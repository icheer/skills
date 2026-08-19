#!/bin/bash
# =============================================================================
# Deep Reader - 文章抓取脚本（Unix / Git Bash 版，零外部语言运行时）
# =============================================================================
# 纯 bash + curl + 标准 POSIX 工具实现，与 fetch_article.ps1 完全对齐：
#   .ps1: HttpWebRequest 抓取 + regex 解析 + WebUtility.HtmlDecode 解码
#   .sh:  curl          抓取 + sed/awk 解析 + sed 实体替换（覆盖常见实体）
#
# 不依赖 Python / Node / Perl / 任何外部语言运行时。
#
# 用法:
#   bash fetch_article.sh <url> [-o|--output PATH] [-f|--format json|markdown]
#   bash fetch_article.sh -h|--help
#
#   默认行为：JSON 输出到 stdout（向后兼容老调用方）
#
#   -o PATH / --output PATH  输出到指定文件
#                             配合 --format markdown：自动加 "# title" / 来源: url / 字数: N 前缀
#                             配合 --format json：等价于 > PATH 重定向
#   -f FMT  / --format  FMT  输出格式（json|markdown），仅在指定 --output 时生效
#                             缺省 = json
#
# 工具要求（POSIX/类 Unix 系统自带）:
#   bash 3.2+ / curl / sed / awk / grep / head / wc / mktemp
#
# 默认输出（stdout 或 --output 文件）与 fetch_article.ps1 一致：
#   JSON 格式：{"title","url","content","content_length"}
#     content        —— 纯文本（无 Markdown 转换，与 .sh 一致）
#     content_length —— 中文字符数 + 英文词数（统计于截断前）
#   Markdown 格式：
#     # {title}
#     来源: {url}
#     字数: {content_length}
#     {content}
#
# 限制:
#   - HTML 实体解码仅覆盖常见命名实体（&amp;&lt;&gt;&quot;&apos;&nbsp;）
#     不处理数字实体（如 &#160; / &#xA0;）—— 现代中文站点大多 UTF-8 直出，
#     实际正文很少遇到
#   - CJK 字符计数需要 UTF-8 locale（Git Bash / 现代 Linux 默认满足）
# =============================================================================

set -u

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
URL=""
OUTPUT=""
FORMAT="json"

print_usage() {
  cat <<'EOF'
Usage: fetch_article.sh <url> [-o|--output PATH] [-f|--format json|markdown]
                          [-h|--help]

Options:
  -o, --output PATH    输出到指定文件（缺省输出到 stdout）
  -f, --format FMT     输出格式 json|markdown（仅在指定 --output 时生效，缺省 json）
  -h, --help           显示本帮助

Examples:
  # 默认（向后兼容）：JSON 输出到 stdout
  bash fetch_article.sh "https://example.com/article"

  # 显式 JSON 写入文件（等价于 > file.json）
  bash fetch_article.sh "https://example.com/article" -o article.json

  # Markdown 写入文件（自动加 # title / 来源 / 字数 前缀）
  bash fetch_article.sh "https://example.com/article" -o article.md -f markdown
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -f|--format)  FORMAT="$2"; shift 2 ;;
    -h|--help)    print_usage; exit 0 ;;
    --)           shift; break ;;
    -*)           echo "Error: unknown option '$1'" >&2; echo "Try -h for help." >&2; exit 1 ;;
    *)            URL="$1"; shift ;;
  esac
done

if [ -z "$URL" ]; then
  echo "Usage: $0 <url> [-o PATH] [-f json|markdown]" >&2
  exit 1
fi

if [[ "$FORMAT" != "json" && "$FORMAT" != "markdown" ]]; then
  echo "Error: --format must be 'json' or 'markdown' (got '$FORMAT')" >&2
  exit 1
fi

# markdown 格式必须配合 --output（否则 markdown 内容含真换行，stdout 会破坏 shell 管道假设）
if [ "$FORMAT" = "markdown" ] && [ -z "$OUTPUT" ]; then
  echo "Error: --format markdown requires --output PATH" >&2
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
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowswechat(0xf254101f) XWEB/16389 SideBar Flue" \
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
elif grep -qiE '(id|class)=["'"'"'][^"'"'"']*(rich_media_content|article-content|post-content|mw-content-text|bodyContent|content_block_0|posts-expand|content-wrap)' "$TMPHTML" 2>/dev/null; then
  # 注意：匹配从第一个出现的容器开始（content-wrap > content > posts-expand 嵌套关系），
  # 提取到的 HTML 包含整个嵌套区域——满足 Hexo 列表页 / 文章详情页的需求。
  # 同时支持 <div> 和 <section>（Hexo 列表用 <section class="posts-expand">）。
  CONTENT_HTML=$(awk '/<(div|section)[^>]*(rich_media_content|img-content|article-content|post-content|mw-content-text|bodyContent|content_block_0|posts-expand|content-wrap)[^>]*>/{flag=1} flag' "$TMPHTML")
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
# 用 awk 状态机跨行处理 script/style/noscript/注释整块——比 sed 字符类可靠：
#   sed 的 [^<]* 一旦遇到 inline script 里的字面 '<' 字符（如 'replace(/<[^>]+>/g, "")'）
#   就会提前结束匹配，导致半段 JS 残留。
#   awk 状态机按"是否在 <script>...</script> 块内"切分内容，跨行天然安全。
TEXT=$(printf '%s' "$TEXT" | awk '
  BEGIN { in_block = "" }
  {
    line = $0
    while (length(line) > 0) {
      if (in_block == "") {
        # 找下一个块起始位置（最近的 <script / <style / <noscript / <!--）
        i_script = index(line, "<script")
        i_style  = index(line, "<style")
        i_noscr  = index(line, "<noscript")
        i_comm   = index(line, "<!--")
        i_min = 0; kind = ""
        if (i_script > 0 && (i_min == 0 || i_script < i_min)) { i_min = i_script; kind = "script" }
        if (i_style  > 0 && (i_min == 0 || i_style  < i_min)) { i_min = i_style;  kind = "style" }
        if (i_noscr  > 0 && (i_min == 0 || i_noscr  < i_min)) { i_min = i_noscr;  kind = "noscript" }
        if (i_comm   > 0 && (i_min == 0 || i_comm   < i_min)) { i_min = i_comm;   kind = "comment" }
        if (i_min == 0) { print line; line = "" }
        else {
          # 输出块起始之前的内容
          if (i_min > 1) print substr(line, 1, i_min - 1)
          if (kind == "comment") {
            rest = substr(line, i_min + 4)
            end_idx = index(rest, "-->")
            if (end_idx > 0) line = substr(rest, end_idx + 3)
            else { in_block = "comment"; line = "" }
          } else {
            tag_open = substr(line, i_min)
            tag_end = index(tag_open, ">")
            if (tag_end == 0) { in_block = kind; line = "" }
            else {
              rest = substr(tag_open, tag_end + 1)
              end_tag = "</" kind ">"
              end_idx = index(rest, end_tag)
              if (end_idx > 0) line = substr(rest, end_idx + length(end_tag))
              else { in_block = kind; line = "" }
            }
          }
        }
      } else {
        end_tag = "</" in_block ">"
        end_idx = index(line, end_tag)
        if (end_idx > 0) { line = substr(line, end_idx + length(end_tag)); in_block = "" }
        else line = ""
      }
    }
  }
')

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
# 7. 构造 JSON（手工 escape，与 .ps1 同款结构）
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

JSON=$(printf '{"title":"%s","url":"%s","content":"%s","content_length":%d}' \
  "$TITLE_ESC" "$URL_ESC" "$CONTENT_ESC" "$CONTENT_LENGTH")

# -----------------------------------------------------------------------------
# 8. 输出：按 FORMAT / OUTPUT 分流
# -----------------------------------------------------------------------------
if [ -z "$OUTPUT" ]; then
  # 默认：JSON 到 stdout（向后兼容老调用方 `bash fetch.sh URL > /tmp/x.json`）
  printf '%s\n' "$JSON"
else
  # 确保目标目录存在（仅创建父目录，文件本身由下面重定向创建）
  OUTDIR=$(dirname -- "$OUTPUT")
  if [ -n "$OUTDIR" ] && [ ! -d "$OUTDIR" ]; then
    mkdir -p -- "$OUTDIR" || { echo "Error: cannot create dir '$OUTDIR'" >&2; exit 1; }
  fi

  case "$FORMAT" in
    json)
      printf '%s\n' "$JSON" > "$OUTPUT" || { echo "Error: write failed: $OUTPUT" >&2; exit 1; }
      ;;
    markdown)
      # Markdown 格式（人读最终产物）：
      #   # {title}
      #   来源: {url}
      #   字数: {content_length}
      #   {content}
      # TITLE/URL 里有 [、]、# 等 markdown 特殊字符时不影响 # 标题行（一级标题的 # 后是文本），
      # 但为了将来扩展（链接/列表），仍然走 JSON 同款 escape_for_json_inline 把控制字符转义掉。
      printf '# %s\n\n来源: %s\n\n字数: %d\n\n%s\n' \
        "$TITLE" "$URL" "$CONTENT_LENGTH" "$TEXT" > "$OUTPUT" \
        || { echo "Error: write failed: $OUTPUT" >&2; exit 1; }
      ;;
  esac
fi