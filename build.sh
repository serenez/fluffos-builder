#!/bin/bash

# FluffOS 通用自动编译安装脚本
# 支持: Ubuntu, Debian, CentOS, RHEL, Fedora, OpenEuler, HCE OS, Arch Linux, openSUSE 等
# 功能: 自动从 Git 拉取最新代码，编译并安装到全局目录

set -e  # 遇到错误立即退出

# ==== 配置区域 ====
# Git 仓库地址
GIT_REPO="${GIT_REPO:-https://github.com/fluffos/fluffos.git}"
# Git 分支
GIT_BRANCH="${GIT_BRANCH:-master}"
# 安装目录
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# 本地项目目录（自动检测）
# 默认使用脚本所在目录下的 fluffos 子目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEFAULT_PROJECT_DIR="$SCRIPT_DIR/fluffos"
# 允许通过环境变量覆盖
PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}"

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印信息函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 询问用户 yes/no 问题
ask_yes_no() {
    local question="$1"
    local default="${2:-y}"  # 默认为 y

    # 如果是非交互模式，使用默认值
    if [ -n "$NON_INTERACTIVE" ]; then
        if [ "$default" = "y" ]; then
            return 0
        else
            return 1
        fi
    fi

    local prompt
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        read -p "$question $prompt: " answer
        answer=${answer:-$default}  # 如果用户直接回车，使用默认值
        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "请输入 y 或 n"
                ;;
        esac
    done
}

# 询问用户选择
ask_choice() {
    local question="$1"
    shift
    local options=("$@")

    # 如果是非交互模式，返回第一个选项
    if [ -n "$NON_INTERACTIVE" ]; then
        echo "1"
        return
    fi

    echo "$question"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done

    while true; do
        read -p "请选择 [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$choice"
            return
        else
            echo "无效选择，请输入 1-${#options[@]} 之间的数字"
        fi
    done
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测 Linux 发行版
detect_system() {
    if [ ! -f /etc/os-release ]; then
        print_error "无法检测操作系统版本"
        exit 1
    fi

    . /etc/os-release

    OS_NAME="$NAME"
    OS_VERSION="${VERSION:-Unknown}"
    OS_ID="$ID"
    OS_ID_LIKE="${ID_LIKE:-$ID}"

    print_info "检测到系统: $OS_NAME $OS_VERSION"

    # 检测发行版类型
    if [[ "$OS_ID" =~ "ubuntu" ]] || [[ "$OS_ID_LIKE" =~ "ubuntu" ]]; then
        DISTRO_TYPE="ubuntu"
        PKG_MGR="apt"
        print_info "发行版类型: Ubuntu/Ubuntu-based"
    elif [[ "$OS_ID" =~ "debian" ]] || [[ "$OS_ID_LIKE" =~ "debian" ]]; then
        DISTRO_TYPE="debian"
        PKG_MGR="apt"
        print_info "发行版类型: Debian/Debian-based"
    elif [[ "$OS_ID" =~ "centos" ]] || [[ "$OS_ID_LIKE" =~ "centos" ]]; then
        DISTRO_TYPE="centos"
        detect_rpm_package_manager
        print_info "发行版类型: CentOS"
    elif [[ "$OS_ID" =~ "rhel" ]] || [[ "$OS_ID_LIKE" =~ "rhel" ]]; then
        DISTRO_TYPE="rhel"
        detect_rpm_package_manager
        print_info "发行版类型: RHEL"
    elif [[ "$OS_ID" =~ "fedora" ]] || [[ "$OS_ID_LIKE" =~ "fedora" ]]; then
        DISTRO_TYPE="fedora"
        PKG_MGR="dnf"
        print_info "发行版类型: Fedora"
    elif [[ "$OS_NAME" =~ "openEuler" ]]; then
        DISTRO_TYPE="openeuler"
        detect_rpm_package_manager
        print_info "发行版类型: OpenEuler"
    elif [[ "$OS_NAME" =~ "HCE" ]] || [[ "$OS_NAME" =~ "Huawei Cloud EulerOS" ]]; then
        DISTRO_TYPE="hce"
        detect_rpm_package_manager
        print_info "发行版类型: 华为云 EulerOS (HCE OS)"
    elif [[ "$OS_NAME" =~ "EulerOS" ]]; then
        DISTRO_TYPE="euleros"
        detect_rpm_package_manager
        print_info "发行版类型: EulerOS"
    elif [[ "$OS_ID" =~ "arch" ]] || [[ "$OS_ID_LIKE" =~ "arch" ]]; then
        DISTRO_TYPE="arch"
        PKG_MGR="pacman"
        print_info "发行版类型: Arch Linux"
    elif [[ "$OS_ID" =~ "opensuse" ]] || [[ "$OS_ID_LIKE" =~ "suse" ]]; then
        DISTRO_TYPE="opensuse"
        PKG_MGR="zypper"
        print_info "发行版类型: openSUSE"
    else
        DISTRO_TYPE="unknown"
        print_warning "未识别的发行版: $OS_NAME"
        print_warning "尝试自动检测包管理器..."
        auto_detect_package_manager
    fi

    print_info "包管理器: $PKG_MGR"
}

# 检测 RPM 系统的包管理器
detect_rpm_package_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MGR="yum"
    else
        print_error "未找到包管理器 (yum/dnf)"
        exit 1
    fi
}

# 自动检测包管理器
auto_detect_package_manager() {
    if command -v apt &> /dev/null || command -v apt-get &> /dev/null; then
        PKG_MGR="apt"
        DISTRO_TYPE="debian"
    elif command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
        DISTRO_TYPE="fedora"
    elif command -v yum &> /dev/null; then
        PKG_MGR="yum"
        DISTRO_TYPE="centos"
    elif command -v pacman &> /dev/null; then
        PKG_MGR="pacman"
        DISTRO_TYPE="arch"
    elif command -v zypper &> /dev/null; then
        PKG_MGR="zypper"
        DISTRO_TYPE="opensuse"
    else
        print_error "无法检测包管理器"
        print_error "请手动安装依赖后使用 --skip-deps 选项运行"
        exit 1
    fi
    print_info "自动检测到包管理器: $PKG_MGR"
}

# 更新包列表
update_package_list() {
    print_step "更新软件包列表..."
    case "$PKG_MGR" in
        apt)
            apt update -y || print_warning "软件包列表更新失败"
            ;;
        dnf|yum)
            $PKG_MGR update -y || print_warning "软件包列表更新失败"
            ;;
        pacman)
            pacman -Sy || print_warning "软件包列表更新失败"
            ;;
        zypper)
            zypper refresh || print_warning "软件包列表更新失败"
            ;;
    esac
}

# 安装单个包
install_package() {
    local package="$1"
    local result=0

    case "$PKG_MGR" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt install -y "$package" 2>&1 | tee -a /tmp/fluffos-install.log
            result=${PIPESTATUS[0]}
            ;;
        dnf|yum)
            $PKG_MGR install -y "$package" 2>&1 | tee -a /tmp/fluffos-install.log
            result=${PIPESTATUS[0]}
            ;;
        pacman)
            pacman -S --noconfirm "$package" 2>&1 | tee -a /tmp/fluffos-install.log
            result=${PIPESTATUS[0]}
            ;;
        zypper)
            zypper install -y "$package" 2>&1 | tee -a /tmp/fluffos-install.log
            result=${PIPESTATUS[0]}
            ;;
    esac

    return $result
}

# 获取包名（不同发行版的包名映射）
get_package_name() {
    local generic_name="$1"

    case "$PKG_MGR" in
        apt)
            # Debian/Ubuntu 包名
            case "$generic_name" in
                gcc) echo "build-essential" ;;
                gcc-c++) echo "g++" ;;
                cmake) echo "cmake" ;;
                git) echo "git" ;;
                bison) echo "bison" ;;
                flex) echo "flex" ;;
                pkgconfig) echo "pkg-config" ;;
                autoconf) echo "autoconf" ;;
                automake) echo "automake" ;;
                libtool) echo "libtool" ;;
                patch) echo "patch" ;;
                zlib-devel) echo "zlib1g-dev" ;;
                pcre-devel) echo "libpcre3-dev" ;;
                openssl-devel) echo "libssl-dev" ;;
                bzip2-devel) echo "libbz2-dev" ;;
                elfutils-devel) echo "libelf-dev libdw-dev" ;;
                xz-devel) echo "liblzma-dev" ;;
                zstd-devel) echo "libzstd-dev" ;;
                sqlite-devel) echo "libsqlite3-dev" ;;
                mariadb-devel) echo "libmariadb-dev" ;;
                postgresql-devel) echo "libpq-dev" ;;
                libicu-devel) echo "libicu-dev" ;;
                jemalloc-devel) echo "libjemalloc-dev" ;;
                gtest-devel) echo "libgtest-dev" ;;
                expect) echo "expect" ;;
                telnet) echo "telnet" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        dnf|yum)
            # CentOS/RHEL/Fedora 包名
            case "$generic_name" in
                gcc) echo "gcc" ;;
                gcc-c++) echo "gcc-c++" ;;
                pkgconfig) echo "pkgconfig" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        pacman)
            # Arch Linux 包名
            case "$generic_name" in
                gcc) echo "base-devel" ;;
                gcc-c++) echo "" ;;  # 包含在 base-devel 中
                zlib-devel) echo "zlib" ;;
                pcre-devel) echo "pcre" ;;
                openssl-devel) echo "openssl" ;;
                bzip2-devel) echo "bzip2" ;;
                elfutils-devel) echo "elfutils" ;;
                xz-devel) echo "xz" ;;
                zstd-devel) echo "zstd" ;;
                sqlite-devel) echo "sqlite" ;;
                mariadb-devel) echo "mariadb-libs" ;;
                postgresql-devel) echo "postgresql-libs" ;;
                libicu-devel) echo "icu" ;;
                jemalloc-devel) echo "jemalloc" ;;
                gtest-devel) echo "gtest" ;;
                pkgconfig) echo "pkgconf" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        zypper)
            # openSUSE 包名
            case "$generic_name" in
                gcc) echo "gcc gcc-c++" ;;
                gcc-c++) echo "" ;;  # 已包含在上面
                zlib-devel) echo "zlib-devel" ;;
                pcre-devel) echo "pcre-devel" ;;
                openssl-devel) echo "libopenssl-devel" ;;
                bzip2-devel) echo "libbz2-devel" ;;
                elfutils-devel) echo "libelf-devel libdw-devel" ;;
                xz-devel) echo "xz-devel" ;;
                zstd-devel) echo "libzstd-devel" ;;
                sqlite-devel) echo "sqlite3-devel" ;;
                mariadb-devel) echo "libmariadb-devel" ;;
                postgresql-devel) echo "postgresql-devel" ;;
                libicu-devel) echo "libicu-devel" ;;
                jemalloc-devel) echo "jemalloc-devel" ;;
                gtest-devel) echo "gtest" ;;
                pkgconfig) echo "pkg-config" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
    esac
}

# 安装依赖
install_dependencies() {
    # 清空日志
    > /tmp/fluffos-install.log
    print_info "安装日志: /tmp/fluffos-install.log"

    update_package_list

    print_step "正在安装编译依赖..."

    # 定义通用包名
    REQUIRED_PACKAGES=(
        gcc
        gcc-c++
        cmake
        git
        bison
        flex
        pkgconfig
        autoconf
        automake
        libtool
        patch
        zlib-devel
        pcre-devel
        openssl-devel
        bzip2-devel
        elfutils-devel
        xz-devel
        zstd-devel
    )

    OPTIONAL_PACKAGES=(
        sqlite-devel
        mariadb-devel
        postgresql-devel
        libicu-devel
        jemalloc-devel
    )

    TEST_PACKAGES=(
        gtest-devel
        expect
        telnet
    )

    # 安装必需包
    print_info "安装必需的编译工具和库..."
    local failed_packages=()

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        real_pkg=$(get_package_name "$pkg")
        if [ -z "$real_pkg" ]; then
            print_info "跳过 $pkg (该系统不需要)"
            continue  # 跳过空包名
        fi

        print_info "正在安装 $pkg → $real_pkg ..."
        # 支持多个包名（用空格分隔）
        local pkg_failed=0
        for p in $real_pkg; do
            if ! install_package "$p"; then
                print_warning "包 $p 安装失败"
                failed_packages+=("$p")
                pkg_failed=1
            else
                print_info "✓ $p 安装成功"
            fi
        done

        # 如果是关键包（cmake, gcc, git）失败则立即退出
        if [ $pkg_failed -eq 1 ]; then
            case "$pkg" in
                cmake|gcc|git)
                    print_error "关键包 $pkg 安装失败，无法继续"
                    print_error "请查看日志: /tmp/fluffos-install.log"
                    exit 1
                    ;;
            esac
        fi
    done

    # 报告失败的包
    if [ ${#failed_packages[@]} -gt 0 ]; then
        print_warning "以下包安装失败: ${failed_packages[*]}"
        print_warning "这可能影响部分功能，但不影响基本编译"
    fi

    # 安装可选包
    print_info "安装可选的开发库..."
    for pkg in "${OPTIONAL_PACKAGES[@]}"; do
        real_pkg=$(get_package_name "$pkg")
        if [ -z "$real_pkg" ]; then
            continue
        fi

        print_info "安装 $pkg ($real_pkg) ..."
        for p in $real_pkg; do
            install_package "$p" || print_warning "$p 安装失败，继续..."
        done
    done

    # 安装测试工具
    print_info "安装测试工具（可选）..."
    for pkg in "${TEST_PACKAGES[@]}"; do
        real_pkg=$(get_package_name "$pkg")
        if [ -z "$real_pkg" ]; then
            continue
        fi

        for p in $real_pkg; do
            install_package "$p" 2>/dev/null || print_info "$p 不可用，跳过"
        done
    done

    print_info "依赖安装完成"
}

# 检查 Git 是否可用
check_git() {
    if ! command -v git &> /dev/null; then
        print_error "Git 未安装，无法拉取代码"
        exit 1
    fi
    print_info "Git 版本: $(git --version | head -n1)"
}

# 从 Git 获取最新代码
update_source_code() {
    print_step "准备源代码..."

    echo ""
    print_info "不一[279631638]："
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "脚本位置: $SCRIPT_DIR"
    print_info "项目目录: $PROJECT_DIR"
    print_info "Git 仓库: $GIT_REPO"
    print_info "Git 分支: $GIT_BRANCH"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 检查项目目录是否存在
    if [ -d "$PROJECT_DIR" ]; then
        # 检查是否是 Git 仓库
        if [ -d "$PROJECT_DIR/.git" ]; then
            print_info "检测到现有的 FluffOS 项目: $PROJECT_DIR"

            # 显示当前项目信息
            cd "$PROJECT_DIR"
            local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            local current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "unknown")

            echo ""
            print_info "当前项目信息:"
            print_info "  远程仓库: $remote_url"
            print_info "  当前分支: $current_branch"
            print_info "  最新提交: $current_commit"
            echo ""

            # 询问用户是否使用现有项目
            if ask_yes_no "是否使用现有项目并更新到最新版本？" "y"; then
                # 保存当前工作区修改（如果有）
                if ! git diff-index --quiet HEAD -- 2>/dev/null; then
                    print_warning "检测到未提交的修改"
                    if ask_yes_no "是否保存当前修改到 stash？" "y"; then
                        git stash save "Auto-stash before update $(date +'%Y-%m-%d %H:%M:%S')"
                        print_info "修改已保存到 stash"
                    fi
                fi

                # 拉取最新代码
                print_info "从远程仓库拉取分支: $GIT_BRANCH"
                git fetch origin || {
                    print_error "拉取代码失败"
                    exit 1
                }

                git checkout "$GIT_BRANCH" || {
                    print_error "切换分支失败"
                    exit 1
                }

                git pull origin "$GIT_BRANCH" || {
                    print_error "更新代码失败"
                    exit 1
                }

                # 显示最新提交信息
                print_info "最新提交:"
                git log -1 --oneline --decorate
            else
                print_info "使用现有代码，跳过更新"
            fi

        else
            print_warning "目录 $PROJECT_DIR 存在但不是 Git 仓库"
            if ask_yes_no "是否删除现有目录并重新克隆？" "n"; then
                rm -rf "$PROJECT_DIR"
                clone_repository
            else
                print_error "无法继续，请手动处理该目录"
                exit 1
            fi
        fi
    else
        # 目录不存在，提示用户将要克隆
        echo ""
        print_info "将要克隆 FluffOS 项目到: $PROJECT_DIR"
        print_info "仓库地址: $GIT_REPO"
        print_info "分支: $GIT_BRANCH"
        echo ""

        if ask_yes_no "是否继续克隆项目？" "y"; then
            clone_repository
        else
            print_error "用户取消操作"
            exit 1
        fi
    fi
}

# 克隆 Git 仓库
clone_repository() {
    print_info "克隆 FluffOS 仓库..."
    print_info "仓库地址: $GIT_REPO"
    print_info "目标目录: $PROJECT_DIR"

    # 创建父目录
    mkdir -p "$(dirname "$PROJECT_DIR")"

    # 克隆仓库
    git clone --branch "$GIT_BRANCH" "$GIT_REPO" "$PROJECT_DIR" || {
        print_error "克隆仓库失败"
        exit 1
    }

    cd "$PROJECT_DIR"
    print_info "仓库克隆成功"
    print_info "当前版本:"
    git log -1 --oneline --decorate
}

# 检查 CMake 版本
check_cmake_version() {
    print_step "检查 CMake 版本..."

    if ! command -v cmake &> /dev/null; then
        print_error "CMake 未安装！"
        print_error ""
        print_error "请手动安装 CMake:"
        case "$PKG_MGR" in
            apt)
                print_error "  sudo apt update"
                print_error "  sudo apt install -y cmake"
                ;;
            dnf)
                print_error "  sudo dnf install -y cmake"
                ;;
            yum)
                print_error "  sudo yum install -y cmake"
                ;;
            pacman)
                print_error "  sudo pacman -S cmake"
                ;;
            zypper)
                print_error "  sudo zypper install cmake"
                ;;
            *)
                print_error "  使用您的包管理器安装 cmake"
                ;;
        esac
        print_error ""
        print_error "或从源代码安装最新版本:"
        print_error "  wget https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1.tar.gz"
        print_error "  tar -zxvf cmake-3.28.1.tar.gz"
        print_error "  cd cmake-3.28.1"
        print_error "  ./bootstrap && make -j\$(nproc) && sudo make install"
        exit 1
    fi

    CMAKE_VERSION=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
    CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)

    print_info "CMake 版本: $CMAKE_VERSION"

    # 检查版本是否满足 3.22+ 要求
    if [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 22 ]); then
        print_error "CMake 版本过低，需要 3.22 或更高版本"
        print_info "当前版本: $CMAKE_VERSION"
        print_info ""
        print_info "请升级 CMake:"
        case "$PKG_MGR" in
            apt)
                print_info "  sudo apt install -y software-properties-common"
                print_info "  sudo add-apt-repository ppa:ubuntu-toolchain-r/test"
                print_info "  sudo apt update && sudo apt install cmake"
                ;;
            dnf|yum)
                print_info "  # 或从源代码编译最新版本"
                ;;
        esac
        print_info ""
        print_info "或从源代码编译:"
        print_info "  wget https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1.tar.gz"
        print_info "  tar -zxvf cmake-3.28.1.tar.gz"
        print_info "  cd cmake-3.28.1"
        print_info "  ./bootstrap && make -j\$(nproc) && sudo make install"
        exit 1
    fi

    print_info "CMake 版本检查通过"
}

# 清理旧的构建
clean_build() {
    if [ -d "$PROJECT_DIR/build" ]; then
        print_step "清理旧的构建目录..."
        rm -rf "$PROJECT_DIR/build"
        print_info "清理完成"
    fi
}

# 配置构建选项
configure_build() {
    print_step "配置构建..."

    cd "$PROJECT_DIR"
    mkdir -p build
    cd build

    # 根据需求选择构建类型
    BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}"

    # CMake 配置选项 - 使用与旧脚本相同的配置以保证速度
    CMAKE_OPTS=(
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DPACKAGE_DB_SQLITE=2
        -DPACKAGE_DB_DEFAULT_DB=2
    )

    # 自定义选项（从环境变量读取）
    if [ -n "$CMAKE_EXTRA_OPTS" ]; then
        read -ra EXTRA_OPTS <<< "$CMAKE_EXTRA_OPTS"
        CMAKE_OPTS+=("${EXTRA_OPTS[@]}")
        print_info "添加自定义选项: $CMAKE_EXTRA_OPTS"
    fi

    print_info "构建类型: $BUILD_TYPE"
    print_info "CMake 选项: ${CMAKE_OPTS[*]}"

    # 运行 CMake
    if ! cmake "$PROJECT_DIR" "${CMAKE_OPTS[@]}"; then
        print_error "CMake 配置失败"
        exit 1
    fi

    print_info "配置完成"
}

# 编译
compile() {
    print_step "开始编译..."

    cd "$PROJECT_DIR/build"

    # 获取 CPU 核心数
    NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
    print_info "使用 $NPROC 个并行任务进行编译"

    # 编译
    if ! make -j"$NPROC"; then
        print_error "编译失败"
        exit 1
    fi

    print_info "编译完成！"

    # 安装到 build 目录
    print_info "执行 make install..."
    if ! make install; then
        print_error "安装失败"
        exit 1
    fi

    # 验证驱动程序是否存在
    if [ -f "bin/driver" ]; then
        print_info "✓ 驱动程序安装成功: $PROJECT_DIR/build/bin/driver"
    else
        print_error "驱动程序未找到: $PROJECT_DIR/build/bin/driver"
        print_error "尝试查找 driver 文件..."
        find "$PROJECT_DIR/build" -name "driver" -type f 2>/dev/null || true
        print_error ""
        print_error "请检查编译日志"
        exit 1
    fi
}

# 安装到全局目录
install_driver() {
    print_step "安装 FluffOS 驱动程序..."

    cd "$PROJECT_DIR/build"

    # 检查驱动程序是否存在
    if [ ! -f "bin/driver" ]; then
        print_error "驱动程序未找到: $PROJECT_DIR/build/bin/driver"
        exit 1
    fi

    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "编译完成！驱动程序位置:"
    print_info "  $PROJECT_DIR/build/bin/driver"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 询问用户是否复制到 /usr/local/bin
    if ask_yes_no "是否将驱动程序复制到 /usr/local/bin ？" "y"; then
        print_info "复制驱动程序到 /usr/local/bin/driver"
        cp -f bin/driver /usr/local/bin/driver
        chmod +x /usr/local/bin/driver
        print_info "✓ 驱动程序已复制到 /usr/local/bin/driver"
        DRIVER_PATH="/usr/local/bin/driver"
    else
        DRIVER_PATH="$PROJECT_DIR/build/bin/driver"
        print_info "驱动程序位于: $DRIVER_PATH"
    fi
}

# 运行测试
run_tests() {
    if [ -z "$RUN_TESTS" ]; then
        return
    fi

    print_step "运行单元测试..."
    cd "$PROJECT_DIR/build"
    if make test; then
        print_info "单元测试通过"
    else
        print_warning "部分单元测试失败"
    fi

    print_step "运行 LPC 测试套件..."
    DRIVER_PATH="$INSTALL_DIR/bin/driver"
    [ ! -f "$DRIVER_PATH" ] && DRIVER_PATH="$INSTALL_DIR/driver"

    if [ ! -f "$DRIVER_PATH" ]; then
        print_error "驱动程序未找到，跳过 LPC 测试"
        return
    fi

    if [ -d "$PROJECT_DIR/testsuite" ]; then
        cd "$PROJECT_DIR/testsuite"
        if "$DRIVER_PATH" etc/config.test -ftest; then
            print_info "LPC 测试通过"
        else
            print_warning "部分 LPC 测试失败"
        fi
    fi
}

# 显示构建信息
show_build_info() {
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "         FluffOS 编译完成！         "
    print_info "如有问题请联系作者：不一 [QQ 279631638]！ "
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info ""
    print_info "系统信息:"
    print_info "  操作系统: $OS_NAME $OS_VERSION"
    print_info "  发行版类型: $DISTRO_TYPE"
    print_info "  构建类型: $BUILD_TYPE"
    print_info ""

    if [ -z "$SKIP_INSTALL" ]; then
        print_info "安装位置:"
        print_info "  驱动程序: $DRIVER_PATH"

        SHARE_DIR="$INSTALL_DIR/../share/fluffos"
        if [ -f "$SHARE_DIR/Config.example" ]; then
            print_info "  配置示例: $SHARE_DIR/Config.example"
        fi
        if [ -d "$SHARE_DIR/docs" ]; then
            print_info "  文档目录: $SHARE_DIR/docs/"
        fi
        if [ -f "$SHARE_DIR/VERSION" ]; then
            print_info "  版本信息: $SHARE_DIR/VERSION"
        fi
        print_info ""

        if [ -f "$SHARE_DIR/VERSION" ]; then
            print_info "版本详情:"
            cat "$SHARE_DIR/VERSION" | sed 's/^/  /'
            print_info ""
        fi

        print_info "使用方法:"
        print_info "  直接运行: $DRIVER_PATH <config_file>"

        if echo "$PATH" | grep -q "$INSTALL_DIR/bin" || echo "$PATH" | grep -q "$INSTALL_DIR"; then
            print_info "  或直接运行: driver <config_file>"
        else
            print_info ""
            print_info "添加到 PATH (可选):"
            if [ -d "$INSTALL_DIR/bin" ]; then
                print_info "  echo 'export PATH=\"$INSTALL_DIR/bin:\$PATH\"' >> ~/.bashrc"
            else
                print_info "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc"
            fi
            print_info "  source ~/.bashrc"
        fi
    else
        print_info "驱动程序位置:"
        print_info "  $DRIVER_PATH"
        print_info ""
        print_info "使用方法:"
        print_info "  $DRIVER_PATH <config_file>"
        print_info ""
        print_info "提示: 如需全局安装，请重新运行脚本并选择安装"
    fi

    print_info ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 检查依赖是否安装
check_dependencies() {
    print_step "检查依赖安装情况..."

    local missing=()
    local installed=()

    # 检查关键工具
    local tools=("gcc" "g++" "cmake" "git" "make" "bison")

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=$("$tool" --version 2>/dev/null | head -n1 || echo "unknown")
            installed+=("✓ $tool: $version")
        else
            missing+=("✗ $tool")
        fi
    done

    # 显示结果
    if [ ${#installed[@]} -gt 0 ]; then
        print_info "已安装的工具:"
        for item in "${installed[@]}"; do
            echo "  $item"
        done
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "缺失的工具:"
        for item in "${missing[@]}"; do
            echo "  $item"
        done
        print_warning ""
        print_warning "建议运行脚本安装依赖: sudo $0"
        return 1
    else
        print_info "所有必需工具已安装 ✓"
        return 0
    fi
}

# 显示使用说明
show_usage() {
    cat << EOF

FluffOS 通用自动编译安装脚本
有问题请联系作者：不一[QQ 279631638]
支持系统:
  - Ubuntu / Debian 及衍生版
  - CentOS / RHEL / Rocky Linux / AlmaLinux
  - Fedora
  - OpenEuler / HCE OS / EulerOS
  - Arch Linux / Manjaro
  - openSUSE / SLES

功能:
  - 自动检测 Linux 发行版
  - 自动从 Git 拉取最新代码
  - 自动编译并安装到全局目录
  - 支持多种构建配置

使用方法:
    $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -y, --yes               非交互模式，所有确认使用默认值
    --check                 检查依赖安装情况
    --info                  显示系统信息后退出
    -c, --clean             清理构建目录后退出
    -d, --debug             使用 Debug 构建类型
    -r, --release           使用 Release 构建类型（生产环境）
    -s, --sanitizer         启用地址消毒器（仅 Debug 模式）
    -t, --test              编译后运行测试
    --skip-update           跳过 Git 更新（使用现有代码）
    --skip-deps             跳过依赖安装

环境变量:
    GIT_REPO                Git 仓库地址（默认: https://github.com/fluffos/fluffos.git）
    GIT_BRANCH              Git 分支（默认: master）
    PROJECT_DIR             项目目录（默认: 脚本所在目录/fluffos）
    INSTALL_DIR             安装目录（默认: /usr/local/bin）
    BUILD_TYPE              构建类型（Debug|Release|RelWithDebInfo）
    ENABLE_SANITIZER        启用 sanitizer（设置为任意值）
    RUN_TESTS               运行测试（设置为任意值）
    CMAKE_EXTRA_OPTS        额外的 CMake 选项

目录结构:
    脚本可放在任意目录，会在同目录下创建 fluffos/ 子目录存放代码：

    /your/path/
    ├── build.sh            ← 脚本位置
    └── fluffos/            ← 自动克隆的项目
        ├── src/
        ├── build/
        └── ...

示例:
    # 标准安装（自动拉取最新代码）
    sudo $0

    # 生产环境安装
    sudo $0 --release

    # 调试构建并运行测试
    sudo $0 --debug --test

    # 使用自定义仓库和分支
    GIT_REPO="https://gitee.com/your/fluffos.git" GIT_BRANCH="develop" sudo $0

    # 跳过更新，只重新编译
    sudo $0 --skip-update

    # 安装到自定义目录
    INSTALL_DIR="/opt/fluffos" sudo $0

EOF
}

# 显示系统信息
show_system_info() {
    detect_system
    check_cmake_version
    check_git

    print_info "======================================"
    print_info "系统信息"
    print_info "======================================"
    print_info "操作系统: $OS_NAME"
    print_info "版本: $OS_VERSION"
    print_info "ID: $OS_ID"
    print_info "发行版类型: $DISTRO_TYPE"
    print_info "包管理器: $PKG_MGR"
    print_info ""

    if command -v gcc &> /dev/null; then
        GCC_VERSION=$(gcc --version | head -n1)
        print_info "GCC: $GCC_VERSION"
    fi

    if command -v g++ &> /dev/null; then
        GXX_VERSION=$(g++ --version | head -n1)
        print_info "G++: $GXX_VERSION"
    fi

    CMAKE_VERSION_FULL=$(cmake --version | head -n1)
    print_info "CMake: $CMAKE_VERSION_FULL"

    GIT_VERSION_FULL=$(git --version 2>/dev/null || echo "Not installed")
    print_info "Git: $GIT_VERSION_FULL"

    print_info ""
    print_info "配置:"
    print_info "Git 仓库: $GIT_REPO"
    print_info "Git 分支: $GIT_BRANCH"
    print_info "项目目录: $PROJECT_DIR"
    print_info "安装目录: $INSTALL_DIR"
    print_info ""
}

# 主函数
main() {
    echo ""
    print_info "======================================"
    print_info "FluffOS 通用自动编译安装脚本"
    print_info "不一[279631638]"
    print_info "======================================"
    echo ""

    print_info "配置信息:"
    print_info "  项目目录: $PROJECT_DIR"
    print_info "  安装目录: $INSTALL_DIR"
    print_info "  Git 仓库: $GIT_REPO"
    print_info "  Git 分支: $GIT_BRANCH"
    echo ""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--yes)
                NON_INTERACTIVE=1
                shift
                ;;
            --check)
                detect_system
                check_dependencies
                exit $?
                ;;
            --info)
                show_system_info
                exit 0
                ;;
            -c|--clean)
                CLEAN_ONLY=1
                shift
                ;;
            -d|--debug)
                BUILD_TYPE="Debug"
                shift
                ;;
            -r|--release)
                BUILD_TYPE="Release"
                shift
                ;;
            -s|--sanitizer)
                ENABLE_SANITIZER=1
                shift
                ;;
            -t|--test)
                RUN_TESTS=1
                shift
                ;;
            --skip-update)
                SKIP_UPDATE=1
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=1
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # 检查 root 权限
    check_root

    # 检测系统
    detect_system

    # 如果只是清理，执行后退出
    if [ -n "$CLEAN_ONLY" ]; then
        clean_build
        print_info "清理完成"
        exit 0
    fi

    # 检查 CMake 和 Git
    check_cmake_version
    check_git

    # 安装依赖
    if [ -z "$SKIP_DEPS" ]; then
        install_dependencies
    else
        print_info "跳过依赖安装"
    fi

    # 更新源代码
    if [ -z "$SKIP_UPDATE" ]; then
        update_source_code
    else
        print_info "跳过 Git 更新"
        if [ ! -d "$PROJECT_DIR" ]; then
            print_error "项目目录不存在: $PROJECT_DIR"
            print_error "请先运行不带 --skip-update 选项的脚本"
            exit 1
        fi
    fi

    # 清理旧构建
    clean_build

    # 配置构建
    configure_build

    # 编译
    compile

    # 安装
    install_driver

    # 运行测试
    run_tests

    # 显示构建信息
    show_build_info
}

# 执行主函数
main "$@"
