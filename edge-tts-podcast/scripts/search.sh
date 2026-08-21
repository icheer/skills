#!/usr/bin/env bash
# =============================================================================
# edge-tts-podcast: Parallel Tavily Search via curl
# =============================================================================
# 用 curl 并行请求 Tavily Search API，输出每个查询的原始 JSON 结果。
# 与 max-search/scripts/search.sh 保持相同接口约定。
#
# 用法:
#   bash search.sh [--num-results N] [--output FILE] "query1" "query2" "query3"
#   bash search.sh --check          # 检查 API Key 配置状态
#
# 传 --output FILE 时：每个查询的原始 JSON 会完整落盘到 FILE（可追溯证据），
# 而 stdout 只打印按相关度排序的精简摘要（score/标题/URL），避免整段 JSON 刷屏
# 或被工具截断。不传 --output 时保持旧行为，原始 JSON 直接打印到 stdout（调试用）。
# 摘要由内嵌在本脚本中的 Python 代码生成，不引入额外 .py 文件；若本机没有
# 可用 python，会自动回退为打印原始 JSON。
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

EXCLUDE_DOMAINS='["ntdtv.com","ntd.tv","aboluowang.com","epochtimes.com","epochtimes.jp","dafahao.com","minghui.org","secretchina.com","kanzhongguo.com","soundofhope.org","rfa.org","bannedbook.org","boxun.com","peacehall.com","creaders.net","backchina.com","guancha.cn","wenxuecity.com","awaker.cn","tuidang.org","breitbart.com","infowars.com","naturalnews.com","globalresearch.ca","zerohedge.com","thegatewaypundit.com","newsmax.com","oann.com","dailywire.com","theblaze.com","redstate.com","thenationalpulse.com","thefederalist.com","dailykos.com","alternet.org","commondreams.org","thecanary.co","occupydemocrats.com","truthout.org","dailymail.co.uk","thesun.co.uk","nypost.com","express.co.uk","mirror.co.uk","dailystar.co.uk","theonion.com","clickhole.com","babylonbee.com","newspunch.com","beforeitsnews.com","rt.com","sputniknews.com","tass.com","wikileaks.org"]'

# -----------------------------------------------------------------------------
# 加载全部 API Key
# -----------------------------------------------------------------------------
load_raw_keys() {
  if [[ -n "${TAVILY_API_KEY:-}" ]]; then
    printf '%s' "$TAVILY_API_KEY"
    return
  fi
  if [[ -f "$HOME/.env" ]]; then
    local line
    line="$(grep -m1 '^[[:space:]]*TAVILY_API_KEY=' "$HOME/.env" 2>/dev/null | cut -d= -f2-)"
    if [[ -n "$line" ]]; then
      printf '%s' "$line"
      return
    fi
  fi
  if [[ -f "$HOME/.tavily_api_key" ]]; then
    cat "$HOME/.tavily_api_key"
    return
  fi
}

pick_key() {
  local raw keys
  raw="$(load_raw_keys)"
  IFS=$',\n' read -r -d '' -a keys < <(printf '%s\0' "$raw")
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

mask_key() {
  local k="$1"
  if (( ${#k} <= 8 )); then
    printf '****'
  else
    printf '%s****%s' "${k:0:4}" "${k: -4}"
  fi
}

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
# --check
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
OUTPUT_PATH=""
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
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --output=*)
      OUTPUT_PATH="${1#*=}"
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
# 单次搜索
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
# 并行执行
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

RAW_COMBINED="$TMPDIR_RUN/combined.txt"
: >"$RAW_COMBINED"

success=0
for ((i = 0; i < idx; i++)); do
  f="$TMPDIR_RUN/$i.out"
  [[ -f "$f" ]] || continue
  cat "$f" >>"$RAW_COMBINED"
  echo "---" >>"$RAW_COMBINED"
  grep -q '^\[ERROR\]' "$f" || success=$((success + 1))
done

if [[ -z "$OUTPUT_PATH" ]]; then
  # 未指定落盘路径时保留旧行为：直接输出原始 JSON，供调试使用。
  cat "$RAW_COMBINED"
else
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  cp "$RAW_COMBINED" "$OUTPUT_PATH"
  echo "[INFO] 原始结果已落盘: $OUTPUT_PATH" >&2

  # command -v 只确认命令存在，部分 Windows 环境的 python3 是商店占位符
  # （能被找到但执行会静默失败），所以用 --version 实测可用性。
  PY_BIN=""
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version >/dev/null 2>&1; then
      PY_BIN="$candidate"
      break
    fi
  done

  if [[ -z "$PY_BIN" ]]; then
    echo "[提示] 未找到可用的 python 解释器，无法生成摘要，改为打印原始 JSON。" >&2
    cat "$RAW_COMBINED"
  else
    "$PY_BIN" - "$OUTPUT_PATH" <<'PYEOF' || cat "$RAW_COMBINED"
import json
import re
import sys

# Windows 重定向输出时默认会用系统代码页（GBK）而非 UTF-8，需显式固定。
try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
    text = f.read()

blocks = re.split(r'^===== QUERY: (.*) =====\n', text, flags=re.MULTILINE)
it = iter(blocks[1:])
for query, content in zip(it, it):
    content = content.rsplit('\n---', 1)[0].strip()
    print('===== QUERY: ' + query + ' =====')
    if content.startswith('[ERROR]'):
        print('  ' + content)
        continue
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        print('  [警告] 无法解析该查询返回的 JSON，请查看落盘文件核对原始内容。')
        continue
    answer = (data.get('answer') or '').strip()
    if answer:
        truncated = answer[:200] + ('…' if len(answer) > 200 else '')
        print('  概要: ' + truncated)
    results = sorted(data.get('results') or [], key=lambda r: r.get('score', 0), reverse=True)
    if not results:
        print('  (无结果)')
    for i, r in enumerate(results, 1):
        title = (r.get('title') or '').strip()
        url = (r.get('url') or '').strip()
        snippet = (r.get('content') or '').strip()
        if len(snippet) > 100:
            snippet = snippet[:100] + '…'
        print('  {0}. score={1:.3f} | {2}'.format(i, r.get('score', 0), title))
        print('     ' + url)
        if snippet:
            print('     ' + snippet)
    print()
PYEOF
  fi
fi

echo "[INFO] ${success}/${idx} 个查询成功。" >&2
if (( success == 0 )); then
  echo "[FATAL] 所有查询均失败，请检查 API Key 与网络连接。" >&2
  exit 1
fi
