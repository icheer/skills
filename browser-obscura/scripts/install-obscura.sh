#!/usr/bin/env bash
# Obscura 自动安装脚本 - Linux/macOS
set -e

VERSION="${OBSCURA_VERSION:-latest}"
INSTALL_DIR="${OBSCURA_INSTALL_DIR:-$HOME/.local/bin}"
TEMP_DIR=$(mktemp -d)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# 检测操作系统和架构
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        linux)
            OS_NAME="linux"
            ;;
        darwin)
            OS_NAME="macos"
            ;;
        *)
            error "不支持的操作系统: $OS"
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)
            ARCH_NAME="x86_64"
            ;;
        aarch64|arm64)
            ARCH_NAME="aarch64"
            ;;
        *)
            error "不支持的架构: $ARCH"
            ;;
    esac

    PLATFORM="${ARCH_NAME}-${OS_NAME}"
    info "检测到平台: $PLATFORM"
}

# 下载二进制文件
download_obscura() {
    DOWNLOAD_URL="https://github.com/h4ckf0r0day/obscura/releases/${VERSION}/download/obscura-${PLATFORM}.tar.gz"

    info "从以下地址下载: $DOWNLOAD_URL"

    if command -v curl &> /dev/null; then
        curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_DIR/obscura.tar.gz" || error "下载失败"
    elif command -v wget &> /dev/null; then
        wget -q "$DOWNLOAD_URL" -O "$TEMP_DIR/obscura.tar.gz" || error "下载失败"
    else
        error "需要 curl 或 wget 来下载文件"
    fi

    info "下载完成"
}

# 解压和安装
install_obscura() {
    info "解压到 $TEMP_DIR..."
    tar -xzf "$TEMP_DIR/obscura.tar.gz" -C "$TEMP_DIR"

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"

    # 安装主程序和 worker
    info "安装到 $INSTALL_DIR..."
    cp "$TEMP_DIR/obscura" "$INSTALL_DIR/obscura"
    chmod +x "$INSTALL_DIR/obscura"

    # 尝试安装 obscura-worker (如果存在)
    if [ -f "$TEMP_DIR/obscura-worker" ]; then
        cp "$TEMP_DIR/obscura-worker" "$INSTALL_DIR/obscura-worker"
        chmod +x "$INSTALL_DIR/obscura-worker"
        info "已安装 obscura-worker"
    fi

    info "安装完成"
}

# 验证安装
verify_installation() {
    info "验证安装..."

    if ! command -v obscura &> /dev/null; then
        warn "obscura 未在 PATH 中，请手动添加:"
        echo ""
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
        echo "建议添加到 ~/.bashrc 或 ~/.zshrc"
    fi

    # 运行版本检查
    "$INSTALL_DIR/obscura" --version || error "验证失败"

    # 快速功能测试
    info "运行功能测试..."
    "$INSTALL_DIR/obscura" fetch https://example.com --eval "document.title" --quiet || warn "功能测试失败"

    info "✅ Obscura 安装成功!"
    echo ""
    echo "快速开始:"
    echo "  obscura fetch https://example.com --dump text"
    echo "  obscura fetch https://example.com --screenshot page.png"
}

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
}

# 主流程
main() {
    info "开始安装 Obscura..."

    detect_platform
    download_obscura
    install_obscura
    verify_installation
    cleanup
}

trap cleanup EXIT
main
