#!/usr/bin/env bash
# =============================================================================
# context-dev: Context.dev API 的 bash 直调封装(无 MCP / SDK / Python)
# =============================================================================
# 用 curl 直接调用 https://api.context.dev/v1,输出经过"上下文预算"裁剪:
#   stdout  = 摘要行 + 截断后的 JSON 视图(给 agent 看)
#   完整响应 = 始终保存到文件(用 Read/grep/sed 深读,不占 context)
#
# Key 配置: CONTEXT_DEV_API_KEY 环境变量或 ~/.env,只支持一个 key。
# ⚠ 官方明确禁止多账号轮询("multiple accounts trigger our bot detection"):
#    多个 key 轮流使用会导致所有关联账号同时被封、积分清零。
#    若配置中逗号分隔了多个 key,本脚本只会使用第一个,并打印警告。
#
# 依赖: bash + curl + jq
#
# 用法: bash ctx.sh <子命令> [参数]      (bash ctx.sh help 查看全部)
# =============================================================================

set -uo pipefail

BASE_URL="https://api.context.dev/v1"
OUT_DIR="${CTX_OUT_DIR:-${TMPDIR:-/tmp}/context-dev}"
MAX_CHARS=6000        # stdout 中单个字符串字段的默认截断长度
FULL=0                # --full: stdout 不截断
FORCE_KEY=""          # --api-key: 强制指定 key(调试用)
VERBOSE=0

OP=""                 # 当前子命令(用于输出文件名)
HTTP_CODE=""
USED_KEY=""
CURL_TIMEOUT=120
REQ_BODY=""           # 请求体文件路径(空 = 无 body)
REQ_CT="application/json; charset=utf-8"

# =============================================================================
# 日志: 信息走 stderr,stdout 只留摘要 + JSON 视图
# =============================================================================
log()  { printf '%s\n' "[INFO] $*" >&2; }
warn() { printf '%s\n' "[WARN] $*" >&2; }
die()  { printf '%s\n' "[FATAL] $*" >&2; exit 1; }

# =============================================================================
# Key 管理
# =============================================================================
load_raw_keys() {
  if [[ -n "${CONTEXT_DEV_API_KEY:-}" ]]; then
    printf '%s' "$CONTEXT_DEV_API_KEY"
    return
  fi
  if [[ -f "$HOME/.env" ]]; then
    local line
    line="$(grep -m1 '^[[:space:]]*CONTEXT_DEV_API_KEY=' "$HOME/.env" 2>/dev/null | cut -d= -f2-)"
    [[ -n "$line" ]] && { printf '%s' "$line"; return; }
  fi
}

load_keys() {  # 每行输出一个 key
  local raw k
  raw="$(load_raw_keys)"
  [[ -z "$raw" ]] && return 1
  local IFS=$',\n'
  for k in $raw; do
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    [[ -n "$k" ]] && printf '%s\n' "$k"
  done
}

mask_key() {
  local k="$1"
  if (( ${#k} <= 8 )); then printf '****'
  else printf '%s****%s' "${k:0:4}" "${k: -4}"; fi
}

warn_multi_key() {  # 多 key 警告(官方禁止多账号轮询,会触发 bot 检测封号)
  warn "检测到配置了 ${1} 个 key:官方禁止多账号轮询使用(\"multiple accounts trigger our bot detection\"),
      轮流使用多个 key 会导致所有关联账号同时被封、积分清零!
      本脚本只使用第一个 key;请尽快清理配置,只保留一个。"
}

KEYS=()
init_keys() {
  KEYS=()
  local k
  while IFS= read -r k; do KEYS+=("$k"); done < <(load_keys)
  (( ${#KEYS[@]} == 0 )) && die "未配置 Context.dev API Key。
配置方式(任选其一,只需一个 key):
  A. export CONTEXT_DEV_API_KEY=\"your_key\"
  B. ~/.env: CONTEXT_DEV_API_KEY=your_key
获取 Key: https://www.context.dev/auth"
  (( ${#KEYS[@]} > 1 )) && warn_multi_key "${#KEYS[@]}"
  KEYS=("${KEYS[0]}")  # 永远只用第一个
}

# =============================================================================
# 工具函数
# =============================================================================
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

# 请求体临时文件跟踪(退出时清理;parse / raw @file 直接用用户文件,不在此列)
CREATED_TMP=()
new_body() { REQ_BODY="$(mktemp)"; CREATED_TMP+=("$REQ_BODY"); }
cleanup_tmp() { (( ${#CREATED_TMP[@]} )) && rm -f "${CREATED_TMP[@]}"; return 0; }
trap cleanup_tmp EXIT

QPAIRS=()
add_param() {  # add_param <name> <value>  (value 为空则跳过)
  [[ -z "${2:-}" ]] && return
  QPAIRS+=("$(urlencode "$1")=$(urlencode "$2")")
}
build_query() { local IFS='&'; printf '%s' "${QPAIRS[*]}"; }

read_json_arg() {  # @file 表示从文件读;校验为合法 JSON
  local v="$1"
  if [[ "$v" == @* ]]; then
    v="${v#@}"
    [[ -f "$v" ]] || die "文件不存在: $v"
    v="$(cat "$v")"
  fi
  jq -e . >/dev/null 2>&1 <<<"$v" || die "无效 JSON: ${v:0:120}"
  printf '%s' "$v"
}

csv_to_json_array() {  # "a,b,c" -> ["a","b","c"]
  local out="[" first=1 x
  local IFS=','
  for x in $1; do
    x="$(printf '%s' "$x" | xargs)"
    [[ -z "$x" ]] && continue
    (( first )) && first=0 || out+=","
    out+="$(jq -rn --arg v "$x" '$v|tojson')"
  done
  printf '%s]' "$out"
}

formats_to_json() {  # "md,html,shot" -> {"markdown":true,...}(支持别名);未知项 die
  local out="{}" f
  local IFS=','
  for f in $1; do
    case "$f" in
      md|markdown) f="markdown" ;;
      html) ;;
      screenshot|shot) f="screenshot" ;;
      images|imgs) f="images" ;;
      bytes) ;;
      parse|fields) f="parse" ;;
      highlights|hl) f="highlights" ;;
      json) ;;
      product) ;;
      *) die "未知 format: $f (可选 md,html,screenshot,images,bytes,parse,highlights,json,product)" ;;
    esac
    out="$(jq -cn --arg k "$f" --argjson cur "$out" '$cur + {($k): true}')"
  done
  printf '%s' "$out"
}

# =============================================================================
# HTTP 请求(单 key,无轮换;官方禁止多账号轮询,会触发 bot 检测封号)
# =============================================================================
# 调用前需设置: OP, REQ_BODY, REQ_CT, CURL_TIMEOUT, QPAIRS
BODY_FILE=""
HDR_FILE=""
api_request() {  # $1=method $2=path
  local method="$1" path="$2" code key
  mkdir -p "$OUT_DIR"
  # 清理 2 天前的旧响应文件
  find "$OUT_DIR" -maxdepth 1 -type f -mtime +2 -delete 2>/dev/null

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  BODY_FILE="$OUT_DIR/${stamp}-$$-${OP}.json"
  HDR_FILE="${BODY_FILE}.hdr"

  local url="$BASE_URL$path"
  local qs; qs="$(build_query)"
  [[ -n "$qs" ]] && url="$url?$qs"

  key="${KEYS[0]}"
  (( VERBOSE )) && log "请求: $method $url"

  local args=(-sS --max-time "$CURL_TIMEOUT" --retry 2 --retry-delay 1
    -X "$method" -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}'
    -H "Authorization: Bearer $key")
  [[ -n "$REQ_BODY" ]] && args+=(-H "Content-Type: $REQ_CT" --data-binary "@$REQ_BODY")
  code="$(curl "${args[@]}" "$url" 2>/dev/null)" || code="000"

  if [[ "$code" == "000" ]]; then
    warn "网络请求失败(curl 超时/断连),已内置重试仍失败"
    USED_KEY=""; HTTP_CODE="$code"
    return 1
  fi

  USED_KEY="$key"; HTTP_CODE="$code"
  if [[ "$code" == "401" || "$code" == "403" ]]; then
    warn "HTTP $code:key 失效/无权限(也可能是多账号轮询触发了封禁)。不要创建多个账号。"
  elif [[ "$code" == "402" ]]; then
    warn "402 = 积分不足(USAGE_EXCEEDED):raw GET /org/usage 查余额;被拒的操作不扣费,充值/等待月度恢复后重试"
  elif [[ "$code" == "429" ]]; then
    warn "429 = 组织并发限制或每分钟请求上限:改为串行执行、降低并行度,稍后重试(被拒的请求不扣费)"
  fi
  return 0
}

# =============================================================================
# 输出: 摘要行 + 预算视图(完整响应总在文件)
# =============================================================================
JQ_PRELUDE='
def truncstr($n): if type=="string" and length>$n then .[0:$n] + "…[已截断"+((length-$n)|tostring)+"字符,全文见响应文件]" else . end;
def caparr: if type=="array" and length>20 then .[0:20] + ["…[共"+(length|tostring)+"项,仅显示前20,全量见响应文件]"] else . end;
def tidydeep($n): del(.key_metadata,.cache_metadata) | walk(truncstr($n)) | walk(caparr);
def placeholder($shot;$bytes):
  (if ((.screenshot.data? // "") | startswith("data:")) then .screenshot.data = $shot else . end)
  | (if ((.bytes.data?.base64? // "") != "") then .bytes.data = {contentType: .bytes.data.contentType, base64: $bytes} else . end);
'

# emit <jq视图程序> [额外传给 jq 的参数...]
emit() {
  local view="$1"; shift
  local f="$BODY_FILE"
  local credits rem cache size
  credits="$(jq -r '.key_metadata.credits_consumed  // "-"' "$f" 2>/dev/null)" || credits="-"
  rem="$(jq -r '.key_metadata.credits_remaining // "-"' "$f" 2>/dev/null)" || rem="-"
  cache="$(jq -r '.cache_metadata.status // "-"' "$f" 2>/dev/null)" || cache="-"
  size="$(wc -c <"$f" 2>/dev/null | tr -d ' ')"

  echo "[context.dev] $OP | HTTP $HTTP_CODE | credits: ${credits:--} (剩余 ${rem:--}) | cache: ${cache:--} | key: $(mask_key "${USED_KEY:-none}") | 响应 ${size:-0} bytes"

  if [[ "$HTTP_CODE" != 2* ]]; then
    local emsg
    emsg="$(jq -r '"error_code=" + (.error_code // "UNKNOWN") + " | " + ((.message // .error // "无消息") | if type == "string" then . else tostring end)' "$f" 2>/dev/null)" \
      || emsg="body: $(head -c 200 "$f")"
    echo "[context.dev] 错误: HTTP $HTTP_CODE ${emsg}" >&2
    echo "[context.dev] 完整响应: $f" >&2
    exit 1
  fi

  # 二进制输出落盘: 截图 / 原始字节(stdout 只留文件路径)
  local shot_path="" bytes_path="" dataurl ext
  shot_path="${BODY_FILE%.json}.png"; bytes_path="${BODY_FILE%.json}.bin"
  local shot_msg="" bytes_msg=""
  if jq -e '((.screenshot.data // "") | startswith("data:"))' "$f" >/dev/null 2>&1; then
    dataurl="$(jq -r '.screenshot.data' "$f")"
    ext="${dataurl%%;base64,*}"; ext="${ext##*/}"
    printf '%s' "${dataurl##*;base64,}" | base64 -d >"$shot_path" 2>/dev/null \
      && shot_msg="截图已保存: $shot_path (${ext:-png})"
  fi
  if jq -e '(.bytes.data.base64 // "") != ""' "$f" >/dev/null 2>&1; then
    jq -r '.bytes.data.base64' "$f" | base64 -d >"$bytes_path" 2>/dev/null \
      && bytes_msg="原始字节已保存: $bytes_path"
  fi

  echo "[context.dev] 完整响应: $f"
  [[ -n "$shot_msg" ]]  && echo "[context.dev] $shot_msg"
  [[ -n "$bytes_msg" ]] && echo "[context.dev] $bytes_msg"

  # 非 JSON 响应(raw 场景): 原样截断输出
  if ! jq -e . "$f" >/dev/null 2>&1; then
    echo "[context.dev] 响应非 JSON,前 $MAX_CHARS 字节:"
    head -c "$MAX_CHARS" "$f"; echo
    return 0
  fi

  local tmpview; tmpview="$(mktemp)"
  jq -c --arg shot "[PNG 已保存: $shot_path]" --arg bytes "[base64 已保存: $bytes_path]" \
    "$JQ_PRELUDE
placeholder(\$shot;\$bytes)" "$f" >"$tmpview" 2>/dev/null || cp "$f" "$tmpview"

  if (( FULL )); then
    jq -c '.' "$tmpview"
  else
    jq -c --argjson mc "$MAX_CHARS" "$@" "$JQ_PRELUDE
$view" "$tmpview" 2>/dev/null \
      || { warn "视图处理失败,回退为通用截断视图"; jq -c --argjson mc "$MAX_CHARS" "$JQ_PRELUDE
tidydeep(\$mc)" "$tmpview"; }
  fi
  rm -f "$tmpview"
}

# =============================================================================
# 子命令实现
# =============================================================================
cmd_scrape() {
  OP="scrape"; CURL_TIMEOUT=150
  local url="" fmts="md" hlq="" jschema="" jinstr="" prules="" fresh=0 country="" maxage="" timeout_ms="" partial=0 main_only=1 waitfor=""
  local fullpage=0 shot_sel="" parser="" parser_limit="" parser_sort="" prefer_md=0 page_numbers=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --formats) fmts="$2"; shift 2 ;;
      --formats=*) fmts="${1#*=}"; shift ;;
      --query) hlq="$2"; shift 2 ;;
      --schema) jschema="$(read_json_arg "$2")"; shift 2 ;;
      --instructions) jinstr="$2"; shift 2 ;;
      --rules) prules="$(read_json_arg "$2")"; shift 2 ;;
      --parser) parser="$2"; shift 2 ;;
      --parser-limit) parser_limit="$2"; shift 2 ;;
      --parser-sort) parser_sort="$2"; shift 2 ;;
      --prefer-md) prefer_md=1; shift ;;
      --page-numbers) page_numbers=1; shift ;;
      --fresh) fresh=1; shift ;;
      --max-age) maxage="$2"; shift 2 ;;
      --country) country="$2"; shift 2 ;;
      --wait-for) waitfor="$2"; shift 2 ;;
      --timeout) timeout_ms="$2"; shift 2 ;;
      --partial) partial=1; shift ;;
      --no-main-content) main_only=0; shift ;;
      --full-page) fullpage=1; shift ;;
      --shot-selector) shot_sel="$2"; shift 2 ;;
      -*) die "scrape: 未知参数 $1 (viewport/theme/矩形截图等未暴露参数请用 raw)" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  url="${positional[0]:-}"
  [[ -z "$url" ]] && die "用法: ctx.sh scrape <url> [--formats md,html,...] [--query Q] [--schema JSON] [--parser NAME] ..."
  [[ "$url" != *'://'* ]] && url="https://$url"
  [[ -n "$parser" && -n "$prules" ]] && die "--parser(预置解析器)与 --rules(自定义CSS规则)互斥"

  local fmt_json
  fmt_json="$(formats_to_json "$fmts")"
  # 隐式格式联动:给了专用参数就自动开启对应 format,漏写 --formats 也不会静默丢结果
  [[ -n "$prules" || -n "$parser" ]] && fmt_json="$(jq -cn --argjson f "$fmt_json" '$f + {parse:true}')"
  [[ -n "$jschema" ]] && fmt_json="$(jq -cn --argjson f "$fmt_json" '$f + {json:true}')"
  [[ -n "$hlq" ]] && fmt_json="$(jq -cn --argjson f "$fmt_json" '$f + {highlights:true}')"

  local p
  p="$(jq -cn --arg u "$url" --argjson f "$fmt_json" '{url:$u, formats:$f}')"
  [[ -n "$hlq" ]] && p="$(jq -cn --arg q "$hlq" --argjson p "$p" '$p + {highlightsParams:{query:$q}}')"
  if [[ -n "$jschema" ]]; then
    p="$(jq -cn --argjson s "$jschema" --argjson p "$p" '$p + {jsonParams:{schema:$s}}')"
    [[ -n "$jinstr" ]] && p="$(jq -cn --arg i "$jinstr" --argjson p "$p" '$p + {jsonParams:($p.jsonParams + {instructions:$i})}')"
  fi
  [[ -n "$prules" ]] && p="$(jq -cn --argjson r "$prules" --argjson p "$p" '$p + {parseParams:{rules:$r}}')"
  if [[ -n "$parser" ]]; then
    local pp
    pp="$(jq -cn --arg n "$parser" '{type:"prebuilt", parser:$n}')"
    [[ -n "$parser_limit" ]] && pp="$(jq -cn --argjson l "$parser_limit" --argjson pp "$pp" '$pp + {limit:$l}')"
    [[ -n "$parser_sort" ]] && pp="$(jq -cn --arg s "$parser_sort" --argjson pp "$pp" '$pp + {sort:$s}')"
    p="$(jq -cn --argjson pp "$pp" --argjson p "$p" '$p + {parseParams:$pp}')"
  fi
  (( main_only )) && p="$(jq -cn --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {mainContentOnly:true})}')"
  [[ -n "$country" ]] && p="$(jq -cn --arg c "$country" --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {country:$c})}')"
  [[ -n "$waitfor" ]] && p="$(jq -cn --arg w "$waitfor" --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {waitFor:($w|test("^[0-9]+$")|if . then ($w|tonumber) else $w end)})}')"
  (( page_numbers )) && p="$(jq -cn --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {parsers:(($p.sharedParams.parsers // {}) + {pdf:{includeNumberedPages:true}})})}')"
  (( prefer_md )) && p="$(jq -cn --argjson p "$p" '$p + {markdownParams:($p.markdownParams + {sourcePreference:["markdown-direct","html-conversion"]})}')"
  if [[ -n "$shot_sel" ]]; then
    p="$(jq -cn --arg s "$shot_sel" --argjson p "$p" '$p + {screenshotParams:{area:{selector:$s}}}')"
  elif (( fullpage )); then
    p="$(jq -cn --argjson p "$p" '$p + {screenshotParams:{area:"fullPage"}}')"
  fi
  # 整页/元素截图渲染慢(长页面可达数分钟),放宽 curl 超时
  (( fullpage || ${#shot_sel} )) && CURL_TIMEOUT=280
  (( fresh )) && p="$(jq -cn --argjson p "$p" '$p + {maxAgeMs:0}')"
  [[ -n "$maxage" ]] && p="$(jq -cn --argjson ms "$maxage" --argjson p "$p" '$p + {maxAgeMs:$ms}')"
  if [[ -n "$timeout_ms" || $partial == 1 ]]; then
    p="$(jq -cn --argjson ms "${timeout_ms:-30000}" --argjson p "$p" '$p + {timeoutOpts:{milliseconds:$ms, behavior:"return-partial"}}')"
  fi

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/scrape || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_extract() {
  OP="extract"; CURL_TIMEOUT=150
  local url="" schema="" instr="" fact=0 follow=0 maxpages="" maxdepth=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --schema) schema="$(read_json_arg "$2")"; shift 2 ;;
      --instructions) instr="$2"; shift 2 ;;
      --fact-check) fact=1; shift ;;
      --follow-subdomains) follow=1; shift ;;
      --max-pages) maxpages="$2"; shift 2 ;;
      --max-depth) maxdepth="$2"; shift 2 ;;
      -*) die "extract: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  url="${positional[0]:-}"
  [[ -z "$url" ]] && die "用法: ctx.sh extract <url> --schema '<JSON Schema>' [--instructions S] [--max-pages N(默认5,上限50)]"
  [[ -z "$schema" ]] && die "extract 需要 --schema (JSON Schema,如 '{\"type\":\"object\",\"properties\":{...}}')"
  [[ "$url" == *'://'* ]] || url="https://$url"

  local p
  p="$(jq -cn --arg u "$url" --argjson s "$schema" '{url:$u, schema:$s}')"
  [[ -n "$instr" ]] && p="$(jq -cn --arg i "$instr" --argjson p "$p" '$p + {instructions:$i}')"
  (( fact )) && p="$(jq -cn --argjson p "$p" '$p + {factCheck:true}')"
  (( follow )) && p="$(jq -cn --argjson p "$p" '$p + {followSubdomains:true}')"
  [[ -n "$maxpages" ]] && p="$(jq -cn --argjson n "$maxpages" --argjson p "$p" '$p + {maxPages:$n}')"
  [[ -n "$maxdepth" ]] && p="$(jq -cn --argjson d "$maxdepth" --argjson p "$p" '$p + {maxDepth:$d}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/extract || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_search() {
  OP="search"; CURL_TIMEOUT=120
  local num="" freshness="" include="" exclude="" country="" languages="" desc_chars="" markdown=0 highlights=0 fanout=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --num|--num-results) num="$2"; shift 2 ;;
      --num=*) num="${1#*=}"; shift ;;
      --freshness) freshness="$2"; shift 2 ;;
      --include) include="$2"; shift 2 ;;
      --exclude) exclude="$2"; shift 2 ;;
      --country) country="$2"; shift 2 ;;
      --languages) languages="$2"; shift 2 ;;
      --desc-chars) desc_chars="$2"; shift 2 ;;
      --markdown) markdown=1; shift ;;
      --highlights) highlights=1; shift ;;
      --fanout) fanout=1; shift ;;
      -*) die "search: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh search <query> [--num 1-100] [--markdown] [--highlights] [--freshness last_week] [--languages en,de] ..."
  local query="${positional[*]}"

  local p
  p="$(jq -cn --arg q "$query" '{query:$q}')"
  if [[ -n "$num" ]]; then
    (( num < 1 )) && { warn "--num 下限为 1,已自动调整为 1"; num=1; }
    (( num > 100 )) && { warn "--num 上限为 100,已自动调整为 100"; num=100; }
    p="$(jq -cn --argjson n "$num" --argjson p "$p" '$p + {numResults:$n}')"
  fi
  [[ -n "$freshness" ]] && p="$(jq -cn --arg f "$freshness" --argjson p "$p" '$p + {freshness:$f}')"
  [[ -n "$include" ]] && p="$(jq -cn --argjson d "$(csv_to_json_array "$include")" --argjson p "$p" '$p + {includeDomains:$d}')"
  [[ -n "$exclude" ]] && p="$(jq -cn --argjson d "$(csv_to_json_array "$exclude")" --argjson p "$p" '$p + {excludeDomains:$d}')"
  [[ -n "$country" ]] && p="$(jq -cn --arg c "$country" --argjson p "$p" '$p + {country:$c}')"
  [[ -n "$languages" ]] && p="$(jq -cn --argjson l "$(csv_to_json_array "$languages")" --argjson p "$p" '$p + {languages:$l}')"
  (( fanout )) && p="$(jq -cn --argjson p "$p" '$p + {queryFanout:true}')"
  (( markdown )) && p="$(jq -cn --argjson p "$p" '$p + {markdownOptions:{enabled:true, useMainContentOnly:true}}')"
  (( highlights )) && p="$(jq -cn --argjson p "$p" '$p + {highlightsOptions:{enabled:true}}')"
  # 默认 280 字符/条做上下文预算;--desc-chars 可调大(如新闻类查询拿匹配段落)
  p="$(jq -cn --argjson dc "${desc_chars:-280}" --argjson p "$p" '$p + {descriptionMaxCharacters:$dc}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/search || die "请求失败(HTTP $HTTP_CODE)"
  emit 'del(.key_metadata,.cache_metadata) | {partial, query, results: [.results[] | {url, title, description, relevance, markdown: ((.markdown.markdown // null) | if . != null then truncstr(1000) else null end), highlights: ((.highlights.highlights // null) | if . != null then map(truncstr(400)) else null end)}]}'
}

cmd_answers() {
  OP="answers"
  local mode="fast" jformat=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --json-format) jformat="$(read_json_arg "$2")"; shift 2 ;;
      -*) die "answers: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh answers <task> [--mode fast|ultra] [--json-format JSON]"
  [[ "$mode" == "fast" || "$mode" == "ultra" ]] || die "--mode 只能是 fast 或 ultra"
  local task="${positional[*]}"
  CURL_TIMEOUT=240; [[ "$mode" == "ultra" ]] && CURL_TIMEOUT=320

  local p
  p="$(jq -cn --arg t "$task" --arg m "$mode" '{task:$t, mode:$m}')"
  [[ -n "$jformat" ]] && p="$(jq -cn --argjson j "$jformat" --argjson p "$p" '$p + {json_format:$j}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/answers || die "请求失败(HTTP $HTTP_CODE)"
  emit 'del(.key_metadata,.cache_metadata) | {partial, answer: (.json_content | walk(truncstr($mc))), sources: [(.sources // [])[0:20][] | if type=="object" then {url, title: ((.title // "") | .[0:120])} else . end]}'
}

cmd_map() {
  OP="map"; CURL_TIMEOUT=60
  local domain="" maxlinks="" regex="" exregex="" search="" subdomains=0 maxitems=50
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-links) maxlinks="$2"; shift 2 ;;
      --regex) regex="$2"; shift 2 ;;
      --exclude-regex) exregex="$2"; shift 2 ;;
      --search) search="$2"; shift 2 ;;
      --subdomains) subdomains=1; shift ;;
      --max-items) maxitems="$2"; shift 2 ;;
      -*) die "map: 未知参数 $1" ;;
      *) [[ -z "$domain" ]] && domain="$1"; shift ;;
    esac
  done
  [[ -z "$domain" ]] && die "用法: ctx.sh map <domain> [--max-links N] [--regex R] [--exclude-regex R] [--search S] [--subdomains] [--max-items N]"
  domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"

  add_param domain "$domain"
  (( subdomains )) && add_param includeSubdomains "true"
  [[ -n "$maxlinks" ]] && add_param maxLinks "$maxlinks"
  [[ -n "$regex" ]] && add_param urlRegex "$regex"
  [[ -n "$exregex" ]] && add_param excludeUrlRegex "$exregex"
  [[ -n "$search" ]] && add_param search "$search"

  api_request GET /web/urls || die "请求失败(HTTP $HTTP_CODE)"
  [[ "$maxitems" =~ ^[0-9]+$ ]] || die "--max-items 必须是数字"
  emit 'del(.key_metadata,.cache_metadata) | {success, domain, partial, total: (.urls|length), urls: ([.urls[] | if type=="object" then {url, title} else . end] | .[0:$mi]), note: (if (.urls|length) > $mi then "仅显示前 "+($mi|tostring)+" 条,全量见响应文件" else null end)}' --argjson mi "$maxitems"
}

cmd_crawl() {
  OP="crawl"; CURL_TIMEOUT=600
  local url="" maxpages=10 maxdepth="" regex="" exregex="" main_only=0 prefer_md=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-pages) maxpages="$2"; shift 2 ;;
      --max-depth) maxdepth="$2"; shift 2 ;;
      --regex) regex="$2"; shift 2 ;;
      --exclude-regex) exregex="$2"; shift 2 ;;
      --main-content) main_only=1; shift ;;
      --prefer-md) prefer_md=1; shift ;;
      -*) die "crawl: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  url="${positional[0]:-}"
  [[ -z "$url" ]] && die "用法: ctx.sh crawl <url> [--max-pages N(默认10,上限500)] [--regex R] [--exclude-regex R] [--main-content] [--prefer-md]
注意: 每页消耗 1 credit;stdout 默认只列页面清单,全文在响应文件"

  local p
  p="$(jq -cn --arg u "$url" --argjson mp "$maxpages" '{url:$u, maxPages:$mp}')"
  [[ -n "$maxdepth" ]] && p="$(jq -cn --argjson d "$maxdepth" --argjson p "$p" '$p + {maxDepth:$d}')"
  [[ -n "$regex" ]] && p="$(jq -cn --arg r "$regex" --argjson p "$p" '$p + {urlRegex:$r}')"
  [[ -n "$exregex" ]] && p="$(jq -cn --arg r "$exregex" --argjson p "$p" '$p + {excludeUrlRegex:$r}')"
  (( main_only )) && p="$(jq -cn --argjson p "$p" '$p + {useMainContentOnly:true}')"
  (( prefer_md )) && p="$(jq -cn --argjson p "$p" '$p + {sourcePreference:["markdown-direct","html-conversion"]}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/crawl || die "请求失败(HTTP $HTTP_CODE)"
  emit 'del(.key_metadata,.cache_metadata) | {partial, total: (.results|length), stats: (.metadata // null), pages: [.results[] | {url: (.metadata.sourceUrl // .url // null), title: (.metadata.title // null), ok: (.metadata.success // null), code: (if (.markdown|type)=="object" then .markdown.code else null end)}]}'
}

cmd_brand() {
  OP="brand"; CURL_TIMEOUT=100
  local domain="" name="" email="" ticker="" exchange="" direct="" transaction="" cgl=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --email) email="$2"; shift 2 ;;
      --ticker) ticker="$2"; shift 2 ;;
      --exchange) exchange="$2"; shift 2 ;;
      --direct-url) direct="$2"; shift 2 ;;
      --transaction) transaction="$2"; shift 2 ;;
      --country-gl) cgl="$2"; shift 2 ;;
      -*) die "brand: 未知参数 $1" ;;
      *) shift ;;
    esac
  done
  local n=0 v
  for v in "$domain" "$name" "$email" "$ticker" "$direct" "$transaction"; do [[ -n "$v" ]] && n=$((n + 1)); done
  (( n == 0 )) && die "用法: ctx.sh brand --domain stripe.com | --name 'Stripe' | --email x@corp.com | --ticker T [--exchange E] | --direct-url U | --transaction '描述'"
  (( n > 1 )) && die "brand 只能指定一种查询方式"

  local p
  if [[ -n "$domain" ]]; then
    domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
    p="$(jq -cn --arg d "$domain" '{type:"by_domain", domain:$d}')"
  elif [[ -n "$name" ]]; then
    p="$(jq -cn --arg n "$name" '{type:"by_name", name:$n}')"
    [[ -n "$cgl" ]] && p="$(jq -cn --arg c "$cgl" --argjson p "$p" '$p + {country_gl:$c}')"
  elif [[ -n "$email" ]]; then
    p="$(jq -cn --arg e "$email" '{type:"by_email", email:$e}')"
  elif [[ -n "$ticker" ]]; then
    p="$(jq -cn --arg t "$ticker" '{type:"by_ticker", ticker:$t}')"
    [[ -n "$exchange" ]] && p="$(jq -cn --arg e "$exchange" --argjson p "$p" '$p + {ticker_exchange:$e}')"
  elif [[ -n "$direct" ]]; then
    p="$(jq -cn --arg u "$direct" '{type:"by_direct_url", direct_url:$u}')"
  else
    p="$(jq -cn --arg t "$transaction" '{type:"by_transaction", transaction_info:$t}')"
  fi
  # 未缓存域名冷查询需 ≥60s,否则 422 COLD_DOMAIN_TIMEOUT_TOO_LOW
  p="$(jq -cn --argjson p "$p" '$p + {timeoutOpts:{milliseconds:75000}}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /brand/retrieve || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_brandsearch() {
  OP="brandsearch"; CURL_TIMEOUT=30
  local country="" language=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --country) country="$2"; shift 2 ;;
      --language) language="$2"; shift 2 ;;
      -*) die "brandsearch: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh brandsearch <query> [--country US] [--language english]"
  add_param query "${positional[*]}"
  [[ -n "$country" ]] && add_param country "$(printf '%s' "$country" | tr 'a-z' 'A-Z')"
  [[ -n "$language" ]] && add_param language "$language"
  api_request GET /brand/search || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_styleguide() {
  OP="styleguide"; CURL_TIMEOUT=100
  local domain="" scheme=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scheme) scheme="$2"; shift 2 ;;
      -*) die "styleguide: 未知参数 $1" ;;
      *) [[ -z "$domain" ]] && domain="$1"; shift ;;
    esac
  done
  [[ -z "$domain" ]] && die "用法: ctx.sh styleguide <domain> [--scheme light|dark]"
  domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
  add_param domain "$domain"
  [[ -n "$scheme" ]] && add_param colorScheme "$scheme"
  api_request GET /web/styleguide || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_news() {
  OP="news"; CURL_TIMEOUT=60
  local domain="" name="" ticker="" isin="" exchange="" limit="" src_country="" nlquery="" langs=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query) nlquery="$2"; shift 2 ;;
      --domain) domain="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --ticker) ticker="$2"; shift 2 ;;
      --isin) isin="$2"; shift 2 ;;
      --exchange) exchange="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --source-country) src_country="$2"; shift 2 ;;
      --languages) langs="$2"; shift 2 ;;
      -*) die "news: 未知参数 $1" ;;
      *) shift ;;
    esac
  done
  local searchby
  if [[ -n "$nlquery" ]]; then
    [[ -n "$domain$name$ticker$isin" ]] && die "--query(自然语言主题搜索)与 --domain/--name/--ticker/--isin(实体搜索)互斥"
    searchby="$(jq -cn --arg q "$nlquery" '{type:"natural_language", query:$q}')"
  elif [[ -n "$domain" ]]; then
    domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
    searchby="$(jq -cn --arg d "$domain" '{type:"domain", domain:$d}')"
  elif [[ -n "$name" ]]; then
    searchby="$(jq -cn --arg n "$name" '{type:"name", name:$n}')"
  elif [[ -n "$ticker" ]]; then
    searchby="$(jq -cn --arg t "$ticker" '{type:"ticker", ticker:$t}')"
    [[ -n "$exchange" ]] && searchby="$(jq -cn --arg e "$exchange" --argjson p "$searchby" '$p + {exchange:$e}')"
  elif [[ -n "$isin" ]]; then
    searchby="$(jq -cn --arg i "$isin" '{type:"isin", isin:$i}')"
  else
    die "用法: ctx.sh news --query '主题描述'          自然语言新闻搜索(最多100条,按相关性排序)
      或 news --domain x.com | --name 'Company' | --ticker T | --isin I   实体新闻
      可选: --limit N --source-country c1,c2 --languages en,zh"
  fi

  local p
  p="$(jq -cn --argjson sb "$searchby" '{searchBy:$sb}')"
  [[ -n "$limit" ]] && p="$(jq -cn --argjson l "$limit" --argjson p "$p" '$p + {limit:$l}')"
  [[ -n "$src_country" ]] && p="$(jq -cn --argjson c "$(csv_to_json_array "$src_country")" --argjson p "$p" '$p + {filterBy:(($p.filterBy // {}) + {sourceCountry:$c})}')"
  [[ -n "$langs" ]] && p="$(jq -cn --argjson l "$(csv_to_json_array "$langs")" --argjson p "$p" '$p + {filterBy:(($p.filterBy // {}) + {articleLanguage:$l})}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /news/search || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_parse() {
  OP="parse"; CURL_TIMEOUT=180
  local file="" ocr=0 ext="" page_numbers=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ocr) ocr=1; shift ;;
      --page-numbers) page_numbers=1; shift ;;
      --extension) ext="$2"; shift 2 ;;
      -*) die "parse: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  file="${positional[0]:-}"
  [[ -z "$file" || ! -f "$file" ]] && die "用法: ctx.sh parse <file(pdf/docx/...)> [--ocr] [--page-numbers] [--extension ext]"
  [[ -z "$ext" ]] && ext="${file##*.}"
  ext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"

  add_param extension "${ext:-pdf}"
  (( ocr )) && add_param ocr "true"
  (( page_numbers )) && add_param includeNumberedPages "true"
  REQ_CT="application/octet-stream"
  REQ_BODY="$file"  # 二进制文件直接作为请求体
  api_request POST /parse || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

# =============================================================================
# 公司/人物搜索(自然语言查询;无结果的请求免费)
# =============================================================================
cmd_companies() {
  OP="companies"; CURL_TIMEOUT=90
  local mode="fast" countries="" empmin="" empmax="" cursor=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --countries) countries="$2"; shift 2 ;;
      --employees-min) empmin="$2"; shift 2 ;;
      --employees-max) empmax="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      -*) die "companies: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh companies <自然语言描述> [--mode fast|ultra] [--countries US,GB] [--employees-min N] [--employees-max N] [--cursor C]
例: companies 'solar startups in California that raised a Series B'
费用: fast 2 credits/有结果的页;ultra 10(更强,最多约20秒);无结果免费"
  [[ "$mode" == "fast" || "$mode" == "ultra" ]] || die "--mode 只能是 fast 或 ultra"
  local query="${positional[*]}"

  local p filters="{}"
  p="$(jq -cn --arg q "$query" --arg m "$mode" '{query:$q, mode:$m}')"
  [[ -n "$countries" ]] && filters="$(jq -cn --argjson c "$(csv_to_json_array "$(printf '%s' "$countries" | tr 'a-z' 'A-Z')")" --argjson f "$filters" '$f + {countries:$c}')"
  [[ -n "$empmin" ]] && filters="$(jq -cn --argjson n "$empmin" --argjson f "$filters" '$f + {employees_min:$n}')"
  [[ -n "$empmax" ]] && filters="$(jq -cn --argjson n "$empmax" --argjson f "$filters" '$f + {employees_max:$n}')"
  [[ "$filters" != "{}" ]] && p="$(jq -cn --argjson f "$filters" --argjson p "$p" '$p + {filters:$f}')"
  [[ -n "$cursor" ]] && p="$(jq -cn --arg c "$cursor" --argjson p "$p" '$p + {cursor:$c}')"

  new_body; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /company/search || die "请求失败(HTTP $HTTP_CODE)"
  emit 'del(.key_metadata,.request_id) | {total: (.results|length), next_cursor, companies: [.results[] | {name, domain, description: ((.description // null) | if . then truncstr(200) else . end), industries, organization_type, operating_status, founded_year, stock_symbols, headquarters: {country_code, region, city}, employees, revenue, funding: {stage, total_usd, latest_round}, socials}]}'
}

cmd_people() {
  local action="${1:-}"; shift || true
  case "$action" in
    search)
      OP="people-search"; CURL_TIMEOUT=90
      local mode="fast" countries="" expmin="" expmax="" cursor=""
      local positional=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --mode) mode="$2"; shift 2 ;;
          --countries) countries="$2"; shift 2 ;;
          --exp-min|--experience-min) expmin="$2"; shift 2 ;;
          --exp-max|--experience-max) expmax="$2"; shift 2 ;;
          --cursor) cursor="$2"; shift 2 ;;
          -*) die "people search: 未知参数 $1" ;;
          *) positional+=("$1"); shift ;;
        esac
      done
      (( ${#positional[@]} == 0 )) && die "用法: ctx.sh people search <自然语言描述> [--mode fast|ultra] [--countries US] [--exp-min N] [--exp-max N] [--cursor C]
例: people search 'VPs of sales at solar companies in California'
费用: fast 10 credits/有结果的页;ultra 50(最多约30秒);无结果免费"
      [[ "$mode" == "fast" || "$mode" == "ultra" ]] || die "--mode 只能是 fast 或 ultra"
      local query="${positional[*]}"

      local p filters="{}"
      p="$(jq -cn --arg q "$query" --arg m "$mode" '{query:$q, mode:$m}')"
      [[ -n "$countries" ]] && filters="$(jq -cn --argjson c "$(csv_to_json_array "$(printf '%s' "$countries" | tr 'a-z' 'A-Z')")" --argjson f "$filters" '$f + {countries:$c}')"
      [[ -n "$expmin" ]] && filters="$(jq -cn --argjson n "$expmin" --argjson f "$filters" '$f + {years_of_experience_min:$n}')"
      [[ -n "$expmax" ]] && filters="$(jq -cn --argjson n "$expmax" --argjson f "$filters" '$f + {years_of_experience_max:$n}')"
      [[ "$filters" != "{}" ]] && p="$(jq -cn --argjson f "$filters" --argjson p "$p" '$p + {filters:$f}')"
      [[ -n "$cursor" ]] && p="$(jq -cn --arg c "$cursor" --argjson p "$p" '$p + {cursor:$c}')"

      new_body; printf '%s' "$p" >"$REQ_BODY"
      api_request POST /people/search || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | {total: (.results|length), next_cursor, people: [.results[] | {name, description: ((.description // null) | if . then truncstr(150) else . end), role: {title: .role.title, seniority: .role.seniority, company: .role.company}, location: {country_code: .location.country_code, city: .location.city}, years_of_experience, is_founder, skills, profiles, match}]}'
      ;;
    enrich)
      OP="people-enrich"; CURL_TIMEOUT=60
      local email="" first="" last="" company="" company_domain="" linkedin="" other_url=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --email) email="$2"; shift 2 ;;
          --first) first="$2"; shift 2 ;;
          --last) last="$2"; shift 2 ;;
          --company) company="$2"; shift 2 ;;
          --company-domain) company_domain="$2"; shift 2 ;;
          --linkedin) linkedin="$2"; shift 2 ;;
          --profile) other_url="$2"; shift 2 ;;
          -*) die "people enrich: 未知参数 $1" ;;
          *) shift ;;
        esac
      done
      (( ${#email}${#first}${#last}${#linkedin}${#other_url} == 0 )) && die "用法: ctx.sh people enrich --email E | --linkedin URL | (--first F --last L [--company C|--company-domain D])
费用: 20 credits/匹配;免费/一次性邮箱域名返回 422"
      local p
      p="$(jq -cn '{}')"
      [[ -n "$email" ]] && p="$(jq -cn --arg e "$email" --argjson p "$p" '$p + {email:$e}')"
      if [[ -n "$first" || -n "$last" ]]; then
        p="$(jq -cn --arg f "$first" --arg l "$last" --argjson p "$p" '$p + {name:{first:($f|if .=="" then null else . end), last:($l|if .=="" then null else . end)}}')"
      fi
      if [[ -n "$company" || -n "$company_domain" ]]; then
        p="$(jq -cn --arg c "$company" --arg d "$company_domain" --argjson p "$p" '$p + {company:{name:($c|if .=="" then null else . end), domain:($d|if .=="" then null else . end)}}')"
      fi
      local socials="[]"
      [[ -n "$linkedin" ]] && socials="$(jq -cn --arg u "$linkedin" '[$u]')"
      [[ -n "$other_url" ]] && socials="$(jq -cn --argjson s "$socials" --arg u "$other_url" '$s + [$u]')"
      (( $(jq '.|length' <<<"$socials") > 0 )) && p="$(jq -cn --argjson s "$socials" --argjson p "$p" '$p + {social_urls:$s}')"

      new_body; printf '%s' "$p" >"$REQ_BODY"
      api_request POST /people/enrich || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    *)
      die "用法: ctx.sh people search <描述>   自然语言找人(10 credits/页,ultra 50)
      ctx.sh people enrich --email E | --linkedin URL | --first F --last L --company C   身份线索匹配(20/match)"
      ;;
  esac
}

# =============================================================================
# 批处理: 异步抓一批 URL 或整站爬取(1 credit/页;免费档同时 1 个活跃 batch)
# =============================================================================
cmd_batch() {
  local action="${1:-}"; shift || true
  case "$action" in
    submit)
      OP="batch"
      local urls=() file="" crawl_url="" fmts="md" parser="" jschema="" main_only=0 maxpages="" regex="" exregex="" langs="" prefer_md=0 page_numbers=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --file) file="$2"; shift 2 ;;
          --crawl) crawl_url="$2"; shift 2 ;;
          --formats) fmts="$2"; shift 2 ;;
          --parser) parser="$2"; shift 2 ;;
          --schema) jschema="$(read_json_arg "$2")"; shift 2 ;;
          --main-content) main_only=1; shift ;;
          --max-pages) maxpages="$2"; shift 2 ;;
          --regex) regex="$2"; shift 2 ;;
          --exclude-regex) exregex="$2"; shift 2 ;;
          --languages) langs="$2"; shift 2 ;;
          --prefer-md) prefer_md=1; shift ;;
          --page-numbers) page_numbers=1; shift ;;
          -*) die "batch submit: 未知参数 $1" ;;
          *) urls+=("$1"); shift ;;
        esac
      done
      local fmt_json; fmt_json="$(formats_to_json "$fmts")"
      [[ -n "$parser" ]] && fmt_json="$(jq -cn --argjson f "$fmt_json" '$f + {parse:true}')"
      [[ -n "$jschema" ]] && fmt_json="$(jq -cn --argjson f "$fmt_json" '$f + {json:true}')"
      local data
      data="$(jq -cn --argjson f "$fmt_json" '{formats:$f}')"
      [[ -n "$jschema" ]] && data="$(jq -cn --argjson s "$jschema" --argjson d "$data" '$d + {jsonParams:{schema:$s}}')"
      if [[ -n "$parser" ]]; then
        data="$(jq -cn --arg n "$parser" --argjson d "$data" '$d + {parseParams:{type:"prebuilt", parser:$n}}')"
      fi
      if (( main_only )); then
        data="$(jq -cn --argjson d "$data" '$d + {sharedParams:(($d.sharedParams // {}) + {mainContentOnly:true})}')"
      fi
      (( prefer_md )) && data="$(jq -cn --argjson d "$data" '$d + {markdownParams:(($d.markdownParams // {}) + {sourcePreference:["markdown-direct","html-conversion"]})}')"
      (( page_numbers )) && data="$(jq -cn --argjson d "$data" '$d + {sharedParams:(($d.sharedParams // {}) + {parsers:(($d.sharedParams.parsers // {}) + {pdf:{includeNumberedPages:true}})})}')"

      local input
      if [[ -n "$crawl_url" ]]; then
        [[ ${#urls[@]} -gt 0 || -n "$file" ]] && die "--crawl(整站爬取)与 URL 列表互斥"
        local controls="{}"
        [[ -n "$maxpages" ]] && controls="$(jq -cn --argjson n "$maxpages" --argjson c "$controls" '$c + {maxUrls:$n}')"
        [[ -n "$regex" ]] && controls="$(jq -cn --arg r "$regex" --argjson c "$controls" '$c + {regex:$r}')"
        [[ -n "$exregex" ]] && controls="$(jq -cn --arg r "$exregex" --argjson c "$controls" '$c + {excludeRegex:$r}')"
        if [[ -n "$langs" ]]; then
          if [[ "$langs" == "same_as_start_url" ]]; then
            controls="$(jq -cn --arg l "$langs" --argjson c "$controls" '$c + {languages:$l}')"
          else
            controls="$(jq -cn --argjson l "$(csv_to_json_array "$langs")" --argjson c "$controls" '$c + {languages:$l}')"
          fi
        fi
        input="$(jq -cn --arg u "$crawl_url" --argjson c "$controls" --argjson d "$data" '{mode:"crawl", data:($d + {source:{type:"start_url", url:$u, controls:$c}})}')"
      else
        [[ -n "$file" ]] && { [[ -f "$file" ]] || die "文件不存在: $file"; while IFS= read -r u; do [[ -n "$u" ]] && urls+=("$u"); done <"$file"; }
        (( ${#urls[@]} == 0 )) && die "用法: ctx.sh batch submit <url> [url...] | --file urls.txt | --crawl <start-url>
  [--formats md,html,...] [--parser NAME] [--schema JSON] [--main-content]
  (--crawl 专属: --max-pages N --regex R --exclude-regex R)
费用: 1 credit/页(失败页退回);提交即预留积分;结果保留 180 天"
        input="$(jq -cn --argjson d "$data" --args '{mode:"scrape", data:($d + {urls:[$ARGS.positional[] | {url: .}]})}' -- "${urls[@]}")"
      fi

      local p; p="$(jq -cn --argjson i "$input" '{input:$i}')"
      new_body; printf '%s' "$p" >"$REQ_BODY"
      api_request POST /batch/submit || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | {batch_id: (.id // .batch_id // null), status, intake, credits: (.credits // null), note: "稍后用 batch status <id> 查进度,batch results <id> 取结果"}'
      ;;
    status)
      OP="batch"; CURL_TIMEOUT=30
      local id="${1:-}"; [[ -z "$id" ]] && die "用法: ctx.sh batch status <batch_id>"
      api_request GET "/batch/$id" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | {id, status, progress, credits, failure: (.failure // null), page_errors: ((.page_errors // []) | .[0:5]), results: ((.results // null) | if . then {links: (.links // .)} else . end)}'
      ;;
    results)
      OP="batch"; CURL_TIMEOUT=60
      local id="" limit="20" cursor=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --limit) limit="$2"; shift 2 ;;
          --cursor) cursor="$2"; shift 2 ;;
          -*) die "batch results: 未知参数 $1" ;;
          *) [[ -z "$id" ]] && id="$1"; shift ;;
        esac
      done
      [[ -z "$id" ]] && die "用法: ctx.sh batch results <batch_id> [--limit N] [--cursor C]"
      add_param limit "$limit"
      add_param cursor "$cursor"
      api_request GET "/batch/$id/results" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | {has_more, next_cursor, pages: [.data[] | {url, status, title: (.result.metadata.title // null), error_code: (.error_code // null), credits_used, markdown_chars: ((.result.markdown.data // null) | if . then length else . end)}], note: "每页全文在响应文件里按 url 检索;翻页用 --cursor <next_cursor>"}'
      ;;
    list)
      OP="batch"; CURL_TIMEOUT=30
      api_request GET /batch/list || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    cancel)
      OP="batch"; CURL_TIMEOUT=30
      local id="${1:-}"; [[ -z "$id" ]] && die "用法: ctx.sh batch cancel <batch_id>"
      api_request POST "/batch/$id/cancel" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    rm)
      OP="batch"; CURL_TIMEOUT=30
      local id="${1:-}"; [[ -z "$id" ]] && die "用法: ctx.sh batch rm <batch_id>(删除已完成的 batch 及其结果)"
      api_request DELETE "/batch/$id" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    *)
      die "用法: ctx.sh batch submit <url...|--file F|--crawl U> | status <id> | results <id> [--limit N] | list | cancel <id> | rm <id>"
      ;;
  esac
}

# =============================================================================
# 监控: 定时盯页面/全网搜索,轮询取变更(page 每次 run 1 credit,search 2;查询/列表免费)
# =============================================================================
cmd_monitor() {
  local action="${1:-}"; shift || true
  case "$action" in
    page|search)
      OP="monitor"; CURL_TIMEOUT=60
      local name="" every="" instructions="" exact=0
      local positional=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) name="$2"; shift 2 ;;
          --every) every="$2"; shift 2 ;;
          --instructions) instructions="$2"; shift 2 ;;
          --exact) exact=1; shift ;;
          -*) die "monitor $action: 未知参数 $1" ;;
          *) positional+=("$1"); shift ;;
        esac
      done
      (( ${#positional[@]} == 0 )) && die "用法: ctx.sh monitor page <url> [--name N] [--every 6h|30m|2d|1w] [--instructions '关注什么变化'] [--exact]
      ctx.sh monitor search <query> [--name N] [--every ...] [--instructions '哪类新结果算数'] [--exact]
说明: 创建后立即跑一次基线(计费);默认 AI 判断哪些变化值得报告,--exact 则每次都报;
      page 每次 run 1 credit,search 2;默认无 --every 时用服务端默认周期"
      local target
      if [[ "$action" == "page" ]]; then
        local url="${positional[0]}"; [[ "$url" != *'://'* ]] && url="https://$url"
        target="$(jq -cn --arg u "$url" '{type:"page", url:$u}')"
        [[ -z "$name" ]] && name="$url"
      else
        local query="${positional[*]}"
        target="$(jq -cn --arg q "$query" '{type:"search", query:$q}')"
        [[ -z "$name" ]] && name="$query"
      fi
      [[ -n "$instructions" ]] && target="$(jq -cn --arg i "$instructions" --argjson t "$target" '$t + {instructions:$i}')"

      local p
      p="$(jq -cn --arg n "$name" --argjson t "$target" '{name:$n, target:$t}')"
      if [[ -n "$every" ]]; then
        [[ "$every" =~ ^([0-9]+)(m|h|d|w)$ ]] || die "--every 格式: Nm|Nh|Nd|Nw (如 30m, 6h, 2d, 1w;最小 10 分钟)"
        local freq="${BASH_REMATCH[1]}" unit=""
        case "${BASH_REMATCH[2]}" in m) unit="minutes" ;; h) unit="hours" ;; d) unit="days" ;; w) unit="weeks" ;; esac
        p="$(jq -cn --argjson f "$freq" --arg u "$unit" --argjson p "$p" '$p + {schedule:{type:"interval", frequency:$f, unit:$u}}')"
      fi
      (( exact )) && p="$(jq -cn --argjson p "$p" '$p + {change_detection:{type:"exact"}}')"

      new_body; printf '%s' "$p" >"$REQ_BODY"
      api_request POST /monitors || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    list)
      OP="monitor"; CURL_TIMEOUT=30
      api_request GET /monitors || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    changes)
      OP="monitor"; CURL_TIMEOUT=30
      local id="" limit="20"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --limit) limit="$2"; shift 2 ;;
          -*) die "monitor changes: 未知参数 $1" ;;
          *) [[ -z "$id" ]] && id="$1"; shift ;;
        esac
      done
      add_param limit "$limit"
      if [[ -n "$id" ]]; then
        api_request GET "/monitors/$id/changes" || die "请求失败(HTTP $HTTP_CODE)"
      else
        api_request GET /monitors/changes || die "请求失败(HTTP $HTTP_CODE)"
      fi
      emit 'del(.key_metadata,.request_id) | {changes: [(.changes // .data // [])[0:20][] | {id, monitor_id, title: ((.title // null) | if . then truncstr(120) else . end), summary: ((.summary // null) | if . then truncstr(300) else . end), url, detected_at, importance, matched_url_count, added_url_count, removed_url_count, matched_urls: ((.matched_urls // null) | if . then .[0:10] else . end), evidence: ((.evidence // null) | if . then .[0:10] | map(if type=="string" then truncstr(300) else . end) else . end), diff: ((.diff // null) | if . then truncstr(400) else . end)}], next_cursor: (.next_cursor // null)}'
      ;;
    run)
      OP="monitor"; CURL_TIMEOUT=60
      local id="${1:-}"; [[ -z "$id" ]] && die "用法: ctx.sh monitor run <monitor_id>(手动触发一次,计费)"
      api_request POST "/monitors/$id/run" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    rm)
      OP="monitor"; CURL_TIMEOUT=30
      local id="${1:-}"; [[ -z "$id" ]] && die "用法: ctx.sh monitor rm <monitor_id>"
      api_request DELETE "/monitors/$id" || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    limits)
      OP="monitor"; CURL_TIMEOUT=30
      api_request GET /monitors/limits || die "请求失败(HTTP $HTTP_CODE)"
      emit 'del(.key_metadata,.request_id) | tidydeep($mc)'
      ;;
    *)
      die "用法: ctx.sh monitor page <url> | search <query> | list | changes [id] [--limit N] | run <id> | rm <id> | limits
创建选项: --name --every Nh|Nm|Nd|Nw --instructions S --exact"
      ;;
  esac
}

cmd_raw() {
  OP="raw"; CURL_TIMEOUT=120
  local method="${1:-}" path="${2:-}" body="${3:-}"
  [[ -z "$method" || -z "$path" ]] && die '用法: ctx.sh raw <METHOD> <path> ["{json body}"|@file]
示例: ctx.sh raw POST /people/enrich '\''{"email":"a@b.com"}'\''
      ctx.sh raw POST /utility/prefetch '\''{"type":"domain","domain":"stripe.com"}'\'' (0 credits)
      ctx.sh raw GET /org/usage  (0 credits)'
  method="$(printf '%s' "$method" | tr 'a-z' 'A-Z')"
  [[ "$path" != /* ]] && path="/$path"

  if [[ -n "$body" ]]; then
    if [[ "$body" == @* ]]; then
      REQ_BODY="${body#@}"
      [[ -f "$REQ_BODY" ]] || die "文件不存在: $REQ_BODY"
    else
      jq -e . >/dev/null 2>&1 <<<"$body" || die "body 必须是合法 JSON(或 @file)"
      new_body; printf '%s' "$body" >"$REQ_BODY"
    fi
  fi
  api_request "$method" "$path" || die "请求失败(HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_check() {
  local live=0
  [[ "${1:-}" == "--live" ]] && live=1
  echo "== context-dev 依赖检查 =="
  local c
  for c in bash curl jq; do
    if command -v "$c" >/dev/null; then
      echo "  [OK] $c ($("$c" --version 2>&1 | head -1 | cut -c1-40))"
    else
      echo "  [缺失] $c — 本脚本依赖 bash + curl + jq"
    fi
  done
  echo "== API Key =="
  if [[ -n "${CONTEXT_DEV_API_KEY:-}" ]]; then
    echo "  来源: 环境变量 CONTEXT_DEV_API_KEY"
  elif grep -q '^[[:space:]]*CONTEXT_DEV_API_KEY=' "$HOME/.env" 2>/dev/null; then
    echo "  来源: ~/.env"
  else
    echo "  [未配置] 未找到 Context.dev API Key"
    echo "  配置: export CONTEXT_DEV_API_KEY=\"your_key\" 或 ~/.env 中 CONTEXT_DEV_API_KEY=your_key"
    exit 1
  fi
  local i=0 k
  while IFS= read -r k; do
    i=$((i + 1)); echo "  [$i] $(mask_key "$k")"
  done < <(load_keys)
  if (( i > 1 )); then
    echo "  ⚠ 检测到 $i 个 key:官方禁止多账号轮询(\"multiple accounts trigger our bot detection\")!"
    echo "    多个 key 轮流使用会导致所有关联账号同时被封、积分清零。"
    echo "    本脚本只会使用第 1 个 key;请清理配置,只保留一个。"
  else
    echo "  共 1 个 key"
  fi
  (( live )) || exit 0

  echo "== 连通性验证(0 credits: GET /org/usage) =="
  init_keys
  OP="check"; CURL_TIMEOUT=20
  api_request GET /org/usage || { echo "  [失败] HTTP $HTTP_CODE — 检查网络与 key 有效性"; exit 1; }
  jq -c '.' "$BODY_FILE" | head -c 600; echo
}

# =============================================================================
# 帮助
# =============================================================================
usage() {
  cat <<'EOF'
context-dev — Context.dev API 直调工具 (bash + curl + jq)

用法: bash ctx.sh <子命令> [参数]

子命令:
  check [--live]              检查依赖与 Key 配置(--live 顺带连通性测试, 0 credits)
  search <query>              网页搜索(1 credit/10条; numResults 1-100)
    --num N --freshness last_24_hours|last_week|last_month|last_year
    --include d1,d2 --exclude d1,d2 --country xx --languages en,de
    --desc-chars N(每条description上限,默认280;调大可拿新闻匹配段落)
    --markdown(每条返回正文的+1 credit/条) --highlights(+1 credit/10条)
  scrape <url>                抓取单页(默认 markdown+mainContentOnly, 1 credit)
    --formats md,html,screenshot,images,bytes,parse,highlights,json,product
    --query Q(highlights 用) --schema JSON|@file(json 用, +4 credits)
    --rules JSON|@file(自定义CSS) --parser NAME(预置解析器,与 --rules 互斥)
    (--query/--schema/--rules/--parser 会自动开启对应格式,无需重复写 --formats)
    --parser-limit N --parser-sort newest|oldest|relevant|highest|lowest
      (sort/limit 仅 google-maps-reviews 与 reddit-* 有效;
       reddit 排序在 URL 加 ?sort=top|new|qa,yelp 翻页在 URL 加 ?start=20)
    --prefer-md(优先站点自带 Markdown) --page-numbers(PDF 加 <!-- page N --> 标记)
    --fresh --country XX --wait-for ms|selector
    --timeout MS --partial(return-partial) --no-main-content
    --full-page(整页截图) --shot-selector CSS(元素截图;矩形/viewport/theme 用 raw)
    预置解析器: google-maps(-reviews) google-play(-reviews) app-store(-reviews)
      g2-reviews instagram-{profile,post,feed} tiktok-{profile,video,feed,comments,
      followers,following,user-search} reddit-{post,search,subreddit,user}
      yelp-{search,reviews} emails phone-numbers links
  extract <url>                站点级结构化提取:爬多页按 JSON Schema 出对象(费用见摘要行)
    --schema JSON|@file(必填,真 JSON Schema) --instructions S --fact-check
    --max-pages N(默认5,上限50) --max-depth N --follow-subdomains
  answers <task>              深度研究→结构化JSON+来源(fast=10, ultra=100 credits)
    --mode fast|ultra --json-format JSON|@file
  companies <描述>            自然语言搜公司:档案/总部/规模/融资/社交主页
    (fast 2 credits/页, ultra 10, 无结果免费)
    --mode fast|ultra --countries US,GB --employees-min N --employees-max N --cursor C
  people search <描述>        自然语言找人:职位/雇主/技能/主页
    (fast 10 credits/页, ultra 50, 无结果免费)
    --mode fast|ultra --countries US --exp-min N --exp-max N --cursor C
  people enrich ...           身份线索匹配一个人(20 credits/匹配)
    --email E | --linkedin URL | --first F --last L [--company C --company-domain D]
  batch submit ...            异步批处理:一次抓 ≤10万 URL 或整站爬取(1 credit/页)
    batch submit <url> [url...] | --file urls.txt | --crawl <start-url>
      [--formats ...] [--parser NAME] [--schema JSON] [--main-content]
      [--prefer-md] [--page-numbers]
      (--crawl 加: --max-pages N --regex R --exclude-regex R
        --languages en|same_as_start_url 防多语言副本吃掉配额)
  batch status|results|list|cancel|rm <id>   进度/结果(保留180天,results 支持 --limit/--cursor 翻页)/列表/取消/删除
  monitor page <url>          定时盯一个页面的变化(每次 run 1 credit)
  monitor search <query>      定时搜全网新动态(每次 run 2 credits,变更含 matched_urls/evidence)
    两者通用: --name N --every 30m|6h|2d|1w --instructions S --exact(关闭AI过滤)
  monitor list | changes [id] [--limit N] | run <id> | rm <id> | limits   查询/轮询/手动跑/删/配额
  map <domain>                域名→URL清单(1 credit; --search 时 2)
    --max-links N --regex R --exclude-regex R --search S --subdomains --max-items N(默认50)
  crawl <url>                 同步爬取(1 credit/页, 默认 maxPages=10)
    --max-pages N --max-depth N --regex R --exclude-regex R --main-content --prefer-md
  brand (--domain D|--name N|--email E|--ticker T [--exchange X]|--direct-url U|--transaction S)
                              公司档案(10 credits) --country-gl XX
  brandsearch <query>         品牌模糊搜索(1 credit)  --country US --language english
  styleguide <domain>         设计风格与字体(10 credits)  --scheme light|dark
  news (--query '主题'|--domain D|--name N|--ticker T [--exchange X]|--isin I)
                              新闻:自然语言主题(≤100条)或公司实体(1 credit/10条)
    --limit N --source-country c1,c2 --languages en,zh(文章语言)
  parse <file>                文档解析为 Markdown(1 credit)  --ocr --page-numbers --extension ext
  raw <METHOD> <path> [body]  逃生舱:任意端点, body 为 JSON 字符串或 @file
    例: raw POST /utility/prefetch '{"type":"domain","domain":"stripe.com"}' (0)
        raw GET /org/usage  (0 credits, 查余额)

全局参数(可出现在任意位置):
  --max-chars N   stdout 单字段截断长度(默认 6000;完整响应总在文件里)
  --full          stdout 不截断(慎用, 大响应会占大量 context)
  --api-key KEY   强制使用指定 key(调试)
  -v, --verbose   请求详情输出到 stderr

环境变量:
  CONTEXT_DEV_API_KEY   只支持一个 key(官方禁止多账号轮询,会触发 bot 检测封号!)
  CTX_OUT_DIR           响应文件目录(默认 /tmp/context-dev)
EOF
}

# =============================================================================
# 入口: 先剥离全局参数,再分发子命令
# =============================================================================
main() {
  local cmd="${1:-}"
  case "$cmd" in
    ""|help|-h|--help) usage; exit 0 ;;
    check|search|scrape|extract|answers|companies|people|batch|monitor|map|crawl|brand|brandsearch|styleguide|news|parse|raw) ;;
    *) die "未知子命令: $cmd (bash ctx.sh help 查看用法)" ;;
  esac
  shift

  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-chars) MAX_CHARS="$2"; shift 2 ;;
      --max-chars=*) MAX_CHARS="${1#*=}"; shift ;;
      --full) FULL=1; shift ;;
      --api-key) FORCE_KEY="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=1; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do args+=("$1"); shift; done ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "$cmd" == "check" ]] || init_keys
  [[ -n "$FORCE_KEY" ]] && KEYS=("$FORCE_KEY")

  "cmd_$cmd" "${args[@]}"
}

main "$@"
