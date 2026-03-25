#!/bin/bash
# Fallback 方案：使用 curl 抓取 + sed/lynx 转换
# 当 Python 环境不可用时使用

URL="$1"
if [ -z "$URL" ]; then
    echo "Usage: $0 <url>" >&2
    exit 1
fi

# 使用 curl 抓取
CONTENT=$(curl -sL --max-time 15 \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowsWechat(0xf254101f) XWEB/16389 SideBar Flue" \
    -H "Accept-Language: zh-CN,zh;q=0.9" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    "$URL")

if [ -z "$CONTENT" ]; then
    echo "Error: Failed to fetch URL" >&2
    exit 1
fi

# 提取 body 部分
BODY=$(echo "$CONTENT" | sed -n '/<body/I,/<\/body>/Ip' | sed 's/<[^>]*>//g')

# 基本清理
BODY=$(echo "$BODY" | sed 's/[[:space:]]\+/ /g')
BODY=$(echo "$BODY" | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g')

# 截断
echo "$BODY" | head -c 48000