#!/bin/bash
# =============================================================================
# Edge TTS Podcast — 文章抓取脚本（Unix / Git Bash 版，零外部语言运行时）
# =============================================================================
# 纯 bash + curl + 标准 POSIX 工具实现，与 fetch_article.ps1 完全对齐：
#   .ps1: HttpWebRequest 抓取 + regex 解析 + WebUtility.HtmlDecode 解码
#   .sh:  curl          抓取 + sed/awk 解析 + sed 实体替换（覆盖常见实体）
#
# 不依赖 Python / Node / Perl / 任何外部语言运行时。
#
# 用法:
#   bash fetch_article.sh <url>
#
# 工具要求（POSIX/类 Unix 系统自带）:
#   bash 3.2+ / curl / sed / awk / grep / head / wc / mktemp
#
# 输出与 fetch_article.ps1 一致：{"title","url","content","content_length"}
#   content        —— 纯文本（无 Markdown 转换，与 .ps1 一致）
#   content_length —— 中文字符数 + 英文词数（统计于截断前）
#
# 限制:
#   - HTML 实体解码仅覆盖常见命名实体（&amp;&lt;&gt;&quot;&apos;&nbsp;）
#     不处理数字实体（如 &#160; / &#xA0;）—— 现代中文站点大多 UTF-8 直出，
#     实际正文很少遇到
#   - CJK 字符计数需要 UTF-8 locale（Git Bash / 现代 Linux 默认满足）
# =============================================================================

set -u

URL="$1"
if [ -z "$URL" ]; then
  echo "Usage: $0 <url>" >&2
  exit 1
fi

# 确保 UTF-8 locale（Git Bash / 多数现代系统已满足；这里是兜底）
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

# 临时文件
TMPHTML=$(mktemp 2>/dev/null) || { echo "Error: mktemp failed" >&2; exit 1; }
trap 'rm -f "$TMPHTML"' EXIT

# -----------------------------------------------------------------------------
# 1. 抓取：curl 伪装微信浏览器（对应 .ps1 的 HttpWebRequest）
# -----------------------------------------------------------------------------
curl -sSL --max-time 15 \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowsWechat(0xf254101f) XWEB/16389 SideBar Flue" \
  -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
  -H "Referer: https://www.bing.com/" \
  "$URL" -o "$TMPHTML" || { echo "Error: curl failed" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 工具函数：HTML 实体解码（覆盖常见命名实体）
# -----------------------------------------------------------------------------
decode_entities() {
  sed -e 's/&amp;/\&/g' \
      -e 's/&lt;/</g' \
      -e 's/&gt;/>/g' \
      -e 's/&quot;/"/g' \
      -e "s/&apos;/'/g" \
      -e "s/&#39;/'/g" \
      -e 's/&nbsp;/ /g'
}

# -----------------------------------------------------------------------------
# 2. 提取标题：<title>...</title> 优先，<h1>...</h1> 兜底（对应 .ps1 Get-Title）
# -----------------------------------------------------------------------------
TITLE=$(awk '/<title[^>]*>/{flag=1} flag; /<\/title>/{flag=0; exit}' "$TMPHTML" \
  | sed -e 's/<[^>]*>//g' \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//')
TITLE=$(printf '%s' "$TITLE" | decode_entities)
# 去掉站点名后缀（如 " - 站点名"）
TITLE=$(printf '%s' "$TITLE" | sed -E 's/[[:space:]]*[-|_–—][[:space:]].*$//')

if [ -z "$TITLE" ]; then
  H1=$(awk '/<h1[^>]*>/{flag=1} flag; /<\/h1>/{flag=0; exit}' "$TMPHTML" \
    | sed -e 's/<[^>]*>//g' \
          -e 's/^[[:space:]]*//' \
          -e 's/[[:space:]]*$//')
  TITLE=$(printf '%s' "$H1" | decode_entities)
fi

# -----------------------------------------------------------------------------
# 3. 提取主内容（对应 .ps1 同款优先级）
# -----------------------------------------------------------------------------
CONTENT_HTML=""

# 微信特例：content_noencode: JsDecode('\xNN\xNN...')
HEX_RAW=$(grep -oE "content_noencode[[:space:]]*:[[:space:]]*JsDecode[[:space:]]*\([[:space:]]*['\"][^'\"]+['\"][[:space:]]*\)" "$TMPHTML" 2>/dev/null \
  | head -n1 \
  | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")

if [ -n "$HEX_RAW" ]; then
  # printf '%b' 解释 \xNN 转义为实际字节（对应 .ps1 的 MemoryStream + WriteByte）
  CONTENT_HTML=$(printf '%b' "$HEX_RAW")
elif grep -qiE '(id|class)=["'"'"'][^"'"'"']*(rich_media_content|img-content|article-content|post-content|mw-content-text|bodyContent|content_block_0)' "$TMPHTML" 2>/dev/null; then
  CONTENT_HTML=$(awk '/<div[^>]*(rich_media_content|img-content|article-content|post-content|mw-content-text|bodyContent|content_block_0)[^>]*>/{flag=1} flag' "$TMPHTML")
elif grep -qi '<article' "$TMPHTML" 2>/dev/null; then
  CONTENT_HTML=$(awk '/<article[^>]*>/{flag=1} flag' "$TMPHTML")
else
  CONTENT_HTML=$(awk '/<body[^>]*>/{flag=1} flag' "$TMPHTML")
fi

[ -z "$CONTENT_HTML" ] && CONTENT_HTML=$(cat "$TMPHTML")

# -----------------------------------------------------------------------------
# 4. HTML → 纯文本（对应 .ps1 Convert-HtmlToText）
# -----------------------------------------------------------------------------
# sed 默认按行处理，遇到 <li id="..."\nclass="..."> 这种跨行属性会漏掉 >。
# 先用 paste -sd ' ' 把全部 HTML 压成一行再处理——HTML 内的换行本就是无意义空白。
TEXT=$(printf '%s' "$CONTENT_HTML" | paste -sd ' ' -)

# 去除脚本/样式/注释（必须先于标签剥离，否则 <script src="x"> 会漏掉）
TEXT=$(printf '%s' "$TEXT" | sed \
  -e 's/<script[^>]*>.*<\/script>//gI' \
  -e 's/<style[^>]*>.*<\/style>//gI' \
  -e 's/<noscript[^>]*>.*<\/noscript>//gI' \
  -e 's/<!--.*-->//g')

# 块级标签结束处插入换行（保留段落结构）
TEXT=$(printf '%s' "$TEXT" | sed -E 's#<(br|/p|/div|/h[1-6]|/li|/tr|/section|/article)[^>]*>#\n#gI')

# 去其余标签（此时 HTML 已被压成单行，所有标签都是单行形式）
TEXT=$(printf '%s' "$TEXT" | sed -E 's#<[^>]*>##g')

# 解码实体
TEXT=$(printf '%s' "$TEXT" | decode_entities)

# 压缩行内连续空白（HTML 源码里 tab/多空格用于缩进，对正文无意义）
TEXT=$(printf '%s' "$TEXT" | sed -E 's#[ \t]+# #g')

# -----------------------------------------------------------------------------
# 5. 逐行清理 + 截断（500 行 / 48000 字符，对应 .ps1 同款）
# -----------------------------------------------------------------------------
TEXT=$(printf '%s\n' "$TEXT" \
  | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (length($0) > 0) print}' \
  | head -n 500)

# 字节级截断（与 .ps1 一致按字符截断的近似；UTF-8 中文按 3 字节计）
TEXT_BYTES=${#TEXT}
if [ "$TEXT_BYTES" -gt 48000 ]; then
  TEXT="${TEXT:0:48000}"$'\n\n... (内容过长，已截断)'
fi

# -----------------------------------------------------------------------------
# 6. 字数统计：CJK 主区字符数 + ASCII 词数
# -----------------------------------------------------------------------------
ZH=$(printf '%s' "$TEXT" | grep -o '[一-龥]' | wc -l | tr -d ' ')
EN=$(printf '%s' "$TEXT" | grep -oE '[A-Za-z0-9]+' | wc -l | tr -d ' ')
CONTENT_LENGTH=$((ZH + EN))

# -----------------------------------------------------------------------------
# 7. JSON 输出（手工 escape，与 .ps1 同款结构）
#    必须转义：\\、"、\t、\r（content 里的真实 \n 由 awk 的 ORS 处理成 \n literal）
# -----------------------------------------------------------------------------
escape_for_json_inline() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e $'s/\t/\\\\t/g' \
    -e $'s/\r/\\\\r/g'
}

TITLE_ESC=$(escape_for_json_inline "$TITLE")
URL_ESC=$(escape_for_json_inline "$URL")

# 多行 content：awk 处理每行的控制字符 + 引号 + 反斜杠，行尾追加 \n (literal 两字符)
CONTENT_ESC=$(printf '%s\n' "$TEXT" | awk '
  BEGIN { ORS = "\\n" }
  {
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\t/, "\\t")
    gsub(/\r/, "\\r")
    print
  }
' | sed '$s/\\n$//')

printf '{"title":"%s","url":"%s","content":"%s","content_length":%d}\n' \
  "$TITLE_ESC" "$URL_ESC" "$CONTENT_ESC" "$CONTENT_LENGTH"