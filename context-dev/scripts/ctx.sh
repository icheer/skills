#!/usr/bin/env bash
# =============================================================================
# context-dev: Context.dev API 的 bash 直调封装(无 MCP / SDK / Python)
# =============================================================================
# 用 curl 直接调用 https://api.context.dev/v1,输出经过"上下文预算"裁剪:
#   stdout  = 摘要行 + 截断后的 JSON 视图(给 agent 看)
#   完整响应 = 始终保存到文件(用 Read/grep/sed 深读,不占 context)
#
# 多 Key 支持: CONTEXT_DEV_API_KEY 或 ~/.env 中的 CONTEXT_DEV_API_KEY,
#   逗号分隔多个 key,每次调用随机轮换;401/403/429/网络失败自动换下一个 key。
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
KEY_INDEX=""          # --key-index N: 按序号钉住池中第 N 个 key(多 key 组织错开并发用)
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

KEYS=()
init_keys() {
  KEYS=()
  local k
  while IFS= read -r k; do KEYS+=("$k"); done < <(load_keys)
  (( ${#KEYS[@]} == 0 )) && die "未配置 Context.dev API Key。
配置方式(任选其一,支持多 Key 逗号分隔,每次调用随机轮换):
  A. export CONTEXT_DEV_API_KEY=\"key1,key2\"
  B. ~/.env: CONTEXT_DEV_API_KEY=key1,key2
获取 Key: https://www.context.dev/auth"
}

shuffle_keys() {  # Fisher-Yates 打乱 KEYS
  local i j tmp
  for ((i = ${#KEYS[@]} - 1; i > 0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp="${KEYS[i]}"; KEYS[i]="${KEYS[j]}"; KEYS[j]="$tmp"
  done
}

# =============================================================================
# 工具函数
# =============================================================================
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

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
    out+="$(jq -rn --arg v "$x" '$v')"
  done
  printf '%s]' "$out"
}

# =============================================================================
# HTTP 请求 + Key 轮换(401/403/429/网络失败 → 换下一个 key)
# =============================================================================
# 调用前需设置: OP, REQ_BODY, REQ_CT, CURL_TIMEOUT, QPAIRS
BODY_FILE=""
HDR_FILE=""
api_request() {  # $1=method $2=path
  local method="$1" path="$2" code i=0 key
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

  (( ${#KEYS[@]} > 1 )) && [[ -z "$FORCE_KEY" ]] && shuffle_keys
  (( VERBOSE )) && log "请求: $method $url"

  for key in "${KEYS[@]}"; do
    i=$((i + 1))
    (( ${#KEYS[@]} > 1 )) && log "尝试 key #$i/${#KEYS[@]}: $(mask_key "$key")"
    local args=(-sS --max-time "$CURL_TIMEOUT" --retry 2 --retry-delay 1
      -X "$method" -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}'
      -H "Authorization: Bearer $key")
    [[ -n "$REQ_BODY" ]] && args+=(-H "Content-Type: $REQ_CT" --data-binary "@$REQ_BODY")
    code="$(curl "${args[@]}" "$url" 2>/dev/null)" || code="000"
    if [[ "$code" == "000" ]]; then
      warn "key $(mask_key "$key") 网络请求失败(curl 超时/断连),换下一个"
      continue
    fi
    if [[ "$code" == "401" || "$code" == "403" || "$code" == "429" ]]; then
      warn "key $(mask_key "$key") 返回 HTTP $code,轮换下一个 key"
      continue
    fi
    USED_KEY="$key"; HTTP_CODE="$code"
    return 0
  done

  USED_KEY=""; HTTP_CODE="$code"
  [[ "$code" == "429" ]] && warn "429 = 组织并发限制或每分钟请求上限(Free 套餐并发=1):改为串行执行、降低并行度,或用 --key-index 把并发请求错开到不同 key 的组织"
  return 1
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
  local fullpage=0 shot_sel=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --formats) fmts="$2"; shift 2 ;;
      --formats=*) fmts="${1#*=}"; shift ;;
      --query) hlq="$2"; shift 2 ;;
      --schema) jschema="$(read_json_arg "$2")"; shift 2 ;;
      --instructions) jinstr="$2"; shift 2 ;;
      --rules) prules="$(read_json_arg "$2")"; shift 2 ;;
      --fresh) fresh=1; shift ;;
      --max-age) maxage="$2"; shift 2 ;;
      --country) country="$2"; shift 2 ;;
      --wait-for) waitfor="$2"; shift 2 ;;
      --timeout) timeout_ms="$2"; shift 2 ;;
      --partial) partial=1; shift ;;
      --no-main-content) main_only=0; shift ;;
      --full-page) fullpage=1; shift ;;
      --shot-selector) shot_sel="$2"; shift 2 ;;
      -*) die "scrape: 未知参数 $1 (viewport/theme/pdf页码/矩形截图等未暴露参数请用 raw)" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  url="${positional[0]:-}"
  [[ -z "$url" ]] && die "用法: ctx.sh scrape <url> [--formats md,html,...] [--query Q] [--schema JSON] ..."
  [[ "$url" != *'://'* ]] && url="https://$url"

  # formats 解析(支持别名)
  local fmt_json="{}" f
  local IFS=','
  for f in $fmts; do
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
    fmt_json="$(jq -cn --arg k "$f" --argjson cur "$fmt_json" '$cur + {($k): true}')"
  done
  unset IFS

  local p
  p="$(jq -cn --arg u "$url" --argjson f "$fmt_json" '{url:$u, formats:$f}')"
  [[ -n "$hlq" ]] && p="$(jq -cn --arg q "$hlq" --argjson p "$p" '$p + {highlightsParams:{query:$q}}')"
  if [[ -n "$jschema" ]]; then
    p="$(jq -cn --argjson s "$jschema" --argjson p "$p" '$p + {jsonParams:{schema:$s}}')"
    [[ -n "$jinstr" ]] && p="$(jq -cn --arg i "$jinstr" --argjson p "$p" '$p + {jsonParams:($p.jsonParams + {instructions:$i})}')"
  fi
  [[ -n "$prules" ]] && p="$(jq -cn --argjson r "$prules" --argjson p "$p" '$p + {parseParams:{rules:$r}}')"
  (( main_only )) && p="$(jq -cn --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {mainContentOnly:true})}')"
  [[ -n "$country" ]] && p="$(jq -cn --arg c "$country" --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {country:$c})}')"
  [[ -n "$waitfor" ]] && p="$(jq -cn --arg w "$waitfor" --argjson p "$p" '$p + {sharedParams:($p.sharedParams + {waitFor:($w|test("^[0-9]+$")|if . then ($w|tonumber) else $w end)})}')"
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

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/scrape || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
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

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/extract || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_search() {
  OP="search"; CURL_TIMEOUT=120
  local num="" freshness="" include="" exclude="" country="" markdown=0 highlights=0 fanout=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --num|--num-results) num="$2"; shift 2 ;;
      --num=*) num="${1#*=}"; shift ;;
      --freshness) freshness="$2"; shift 2 ;;
      --include) include="$2"; shift 2 ;;
      --exclude) exclude="$2"; shift 2 ;;
      --country) country="$2"; shift 2 ;;
      --markdown) markdown=1; shift ;;
      --highlights) highlights=1; shift ;;
      --fanout) fanout=1; shift ;;
      -*) die "search: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh search <query> [--num N] [--markdown] [--highlights] [--freshness last_week] ..."
  local query="${positional[*]}"

  local p
  p="$(jq -cn --arg q "$query" '{query:$q}')"
  if [[ -n "$num" ]]; then
    (( num < 10 )) && { warn "--num 下限为 10,已自动调整为 10"; num=10; }
    (( num > 100 )) && { warn "--num 上限为 100,已自动调整为 100"; num=100; }
    p="$(jq -cn --argjson n "$num" --argjson p "$p" '$p + {numResults:$n}')"
  fi
  [[ -n "$freshness" ]] && p="$(jq -cn --arg f "$freshness" --argjson p "$p" '$p + {freshness:$f}')"
  [[ -n "$include" ]] && p="$(jq -cn --argjson d "$(csv_to_json_array "$include")" --argjson p "$p" '$p + {includeDomains:$d}')"
  [[ -n "$exclude" ]] && p="$(jq -cn --argjson d "$(csv_to_json_array "$exclude")" --argjson p "$p" '$p + {excludeDomains:$d}')"
  [[ -n "$country" ]] && p="$(jq -cn --arg c "$country" --argjson p "$p" '$p + {country:$c}')"
  (( fanout )) && p="$(jq -cn --argjson p "$p" '$p + {queryFanout:true}')"
  (( markdown )) && p="$(jq -cn --argjson p "$p" '$p + {markdownOptions:{enabled:true, useMainContentOnly:true}}')"
  (( highlights )) && p="$(jq -cn --argjson p "$p" '$p + {highlightsOptions:{enabled:true}}')"
  p="$(jq -cn --argjson p "$p" '$p + {descriptionMaxCharacters:280}')"

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/search || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
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

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/answers || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'del(.key_metadata,.cache_metadata) | {partial, answer: (.json_content | walk(truncstr($mc))), sources: [(.sources // [])[0:20][] | if type=="object" then {url, title: ((.title // "") | .[0:120])} else . end]}'
}

cmd_map() {
  OP="map"; CURL_TIMEOUT=60
  local domain="" maxlinks="" regex="" search="" subdomains=0 maxitems=50
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-links) maxlinks="$2"; shift 2 ;;
      --regex) regex="$2"; shift 2 ;;
      --search) search="$2"; shift 2 ;;
      --subdomains) subdomains=1; shift ;;
      --max-items) maxitems="$2"; shift 2 ;;
      -*) die "map: 未知参数 $1" ;;
      *) [[ -z "$domain" ]] && domain="$1"; shift ;;
    esac
  done
  [[ -z "$domain" ]] && die "用法: ctx.sh map <domain> [--max-links N] [--regex R] [--search S] [--subdomains] [--max-items N]"
  domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"

  add_param domain "$domain"
  (( subdomains )) && add_param includeSubdomains "true"
  [[ -n "$maxlinks" ]] && add_param maxLinks "$maxlinks"
  [[ -n "$regex" ]] && add_param urlRegex "$regex"
  [[ -n "$search" ]] && add_param search "$search"

  api_request GET /web/urls || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  [[ "$maxitems" =~ ^[0-9]+$ ]] || die "--max-items 必须是数字"
  emit 'del(.key_metadata,.cache_metadata) | {success, domain, partial, total: (.urls|length), urls: ([.urls[] | if type=="object" then {url, title} else . end] | .[0:$mi]), note: (if (.urls|length) > $mi then "仅显示前 "+($mi|tostring)+" 条,全量见响应文件" else null end)}' --argjson mi "$maxitems"
}

cmd_crawl() {
  OP="crawl"; CURL_TIMEOUT=600
  local url="" maxpages=10 maxdepth="" regex="" main_only=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-pages) maxpages="$2"; shift 2 ;;
      --max-depth) maxdepth="$2"; shift 2 ;;
      --regex) regex="$2"; shift 2 ;;
      --main-content) main_only=1; shift ;;
      -*) die "crawl: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  url="${positional[0]:-}"
  [[ -z "$url" ]] && die "用法: ctx.sh crawl <url> [--max-pages N(默认10,上限500)] [--regex R] [--main-content]
注意: 每页消耗 1 credit;stdout 默认只列页面清单,全文在响应文件"

  local p
  p="$(jq -cn --arg u "$url" --argjson mp "$maxpages" '{url:$u, maxPages:$mp}')"
  [[ -n "$maxdepth" ]] && p="$(jq -cn --argjson d "$maxdepth" --argjson p "$p" '$p + {maxDepth:$d}')"
  [[ -n "$regex" ]] && p="$(jq -cn --arg r "$regex" --argjson p "$p" '$p + {urlRegex:$r}')"
  (( main_only )) && p="$(jq -cn --argjson p "$p" '$p + {useMainContentOnly:true}')"

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /web/crawl || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
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

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /brand/retrieve || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_brandsearch() {
  OP="brandsearch"; CURL_TIMEOUT=30
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*) die "brandsearch: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional[@]} == 0 )) && die "用法: ctx.sh brandsearch <query>"
  add_param query "${positional[*]}"
  api_request GET /brand/search || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
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
  api_request GET /web/styleguide || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_news() {
  OP="news"; CURL_TIMEOUT=60
  local domain="" name="" ticker="" isin="" exchange="" limit="" src_country=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --ticker) ticker="$2"; shift 2 ;;
      --isin) isin="$2"; shift 2 ;;
      --exchange) exchange="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --source-country) src_country="$2"; shift 2 ;;
      -*) die "news: 未知参数 $1" ;;
      *) shift ;;
    esac
  done
  local entity
  if [[ -n "$domain" ]]; then
    domain="${domain#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
    entity="$(jq -cn --arg d "$domain" '{type:"domain", domain:$d}')"
  elif [[ -n "$name" ]]; then
    entity="$(jq -cn --arg n "$name" '{type:"name", name:$n}')"
  elif [[ -n "$ticker" ]]; then
    entity="$(jq -cn --arg t "$ticker" '{type:"ticker", ticker:$t}')"
    [[ -n "$exchange" ]] && entity="$(jq -cn --arg e "$exchange" --argjson p "$entity" '$p + {exchange:$e}')"
  elif [[ -n "$isin" ]]; then
    entity="$(jq -cn --arg i "$isin" '{type:"isin", isin:$i}')"
  else
    die "用法: ctx.sh news --domain x.com | --name 'Company' | --ticker T | --isin I [--limit N] [--source-country c1,c2]"
  fi

  local p
  p="$(jq -cn --argjson e "$entity" '{searchBy:{type:"entity", entity:$e}}')"
  [[ -n "$limit" ]] && p="$(jq -cn --argjson l "$limit" --argjson p "$p" '$p + {limit:$l}')"
  [[ -n "$src_country" ]] && p="$(jq -cn --argjson c "$(csv_to_json_array "$src_country")" --argjson p "$p" '$p + {filterBy:{sourceCountry:$c}}')"

  REQ_BODY="$(mktemp)"; printf '%s' "$p" >"$REQ_BODY"
  api_request POST /news/search || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
}

cmd_parse() {
  OP="parse"; CURL_TIMEOUT=180
  local file="" ocr=0 ext=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ocr) ocr=1; shift ;;
      --extension) ext="$2"; shift 2 ;;
      -*) die "parse: 未知参数 $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  file="${positional[0]:-}"
  [[ -z "$file" || ! -f "$file" ]] && die "用法: ctx.sh parse <file(pdf/docx/...)> [--ocr] [--extension ext]"
  [[ -z "$ext" ]] && ext="${file##*.}"
  ext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"

  add_param extension "${ext:-pdf}"
  (( ocr )) && add_param ocr "true"
  REQ_CT="application/octet-stream"
  REQ_BODY="$file"  # 二进制文件直接作为请求体
  api_request POST /parse || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
  emit 'tidydeep($mc)'
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
      REQ_BODY="$(mktemp)"; printf '%s' "$body" >"$REQ_BODY"
    fi
  fi
  api_request "$method" "$path" || die "所有 key 均失败(最后一个 HTTP $HTTP_CODE)"
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
    echo "  配置: export CONTEXT_DEV_API_KEY=\"key1,key2\" 或 ~/.env 中 CONTEXT_DEV_API_KEY=key1,key2"
    exit 1
  fi
  local i=0 k
  while IFS= read -r k; do
    i=$((i + 1)); echo "  [$i] $(mask_key "$k")"
  done < <(load_keys)
  echo "  共 $i 个 key(逗号分隔,每次调用随机轮换;401/403/429/网络失败自动换下一个)"
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
  search <query>              网页搜索(1 credit/10条)
    --num N --freshness last_24_hours|last_week|last_month|last_year
    --include d1,d2 --exclude d1,d2 --country xx --fanout
    --markdown(+1 credit/10条) --highlights(+1 credit/10条)
  scrape <url>                抓取单页(默认 markdown+mainContentOnly, 1 credit)
    --formats md,html,screenshot,images,bytes,parse,highlights,json,product
    --query Q(highlights 用) --schema JSON|@file(json 用, +4 credits)
    --rules JSON|@file(parse 用) --fresh --country XX --wait-for ms|selector
    --timeout MS --partial(return-partial) --no-main-content
    --full-page(整页截图) --shot-selector CSS(元素截图;矩形/viewport/theme 用 raw)
  extract <url>                站点级结构化提取:爬多页按 JSON Schema 出对象(费用见摘要行)
    --schema JSON|@file(必填,真 JSON Schema) --instructions S --fact-check
    --max-pages N(默认5,上限50) --max-depth N --follow-subdomains
  answers <task>              深度研究→结构化JSON+来源(fast=10, ultra=100 credits)
    --mode fast|ultra --json-format JSON|@file
  map <domain>                域名→URL清单(1 credit; --search 时 2)
    --max-links N --regex R --search S --subdomains --max-items N(默认50)
  crawl <url>                 同步爬取(1 credit/页, 默认 maxPages=10)
    --max-pages N --max-depth N --regex R --main-content
  brand (--domain D|--name N|--email E|--ticker T [--exchange X]|--direct-url U|--transaction S)
                              公司档案(10 credits) --country-gl XX
  brandsearch <query>         品牌模糊搜索(1 credit)
  styleguide <domain>         设计风格与字体(10 credits)  --scheme light|dark
  news (--domain D|--name N|--ticker T [--exchange X]|--isin I)  公司新闻(1 credit/10条)
    --limit N --source-country c1,c2
  parse <file>                文档解析为 Markdown(1 credit)  --ocr --extension ext
  raw <METHOD> <path> [body]  逃生舱:任意端点, body 为 JSON 字符串或 @file
    例: raw POST /people/enrich '{"email":"a@b.com"}'   (20 credits/match, beta)
        raw POST /utility/prefetch '{"type":"domain","domain":"stripe.com"}' (0)

全局参数(可出现在任意位置):
  --max-chars N   stdout 单字段截断长度(默认 6000;完整响应总在文件里)
  --full          stdout 不截断(慎用, 大响应会占大量 context)
  --api-key KEY   强制使用指定 key(调试)
  --key-index N   钉住第 N 个 key(1 起):多 key 时把并发请求错开到不同组织
  -v, --verbose   请求详情输出到 stderr

环境变量:
  CONTEXT_DEV_API_KEY   多个 key 逗号分隔, 随机轮换(或配置在 ~/.env)
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
    check|search|scrape|extract|answers|map|crawl|brand|brandsearch|styleguide|news|parse|raw) ;;
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
      --key-index) KEY_INDEX="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=1; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do args+=("$1"); shift; done ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "$cmd" == "check" ]] || init_keys
  [[ -n "$FORCE_KEY" ]] && KEYS=("$FORCE_KEY")
  if [[ -n "${KEY_INDEX:-}" ]]; then
    [[ "$KEY_INDEX" =~ ^[0-9]+$ ]] || die "--key-index 必须是数字"
    (( KEY_INDEX >= 1 && KEY_INDEX <= ${#KEYS[@]} )) || die "--key-index 超出范围(共 ${#KEYS[@]} 个 key)"
    KEYS=("${KEYS[KEY_INDEX-1]}")
  fi

  "cmd_$cmd" "${args[@]}"
}

main "$@"
