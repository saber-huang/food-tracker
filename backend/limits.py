"""
控制 AI 费用的两个小工具：

1. DailyLimiter（限流）：每个用户在 24 小时内最多调用 N 次。
   原理：给每个用户记一个「最近调用时间」的列表；每次请求先把 24 小时之前的记录清掉，
   剩下的条数就是这 24 小时内用了几次，达到上限就拒绝，不去调用 AI。

2. ResultCache（缓存）：相同的请求在一段时间内直接返回上次的结果，不再花钱调用 AI。
   原理：把请求内容（目标、偏好、忌口……）排序后算一个「指纹」（哈希值），
   用指纹当钥匙保存结果；下次有同样指纹的请求，直接把保存的结果拿出来。

两个工具都把数据放在内存里：后端重启会清零。第一版够用；
以后用户多了、后端有多台机器时，可以换成 Redis 之类的数据库。
"""

import hashlib
import json
import threading
import time
from collections import OrderedDict, deque


class DailyLimiter:
    """每个用户在 window_seconds（默认 24 小时）内最多 limit 次。"""

    def __init__(self, limit: int, window_seconds: int = 24 * 3600):
        self.limit = limit
        self.window = window_seconds
        self._calls: dict[str, deque[float]] = {}
        # FastAPI 会用多个线程同时处理请求，加锁避免两个线程同时改同一份数据
        self._lock = threading.Lock()

    def _prune(self, key: str, now: float) -> deque[float]:
        """清掉时间窗口之外的旧记录，返回这个用户最近的调用时间"""
        calls = self._calls.setdefault(key, deque())
        while calls and now - calls[0] >= self.window:
            calls.popleft()
        return calls

    def remaining(self, key: str) -> int:
        """这个用户还剩几次"""
        with self._lock:
            return max(0, self.limit - len(self._prune(key, time.time())))

    def retry_after_seconds(self, key: str) -> int:
        """次数用完时，还要等多少秒才能再用"""
        with self._lock:
            calls = self._prune(key, time.time())
            if len(calls) < self.limit:
                return 0
            return int(self.window - (time.time() - calls[0])) + 1

    def record(self, key: str) -> None:
        """记一次调用（在真的调用了 AI 之后再记，失败的请求不算次数）"""
        with self._lock:
            self._prune(key, time.time()).append(time.time())


class ResultCache:
    """结果缓存：保存 ttl_seconds（默认 24 小时），最多 max_entries 条，满了先丢最早的。"""

    def __init__(self, ttl_seconds: int = 24 * 3600, max_entries: int = 500):
        self.ttl = ttl_seconds
        self.max_entries = max_entries
        self._entries: OrderedDict[str, tuple[float, object]] = OrderedDict()
        self._lock = threading.Lock()

    @staticmethod
    def key_for(payload: object) -> str:
        """把请求内容变成指纹：先按固定顺序转成文字，再算哈希"""
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
