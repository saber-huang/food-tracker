"""
控制 AI 费用、防止被滥用的几个小工具。

重要：这里所有数据都放在内存里，后端重启（或者 Render 免费实例休眠再醒来）就会清零。
所以它们只是「第二道防线」，用来拦住随手乱刷；真正的花费硬上限，是在 Claude 控制台设置的
「每月花费上限」。

包含四个工具：
1. RateLimiter：滑动窗口计数，比如「每个 IP 24 小时内最多 40 次」。
   原理：给每个钥匙（设备 ID、IP……）记一个「最近调用时间」的列表；查询时先把窗口之外的旧记录清掉，
   剩下几条就是用了几次。
2. Guard：把「每分钟、每台设备、每个 IP、全站每天」四道限制合在一起。
   一次性检查，全部通过才一起扣次数（中间不会被别的请求插队），只要有一道不通过就一次都不扣。
3. Gate：同时最多让 N 个请求去调用 AI，其余的排队；排太久就告诉用户「服务器忙」。
   这样不会因为一下子来很多请求，把只有 512 MB 内存的小服务器撑爆。
4. ResultCache：相同的食谱请求直接返回上次的结果，不再花钱。
"""

import hashlib
import json
import math
import threading
import time
from collections import OrderedDict, deque
from collections.abc import Callable
from contextlib import contextmanager
from dataclasses import dataclass

DAY = 24 * 3600


class RateLimiter:
    """在 window_seconds 内，每个钥匙最多 limit 次。

    自己不加锁，由外面的 Guard 统一加锁。钥匙数量有上限（max_keys）：
    超过时丢掉最久没用的，避免有人用无数个假设备 ID 把内存撑满。
    """

    def __init__(self, limit: int, window_seconds: float, max_keys: int = 10_000):
        self.limit = limit
        self.window = window_seconds
        self.max_keys = max_keys
        self._calls: OrderedDict[str, deque[float]] = OrderedDict()

    def _live(self, key: str, now: float) -> deque[float] | None:
        """返回这个钥匙窗口内的记录。只查询，不会新建；记录清空了就把钥匙也删掉。"""
        calls = self._calls.get(key)
        if calls is None:
            return None
        while calls and now - calls[0] >= self.window:
            calls.popleft()
        if not calls:
            del self._calls[key]
            return None
        return calls

    def remaining(self, key: str, now: float) -> int:
        calls = self._live(key, now)
        return max(0, self.limit - (len(calls) if calls else 0))

    def retry_after(self, key: str, now: float) -> int:
        """次数用完时，还要等多少秒才能再用（没用完就是 0）"""
        calls = self._live(key, now)
        if not calls or len(calls) < self.limit:
            return 0
        return max(1, math.ceil(self.window - (now - calls[0])))

    def record(self, key: str, now: float) -> None:
        calls = self._live(key, now)
        if calls is None:
            calls = self._calls[key] = deque()
            while len(self._calls) > self.max_keys:
                self._calls.popitem(last=False)  # 丢掉最久没用的钥匙
        else:
            self._calls.move_to_end(key)
        calls.append(now)

    def undo(self, key: str, now: float) -> None:
        """撤销最近的一次记录（用于把没花钱的失败请求的次数还回去）"""
        calls = self._live(key, now)
        if calls:
            calls.pop()
            if not calls:
                del self._calls[key]


class LimitExceeded(Exception):
    """某一道限制用完了。scope 说明是哪一道：burst 每分钟、device 每台设备、ip 每个 IP、site 全站。"""

    def __init__(self, scope: str, retry_after: int):
        super().__init__(f"limit exceeded: {scope}")
        self.scope = scope
        self.retry_after = retry_after


@dataclass(frozen=True)
class Ticket:
    """一次成功的「扣次数」凭证，失败时用它把次数还回去"""

    keys: dict[str, str]


class Guard:
    """一个功能（识别或食谱）的四道限制。

    - burst：每个 IP 每分钟最多几次，防止瞬间猛刷
    - device：每台设备 24 小时最多几次（设备 ID 是 App 自己报的，能被伪造，所以只算「公平限制」）
    - ip：每个 IP 24 小时最多几次（伪造设备 ID 也绕不过）
    - site：全站 24 小时总共最多几次（最后一道防线：不管来多少人，每天最多花这么多钱）
    """

    _ORDER = ("burst", "device", "ip", "site")
    _DAILY = ("device", "ip", "site")

    def __init__(
        self,
        *,
        per_device: int,
        per_ip: int,
        per_ip_per_minute: int,
        per_site: int,
        clock: Callable[[], float] = time.monotonic,
    ):
        self._layers = {
            "burst": RateLimiter(per_ip_per_minute, 60),
            "device": RateLimiter(per_device, DAY),
            "ip": RateLimiter(per_ip, DAY),
            "site": RateLimiter(per_site, DAY, max_keys=1),
        }
        self.per_device = per_device
        self._clock = clock
        # FastAPI 会用多个线程同时处理请求；加锁保证「检查」和「记录」之间不会被别人插队
        self._lock = threading.Lock()

    @staticmethod
    def _keys(device_key: str, ip_key: str) -> dict[str, str]:
        return {"burst": ip_key, "device": device_key, "ip": ip_key, "site": "*"}

    def acquire(self, device_key: str, ip_key: str) -> Ticket:
        """检查全部限制；都通过才一起记一次，否则抛出 LimitExceeded，什么都不记。"""
        keys = self._keys(device_key, ip_key)
        with self._lock:
            now = self._clock()
            for scope in self._ORDER:
                limiter = self._layers[scope]
                if limiter.remaining(keys[scope], now) <= 0:
                    raise LimitExceeded(scope, limiter.retry_after(keys[scope], now))
            for scope in self._ORDER:
                self._layers[scope].record(keys[scope], now)
        return Ticket(keys)

    def refund(self, ticket: Ticket) -> None:
        """没花钱的失败请求，把每天的次数还回去。每分钟的不还：否则有人可以用坏请求无限刷。"""
        with self._lock:
            now = self._clock()
            for scope in self._DAILY:
                self._layers[scope].undo(ticket.keys[scope], now)

    def remaining(self, device_key: str, ip_key: str) -> int:
        """这台设备现在还能用几次：设备、IP、全站三者里最少的那个"""
        keys = self._keys(device_key, ip_key)
        with self._lock:
            now = self._clock()
            return min(self._layers[scope].remaining(keys[scope], now) for scope in self._DAILY)


class Busy(Exception):
    """同时处理的请求太多，排队超时"""


class Gate:
    """同时最多让 slots 个请求进入「照片处理 + 调用 AI」这一段，其余的排队等待。"""

    def __init__(self, slots: int = 2, wait_seconds: float = 25):
        self._semaphore = threading.BoundedSemaphore(max(1, slots))
        self.wait_seconds = wait_seconds

    @contextmanager
    def enter(self):
        if not self._semaphore.acquire(timeout=self.wait_seconds):
            raise Busy()
        try:
            yield
        finally:
            self._semaphore.release()


class ResultCache:
    """结果缓存：保存 ttl_seconds（默认 24 小时），最多 max_entries 条，满了先丢最早的。"""

    def __init__(self, ttl_seconds: int = DAY, max_entries: int = 200):
        self.ttl = ttl_seconds
        self.max_entries = max_entries
        self._entries: OrderedDict[str, tuple[float, object]] = OrderedDict()
        self._lock = threading.Lock()

    @staticmethod
    def key_for(payload: object) -> str:
        """把请求内容变成「指纹」：先按固定顺序转成文字，再算哈希。内容相同，指纹就相同。"""
        text = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    def get(self, key: str):
        """有且没过期就返回保存的结果，否则返回 None"""
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return None
            saved_at, value = entry
            if time.time() - saved_at >= self.ttl:
                del self._entries[key]
                return None
            return value

    def set(self, key: str, value: object) -> None:
        with self._lock:
            self._entries[key] = (time.time(), value)
            self._entries.move_to_end(key)
            while len(self._entries) > self.max_entries:
                self._entries.popitem(last=False)  # 丢掉最早放进来的
