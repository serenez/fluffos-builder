#!/bin/bash

# FluffOS 一键安装脚本
# 用于从 GitHub 下载并运行编译脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/serenez/fluffos-builder/main/scripts}"
SCRIPT_NAME="build.sh"
# 使用当前目录，除非用户指定了其他目录
INSTALL_DIR="${INSTALL_DIR:-$(pwd)}"

# 显示欢迎信息
show_banner() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "    FluffOS 自动编译安装工具"
    echo "    作者: 不一 [QQ: 279631638]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 检查依赖
check_dependencies() {
    print_step "检查系统工具..."

    local missing=()

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl 或 wget")
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "缺少必要工具: ${missing[*]}"
        print_info "请先安装这些工具，例如："
        print_info "  Ubuntu/Debian: sudo apt install curl git"
        print_info "  CentOS/RHEL:   sudo yum install curl git"
        exit 1
    fi

    print_info "✓ 系统工具检查通过"
}

# 下载脚本
download_script() {
    print_step "下载编译脚本..."

    # 下载脚本到当前目录
    local script_url="$REPO_URL/$SCRIPT_NAME"
    print_info "下载地址: $script_url"

    if command -v curl &> /dev/null; then
        curl -fsSL "$script_url" -o "$SCRIPT_NAME"
    elif command -v wget &> /dev/null; then
        wget -qO "$SCRIPT_NAME" "$script_url"
    else
        print_error "无法下载脚本"
        exit 1
    fi

    # 添加可执行权限
    chmod +x "$SCRIPT_NAME"

    print_info "✓ 脚本下载完成: $INSTALL_DIR/$SCRIPT_NAME"
}

# 运行脚本
run_script() {
    print_step "运行编译脚本..."
    echo ""

    # 传递所有参数给编译脚本
    if [ "$EUID" -ne 0 ]; then
        print_info "需要 root 权限，将使用 sudo 运行..."
        sudo ./"$SCRIPT_NAME" "$@"
    else
        ./"$SCRIPT_NAME" "$@"
    fi
}

# 显示使用说明
show_usage() {
    cat << 'EOF'
FluffOS 一键安装脚本

用法:
    bash <(curl -fL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) [选项]

选项:
    -h, --help      显示帮助
    -y, --yes       非交互模式
    -d, --debug     Debug 构建
    -r, --release   Release 构建
    --skip-deps     跳过依赖安装

环境变量:
    REPO_URL        仓库地址（默认: GitHub 主仓库）
    INSTALL_DIR     安装目录（默认: 当前目录）

示例:
    # 标准安装
    bash <(curl -fL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y

    # 生产构建
    bash <(curl -fL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y --release

    # 使用 wget
    bash <(wget -O- https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y

EOF
}

# 主函数
main() {
    # 检查帮助参数
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    show_banner

    # 检查依赖
    check_dependencies

    # 下载脚本
    download_script

    # 运行脚本
    run_script "$@"
}

# 执行主函数
main "$@"
