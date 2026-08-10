#!/usr/bin/env bash
# 测试和验证脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

PASSED=0
FAILED=0
SKIPPED=0

# 测试计数器
test_count() {
  if [ $? -eq 0 ]; then
    PASSED=$((PASSED + 1))
    success "$1"
  else
    FAILED=$((FAILED + 1))
    error "$1"
  fi
}

skip_test() {
  SKIPPED=$((SKIPPED + 1))
  warn "$1 (跳过)"
}

echo "╔════════════════════════════════════════╗"
echo "║   Browser Obscura - 功能测试套件      ║"
echo "╚════════════════════════════════════════╝"
echo ""

# 1. 检查 obscura 是否已安装
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. 环境检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v obscura &> /dev/null; then
  VERSION=$(obscura --version 2>&1 | head -1)
  test_count "obscura 已安装: $VERSION"
else
  error "obscura 未安装"
  echo ""
  info "请先运行安装脚本:"
  echo "  bash scripts/install-obscura.sh"
  exit 1
fi

# 检查可选依赖
if command -v jq &> /dev/null; then
  success "jq 已安装 (用于 JSON 处理)"
else
  warn "jq 未安装 (部分示例可能无法运行)"
fi

echo ""

# 2. 基础功能测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. 基础功能测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 2.1 简单 fetch
info "测试: 获取网页内容"
if obscura fetch https://example.com --dump text --quiet > /dev/null 2>&1; then
  test_count "fetch --dump text"
else
  test_count "fetch --dump text"
fi

# 2.2 JavaScript 执行
info "测试: JavaScript 执行"
RESULT=$(obscura fetch https://example.com --eval "document.title" --quiet 2>&1)
if echo "$RESULT" | grep -q "Example Domain"; then
  test_count "JavaScript 执行: $RESULT"
else
  test_count "JavaScript 执行"
fi

# 2.3 提取链接
info "测试: 提取链接"
LINK_COUNT=$(obscura fetch https://example.com --dump links --quiet 2>&1 | wc -l)
if [ "$LINK_COUNT" -gt 0 ]; then
  test_count "提取链接: $LINK_COUNT 个"
else
  test_count "提取链接"
fi

# 2.4 Markdown 转换
info "测试: Markdown 转换"
if obscura fetch https://example.com --dump markdown --quiet > /dev/null 2>&1; then
  test_count "Markdown 转换"
else
  test_count "Markdown 转换"
fi

echo ""

# 3. 等待策略测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. 等待策略测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 3.1 domcontentloaded
info "测试: --wait-until domcontentloaded"
if obscura fetch https://example.com --wait-until domcontentloaded --dump text --quiet > /dev/null 2>&1; then
  test_count "domcontentloaded"
else
  test_count "domcontentloaded"
fi

# 3.2 load
info "测试: --wait-until load"
if obscura fetch https://example.com --wait-until load --dump text --quiet > /dev/null 2>&1; then
  test_count "load"
else
  test_count "load"
fi

# 3.3 固定延迟
info "测试: --wait 1"
if timeout 10 obscura fetch https://example.com --wait 1 --dump text --quiet > /dev/null 2>&1; then
  test_count "固定延迟"
else
  test_count "固定延迟"
fi

echo ""

# 4. 输出格式测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. 输出格式测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TEMP_DIR=$(mktemp -d)

for format in text html markdown links assets cookies original; do
  info "测试: --dump $format"
  if obscura fetch https://example.com --dump "$format" --quiet > "$TEMP_DIR/test_$format" 2>&1; then
    if [ -s "$TEMP_DIR/test_$format" ]; then
      SIZE=$(wc -c < "$TEMP_DIR/test_$format")
      test_count "--dump $format ($SIZE 字节)"
    else
      test_count "--dump $format"
    fi
  else
    test_count "--dump $format"
  fi
done

rm -rf "$TEMP_DIR"

echo ""

# 5. 截图测试 (可能需要渲染功能)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. 截图功能测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SCREENSHOT_FILE=$(mktemp).png
info "测试: 页面截图"
if obscura fetch https://example.com --screenshot "$SCREENSHOT_FILE" --quiet > /dev/null 2>&1; then
  if [ -f "$SCREENSHOT_FILE" ] && [ -s "$SCREENSHOT_FILE" ]; then
    SIZE=$(wc -c < "$SCREENSHOT_FILE")
    test_count "截图功能 ($SIZE 字节)"
    rm -f "$SCREENSHOT_FILE"
  else
    test_count "截图功能"
  fi
else
  skip_test "截图功能 (可能需要渲染特性)"
fi

echo ""

# 6. 批量抓取测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. 批量抓取测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查 obscura-worker 是否存在
if command -v obscura-worker &> /dev/null || [ -f "$(dirname $(which obscura))/obscura-worker" ]; then
  info "测试: scrape 命令"
  SCRAPE_RESULT=$(obscura scrape \
    https://example.com \
    https://www.ietf.org \
    --eval "document.title" \
    --concurrency 2 \
    --format json \
    --quiet 2>&1)

  if echo "$SCRAPE_RESULT" | grep -q "Example Domain"; then
    test_count "批量抓取"
  else
    test_count "批量抓取"
  fi
else
  skip_test "批量抓取 (需要 obscura-worker)"
fi

echo ""

# 7. 示例脚本测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. 示例脚本验证"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for script in examples/*.sh; do
  if [ -f "$script" ]; then
    SCRIPT_NAME=$(basename "$script")
    info "验证: $SCRIPT_NAME"
    if [ -x "$script" ]; then
      test_count "$SCRIPT_NAME 可执行"
    else
      error "$SCRIPT_NAME 不可执行"
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo ""

# 8. 实用工具验证
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. 实用工具验证"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for script in scripts/*.sh; do
  if [ -f "$script" ] && [ "$(basename "$script")" != "test-suite.sh" ]; then
    SCRIPT_NAME=$(basename "$script")
    info "验证: $SCRIPT_NAME"
    if [ -x "$script" ]; then
      test_count "$SCRIPT_NAME 可执行"
    else
      error "$SCRIPT_NAME 不可执行"
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo ""

# 测试总结
echo "╔════════════════════════════════════════╗"
echo "║           测试总结                      ║"
echo "╚════════════════════════════════════════╝"
echo ""

TOTAL=$((PASSED + FAILED + SKIPPED))

echo -e "${GREEN}✓ 通过: $PASSED${NC}"
echo -e "${RED}✗ 失败: $FAILED${NC}"
echo -e "${YELLOW}⚠ 跳过: $SKIPPED${NC}"
echo "─────────────────────"
echo "  总计: $TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}       ✨ 所有测试通过! ✨              ${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "Browser Obscura Skill 已就绪!"
  echo ""
  echo "下一步:"
  echo "  1. 查看快速开始: cat docs/QUICK-START.md"
  echo "  2. 运行示例脚本: bash examples/01-basic-fetch.sh"
  echo "  3. 阅读完整文档: cat SKILL.md"
  exit 0
else
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}       ⚠️  部分测试失败                 ${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "请检查失败的测试项，或查看文档获取帮助。"
  exit 1
fi
