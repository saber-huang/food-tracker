#!/usr/bin/env python3
"""
生成公开的支持网页和隐私政策网页。

网页放在 GitHub 的公开仓库 saber-huang/food-tracker-support 里，用 GitHub Pages 免费发布：
  中文支持页：   https://saber-huang.github.io/food-tracker-support/
  中文隐私政策： https://saber-huang.github.io/food-tracker-support/privacy.html
  英文支持页：   https://saber-huang.github.io/food-tracker-support/en.html
  英文隐私政策： https://saber-huang.github.io/food-tracker-support/privacy-en.html
App Store Connect 里每种语言各填一套「隐私政策网址」和「技术支持网址」。每一页右上角可以切换到另一种语言。

内容和 App 用同一份，不要直接改公开仓库里的网页：
  - 隐私政策：FoodTracker/FoodTracker/Privacy/PrivacyPolicy.md（中文）和 PrivacyPolicy.en.md（英文），
    App 里「我的」→「隐私政策」显示的也是它们
  - 联系邮箱：FoodTracker/FoodTracker/Privacy/SupportInfo.swift 里的 contactEmail
  - 支持页：  site/support.md（中文）和 site/support.en.md（英文）

改了上面任何一个之后，更新网页的步骤：
  1. 在 food-tracker 文件夹里运行：python3 site/build_site.py ~/Desktop/food-tracker-support-files
  2. 打开 https://github.com/saber-huang/food-tracker-support ，点「Add file」→「Upload files」，
     把文件夹里的全部文件（index.html、privacy.html、en.html、privacy-en.html、README.md）拖进去
     （同名文件会被替换），点「Commit changes」
  大约一分钟后网页就会更新。第一次发布（2026-09-30）也是这样在网站上上传的；
  公开仓库要由你本人在网站上操作，Claude Code 的权限检查不允许它自己发布公开内容。

只支持这两份文字里用到的几种 Markdown 写法（和 App 里的 MarkdownBlocks.swift 一样）：
「# 」大标题、「## 」小标题、「- 」列表项、空行分段，以及 **加粗** 和 [链接](网址)。
"""

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # food-tracker 文件夹
SUPPORT_INFO = ROOT / "FoodTracker/FoodTracker/Privacy/SupportInfo.swift"
CONTACT_PLACEHOLDER = "{{contact}}"  # 和 App 里 PrivacyPolicy.contactPlaceholder 一样

# 两种语言各自的文件和网页上的固定文字。App 的正式名字定了以后改 app_name
# （App 里意见反馈邮件的标题也用这个名字，见 Localizable.xcstrings 里的「饮食记录 App 反馈」）
LANGUAGES = {
    "zh": {
        "support_md": ROOT / "site/support.md",
        "privacy_md": ROOT / "FoodTracker/FoodTracker/Privacy/PrivacyPolicy.md",
        "support_file": "index.html",
        "privacy_file": "privacy.html",
        "html_lang": "zh-Hans",
        "app_name": "饮食记录 App",
        "nav_label": "网页导航",
        "nav_support": "支持",
        "nav_privacy": "隐私政策",
        "contact_label": "联系邮箱",
        "support_title": "{app} · 支持",
        "privacy_title": "隐私政策 · {app}",
    },
    "en": {
        "support_md": ROOT / "site/support.en.md",
        "privacy_md": ROOT / "FoodTracker/FoodTracker/Privacy/PrivacyPolicy.en.md",
        "support_file": "en.html",
        "privacy_file": "privacy-en.html",
        "html_lang": "en",
        "app_name": "Food Log App",
        "nav_label": "Site navigation",
        "nav_support": "Support",
        "nav_privacy": "Privacy Policy",
        "contact_label": "Contact",
        "support_title": "{app} · Support",
        "privacy_title": "Privacy Policy · {app}",
    },
}
# 切换语言的链接上写的是另一种语言自己的名字
SWITCH_LABEL = {"zh": "English", "en": "中文"}


def contact_email() -> str:
    """从 SupportInfo.swift 里读出联系邮箱，保证网页和 App 用同一个"""
    match = re.search(r'static let contactEmail = "([^"]*)"', SUPPORT_INFO.read_text(encoding="utf-8"))
    if not match or not match.group(1):
        sys.exit("SupportInfo.swift 里的 contactEmail 是空的：先填好联系邮箱再生成网页")
    return match.group(1)


def parse_blocks(text: str) -> list[tuple[str, str]]:
    """把 Markdown 拆成一块一块：(种类, 文字)。规则和 App 里的 MarkdownBlocks.parse 一样"""
    blocks: list[tuple[str, str]] = []
    paragraph: list[str] = []

    def finish_paragraph():
        if paragraph:
            blocks.append(("paragraph", " ".join(paragraph)))
            paragraph.clear()

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            finish_paragraph()
        elif line.startswith("## "):
            finish_paragraph()
            blocks.append(("heading", line[3:]))
        elif line.startswith("# "):
            finish_paragraph()
            blocks.append(("title", line[2:]))
        elif line.startswith("- "):
            finish_paragraph()
            blocks.append(("bullet", line[2:]))
        else:
            paragraph.append(line)
    finish_paragraph()
    return blocks


def inline(text: str) -> str:
    """一块文字里的加粗和链接。先把 < > & 这些字符转义，别人的文字不会被当成网页代码"""
    out = html.escape(text, quote=True)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    return out


def body_html(blocks: list[tuple[str, str]]) -> str:
    """把块变成网页内容；连续的列表项放进同一个 <ul>"""
    parts: list[str] = []
    in_list = False
    for kind, text in blocks:
        if kind == "bullet" and not in_list:
            parts.append("<ul>")
            in_list = True
        elif kind != "bullet" and in_list:
            parts.append("</ul>")
            in_list = False
        tag = {"title": "h1", "heading": "h2", "paragraph": "p", "bullet": "li"}[kind]
        parts.append(f"<{tag}>{inline(text)}</{tag}>")
    if in_list:
        parts.append("</ul>")
    return "\n".join(parts)


PAGE = """<!doctype html>
<html lang="{html_lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="alternate" hreflang="{other_lang}" href="{other_href}">
<style>
  :root {{ --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --accent: #0066cc; --line: #e5e5ea; color-scheme: light dark; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg: #000000; --fg: #f5f5f7; --muted: #a1a1a6; --accent: #2997ff; --line: #2c2c2e; }}
  }}
  html {{ -webkit-text-size-adjust: 100%; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg);
         font: 17px/1.7 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB",
               "Microsoft YaHei", "Noto Sans CJK SC", sans-serif; }}
  nav, main, footer {{ max-width: 720px; margin: 0 auto; padding-left: 16px; padding-right: 16px; }}
  nav {{ display: flex; gap: 20px; padding-top: 20px; font-size: 15px; }}
  nav a {{ color: var(--muted); text-decoration: none; }}
  nav a[aria-current="page"] {{ color: var(--fg); font-weight: 600; }}
  nav .switch {{ margin-left: auto; }}
  h1 {{ font-size: 28px; line-height: 1.3; margin: 28px 0 12px; }}
  h2 {{ font-size: 20px; line-height: 1.4; margin: 32px 0 8px; }}
  p, li {{ margin: 8px 0; }}
  ul {{ padding-left: 1.3em; }}
  a {{ color: var(--accent); overflow-wrap: anywhere; }}
  footer {{ color: var(--muted); font-size: 14px; margin-top: 40px; padding-top: 16px; padding-bottom: 40px;
           border-top: 1px solid var(--line); }}
</style>
</head>
<body>
<nav aria-label="{nav_label}">
  <a href="{support_href}"{support_current}>{nav_support}</a>
  <a href="{privacy_href}"{privacy_current}>{nav_privacy}</a>
  <a class="switch" href="{other_href}" lang="{other_lang}" hreflang="{other_lang}">{switch_label}</a>
</nav>
<main>
{body}
</main>
<footer>{app_name} · {contact_label} <a href="mailto:{email}">{email}</a></footer>
</body>
</html>
"""


def page(lang: str, kind: str, *, email: str) -> str:
    """一页网页。lang 是 zh 或 en，kind 是 support（支持页）或 privacy（隐私政策）"""
    conf = LANGUAGES[lang]
    other = "en" if lang == "zh" else "zh"
    markdown = conf[f"{kind}_md"].read_text(encoding="utf-8")
    # 网页上把联系邮箱做成可以点的邮件链接（App 里显示成普通文字）
    markdown = markdown.replace(CONTACT_PLACEHOLDER, f"[{email}](mailto:{email})")
    if "{{" in markdown:
        sys.exit(f"{conf[f'{kind}_md'].name}：还有没替换的占位符")
    current_attr = ' aria-current="page"'
    support_href = "./" if conf["support_file"] == "index.html" else conf["support_file"]
    other_file = LANGUAGES[other][f"{kind}_file"]
    return PAGE.format(
        html_lang=conf["html_lang"],
        title=html.escape(conf[f"{kind}_title"].format(app=conf["app_name"])),
        body=body_html(parse_blocks(markdown)),
        nav_label=html.escape(conf["nav_label"]),
        nav_support=html.escape(conf["nav_support"]),
        nav_privacy=html.escape(conf["nav_privacy"]),
        support_href=support_href,
        privacy_href=conf["privacy_file"],
        support_current=current_attr if kind == "support" else "",
        privacy_current=current_attr if kind == "privacy" else "",
        other_lang=LANGUAGES[other]["html_lang"],
        other_href="./" if other_file == "index.html" else other_file,
        switch_label=SWITCH_LABEL[lang],
        app_name=html.escape(conf["app_name"]),
        contact_label=html.escape(conf["contact_label"]),
        email=html.escape(email, quote=True),
    )


README = """# Food Log App · 饮食记录 App

Support pages and privacy policy for the Food Log App, published with GitHub Pages.
这个仓库只放饮食记录 App 的支持网页和隐私政策，用 GitHub Pages 发布：

- Support: https://saber-huang.github.io/food-tracker-support/en.html
- Privacy Policy: https://saber-huang.github.io/food-tracker-support/privacy-en.html
- 支持页：https://saber-huang.github.io/food-tracker-support/
- 隐私政策：https://saber-huang.github.io/food-tracker-support/privacy.html

These pages are generated from the main project; please don't edit them here.
网页由主项目里的 site/build_site.py 生成，请不要直接修改这里的文件。
"""


def main():
    if len(sys.argv) != 2:
        sys.exit("用法：python3 site/build_site.py <输出文件夹，比如 ~/Desktop/food-tracker-support-files>")
    out = Path(sys.argv[1]).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    email = contact_email()
    files = {
        "README.md": README,
        ".nojekyll": "",  # 告诉 GitHub Pages 原样发布这些文件，不用 Jekyll 再处理一遍
    }
    for lang, conf in LANGUAGES.items():
        files[conf["support_file"]] = page(lang, "support", email=email)
        files[conf["privacy_file"]] = page(lang, "privacy", email=email)
    for name, content in files.items():
        (out / name).write_text(content, encoding="utf-8")
        print("写好了", out / name)


if __name__ == "__main__":
    main()
