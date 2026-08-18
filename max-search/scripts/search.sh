#!/usr/bin/env bash
# =============================================================================
# max-search: Parallel Tavily Search via curl
# =============================================================================
# 用 curl 并行请求 Tavily Search API，输出每个查询的原始 JSON 结果，
# 供上层 LLM（agent）直接综合分析。无需 Python / jq。
#
# 用法:
#   bash search.sh [--num-results N] "query1" "query2" "query3"
#   bash search.sh --check          # 检查 API Key 配置状态
#
# API Key 加载优先级:
#   1. 环境变量 TAVILY_API_KEY
#   2. ~/.env         (TAVILY_API_KEY=key1,key2,key3)
#   3. ~/.tavily_api_key
# 支持多 Key（逗号或换行分隔），每次运行随机选一个。
#
# 依赖: bash + curl（Windows 请用 Git Bash 运行）
# =============================================================================

set -uo pipefail

TAVILY_URL="https://api.tavily.com/search"
NUM_RESULTS=8

# 低质量 / 强偏见 / 伪科学 / 讽刺 站点黑名单（JSON 数组，内联到请求体）
EXCLUDE_DOMAINS='["ntdtv.com","ntd.tv","aboluowang.com","epochtimes.com","epochtimes.jp","dafahao.com","minghui.org","secretchina.com","kanzhongguo.com","soundofhope.org","rfa.org","bannedbook.org","boxun.com","peacehall.com","creaders.net","backchina.com","guancha.cn","wenxuecity.com","awaker.cn","tuidang.org","breitbart.com","infowars.com","naturalnews.com","globalresearch.ca","zerohedge.com","thegatewaypundit.com","newsmax.com","oann.com","dailywire.com","theblaze.com","redstate.com","thenationalpulse.com","thefederalist.com","dailykos.com","alternet.org","commondreams.org","thecanary.co","occupydemocrats.com","truthout.org","dailymail.co.uk","thesun.co.uk","nypost.com","express.co.uk","mirror.co.uk","dailystar.co.uk","theonion.com","clickhole.com","babylonbee.com","newspunch.com","beforeitsnews.com","rt.com","sputniknews.com","tass.com","wikileaks.org","mediabiasfactcheck.com","allsides.com"]'

# -----------------------------------------------------------------------------
# 加载全部 API Key（返回逗号/换行分隔的原始串）
# -----------------------------------------------------------------------------
load_raw_keys() {
  # 1. 环境变量
  if [[ -n "${TAVILY_API_KEY:-}" ]]; then
    printf '%s' "$TAVILY_API_KEY"
    return
  fi
  # 2. ~/.env 中第一行 TAVILY_API_KEY=
  if [[ -f "$HOME/.env" ]]; then
    local line
    line="$(grep -m1 '^[[:space:]]*TAVILY_API_KEY=' "$HOME/.env" 2>/dev/null | cut -d= -f2-)"
    if [[ -n "$line" ]]; then
      printf '%s' "$line"
      return
    fi
  fi
  # 3. ~/.tavily_api_key（旧格式）
  if [[ -f "$HOME/.tavily_api_key" ]]; then
    cat "$HOME/.tavily_api_key"
    return
  fi
}

# 随机选一个 Key
pick_key() {
  local raw keys
  raw="$(load_raw_keys)"
  # 按逗号和换行拆分
  IFS=$',\n' read -r -d '' -a keys < <(printf '%s\0' "$raw")
  # 去除空白项
  local cleaned=()
  local k
  for k in "${keys[@]}"; do
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    [[ -n "$k" ]] && cleaned+=("$k")
  done
  local n=${#cleaned[@]}
  (( n == 0 )) && return 1
  printf '%s' "${cleaned[$((RANDOM % n))]}"
}

# Key 打码显示
mask_key() {
  local k="$1"
  if (( ${#k} <= 8 )); then
    printf '****'
  else
    printf '%s****%s' "${k:0:4}" "${k: -4}"
  fi
}

# JSON 字符串转义（转义反斜杠与双引号，覆盖绝大多数搜索词）
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

# -----------------------------------------------------------------------------
# --check: 检查 Key 配置
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--check" ]]; then
  raw="$(load_raw_keys)"
  if [[ -z "$raw" ]]; then
    cat <<'EOF'
[未配置] 未找到 Tavily API Key。

配置方式（任选其一）:
  A. ~/.env 文件（推荐，支持多 Key）:
       TAVILY_API_KEY=key1,key2,key3
  B. 环境变量:
       export TAVILY_API_KEY="key1,key2"
  C. ~/.tavily_api_key 文件（单 Key，向后兼容）

获取 Key: https://app.tavily.com/home
EOF
    exit 1
  fi
  IFS=$',\n' read -r -d '' -a all_keys < <(printf '%s\0' "$raw")
  count=0
  echo "[已配置] 检测到 Tavily API Key:"
  for k in "${all_keys[@]}"; do
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    [[ -z "$k" ]] && continue
    count=$((count + 1))
    echo "  [$count] $(mask_key "$k")"
  done
  echo "共 $count 个 Key（每次搜索随机选用）"
  exit 0
fi

# -----------------------------------------------------------------------------
# 解析参数
# -----------------------------------------------------------------------------
QUERIES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --num-results)
      NUM_RESULTS="$2"
      shift 2
      ;;
    --num-results=*)
      NUM_RESULTS="${1#*=}"
      shift
      ;;
    *)
      QUERIES+=("$1")
      shift
      ;;
  esac
done

if (( ${#QUERIES[@]} == 0 )); then
  echo "[FATAL] 未提供搜索查询。用法: bash search.sh [--num-results N] \"query1\" \"query2\"" >&2
  exit 1
fi

# 取 Key
API_KEY="$(pick_key)" || true
if [[ -z "${API_KEY:-}" ]]; then
  cat >&2 <<'EOF'
[FATAL] 未配置 Tavily API Key。

配置方式（任选其一）:
  A. ~/.env: TAVILY_API_KEY=key1,key2,key3
  B. export TAVILY_API_KEY="YOUR_KEY"
  C. ~/.tavily_api_key（单 Key）

获取 Key: https://app.tavily.com/home
EOF
  exit 1
fi

# -----------------------------------------------------------------------------
# 单次搜索：结果写入临时文件
# -----------------------------------------------------------------------------
run_one() {
  local query="$1" outfile="$2"
  local esc payload payload_file resp code body
  esc="$(json_escape "$query")"
  payload="{\"query\":\"${esc}\",\"max_results\":${NUM_RESULTS},\"include_answer\":\"basic\",\"auto_parameters\":true,\"exclude_domains\":${EXCLUDE_DOMAINS}}"

  # 必须把 payload 写文件后用 --data-binary @file，不能用 -d "$payload"：
  # 在 Windows 上 Git Bash 向原生 curl.exe 传参时会把 argv 从 UTF-8 转成系统
  # ANSI 码页（简中环境为 GBK），中文查询到服务端就成了乱码。文件内容不经过
  # 这层转码，因此是唯一可靠的传递方式。
  payload_file="${outfile}.json"
  printf '%s' "$payload" >"$payload_file"

  # -w 追加换行 + HTTP 状态码，便于分离
  resp="$(curl -sS --max-time 30 --retry 2 --retry-delay 1 \
    -w $'\n%{http_code}' \
    -X POST "$TAVILY_URL" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${API_KEY}" \
    --data-binary "@${payload_file}" 2>/dev/null)" || {
      printf '===== QUERY: %s =====\n[ERROR] curl 请求失败（网络错误）\n' "$query" >"$outfile"
      return
    }

  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  if [[ "$code" == "200" ]]; then
    printf '===== QUERY: %s =====\n%s\n' "$query" "$body" >"$outfile"
  else
    printf '===== QUERY: %s =====\n[ERROR] HTTP %s: %s\n' "$query" "$code" "$body" >"$outfile"
  fi
}

# -----------------------------------------------------------------------------
# 并行执行所有查询
# -----------------------------------------------------------------------------
echo "[INFO] 并行执行 ${#QUERIES[@]} 个查询（每个 num_results=${NUM_RESULTS}）..." >&2

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

idx=0
for q in "${QUERIES[@]}"; do
  run_one "$q" "$TMPDIR_RUN/$idx.out" &
  idx=$((idx + 1))
done
wait

# -----------------------------------------------------------------------------
# 按顺序汇总输出，并统计成功数
# -----------------------------------------------------------------------------
success=0
for ((i = 0; i < idx; i++)); do
  f="$TMPDIR_RUN/$i.out"
  [[ -f "$f" ]] || continue
  cat "$f"
  echo "---"
  grep -q '^\[ERROR\]' "$f" || success=$((success + 1))
done

echo "[INFO] ${success}/${idx} 个查询成功。" >&2
if (( success == 0 )); then
  echo "[FATAL] 所有查询均失败，请检查 API Key 与网络连接。" >&2
  exit 1
fi
