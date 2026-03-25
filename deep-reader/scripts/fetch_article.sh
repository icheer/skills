#!/bin/bash
# Fallback 方案：使用 curl + Python（BeautifulSoup）转换
# 适用于 Python 环境可用时

URL="$1"
if [ -z "$URL" ]; then
    echo "Usage: $0 <url>" >&2
    exit 1
fi

python -c "
import sys
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

import json, re, subprocess
from bs4 import BeautifulSoup

url = sys.argv[1]

cmd = [
    'curl', '-sL', '--max-time', '15',
    '-H', 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowsWechat(0xf254101f) XWEB/16389 SideBar Flue',
    '-H', 'Accept-Language: zh-CN,zh;q=0.9',
    '-H', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    url
]

proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
raw = proc.stdout.read()
proc.wait()

if not raw:
    print('Error: Failed to fetch URL', file=sys.stderr)
    exit(1)

soup = BeautifulSoup(raw, 'html.parser')

# 提取标题
title = ''
title_tag = soup.find('title')
if title_tag:
    title = re.split(r'\s*[-_]\s*', title_tag.get_text(strip=True))[0].strip()
if not title:
    h1 = soup.find('h1')
    if h1:
        title = h1.get_text(strip=True)

# 微信正文通过 JS 注入 content_noencode，格式：content_noencode: JsDecode('\\x3c...')
content_html = None
for s in soup.find_all('script'):
    if s.string and 'content_noencode' in s.string:
        m = re.search(r\"content_noencode\s*:\s*JsDecode\s*\(\s*['\\\"]([^'\\\"]+)['\\\"]\s*\)\", s.string)
        if m:
            hex_str = m.group(1)
            # JsDecode: \\xAB -> chr(int('AB', 16))
            def hex_decode(m):
                try:
                    return bytes.fromhex(m.group(1)).decode('utf-8', errors='replace')
                except Exception:
                    return m.group(0)
            content_html = re.sub(r'\\\\x([0-9a-fA-F]{2})', hex_decode, hex_str)
            break

if content_html:
    # hex 解码后的 HTML 片段，强制 UTF-8
    inner = BeautifulSoup(content_html, 'html.parser')
    text = inner.get_text(separator='\n', strip=True)
else:
    main = soup.find(id='img-content') or soup.find(class_='rich_media_content') or soup.find('article')
    if main:
        text = main.get_text(separator='\n', strip=True)
    else:
        body = soup.find('body')
        text = body.get_text(separator='\n', strip=True) if body else ''

lines = [l for l in text.split('\n') if l.strip()]
content = '\n'.join(lines[:500])

# 计算字数：用 ord() 避免 shell 环境下 \u 转义问题
def count_length(t):
    zh = sum(1 for c in t if 0x4e00 <= ord(c) <= 0x9fff or 0x3400 <= ord(c) <= 0x4dbf)
    en = len([w for w in t.split() if w and w[0].isascii() and (w[0].isalpha() or w[0].isdigit())])
    return zh + en

result = {
    'title': title,
    'url': url,
    'content': content,
    'content_length': count_length(text)
}
print(json.dumps(result, ensure_ascii=False))
" "$URL"
