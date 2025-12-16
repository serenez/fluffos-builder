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

# 修复 CentOS 7 EOL 源问题
fix_centos7_repos() {
    # 只处理 CentOS 7
    if [[ "$DISTRO_TYPE" != "centos" ]]; then
        return 0
    fi

    # 检查版本是否为 7
    local version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$version_id" != "7" ]; then
        return 0
    fi

    print_warning "检测到 CentOS 7（已 EOL），修复 yum 源..."

    # 备份原始源
    if [ ! -d /etc/yum.repos.d/backup ]; then
        mkdir -p /etc/yum.repos.d/backup
        cp /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    fi

    # 先清理缓存
    yum clean all &>/dev/null

    # 重写 CentOS-Base.repo
    cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-7 - Base - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/
gpgcheck=0
enabled=1

[updates]
name=CentOS-7 - Updates - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/$basearch/
gpgcheck=0
enabled=1

[extras]
name=CentOS-7 - Extras - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/extras/$basearch/
gpgcheck=0
enabled=1

[centosplus]
name=CentOS-7 - Plus - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/centosplus/$basearch/
gpgcheck=0
enabled=0
EOF

    # 重写 SCL 仓库配置
    if [ -f /etc/yum.repos.d/CentOS-SCLo-scl.repo ] || [ -f /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo ]; then
        cat > /etc/yum.repos.d/CentOS-SCLo-scl.repo <<'EOF'
[centos-sclo-sclo]
name=CentOS-7 - SCLo sclo
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/sclo/$basearch/sclo/
gpgcheck=0
enabled=1

[centos-sclo-sclo-testing]
name=CentOS-7 - SCLo sclo Testing
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/sclo/$basearch/sclo/
gpgcheck=0
enabled=0
EOF

        cat > /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo <<'EOF'
[centos-sclo-rh]
name=CentOS-7 - SCLo rh
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/sclo/$basearch/rh/
gpgcheck=0
enabled=1

[centos-sclo-rh-testing]
name=CentOS-7 - SCLo rh Testing
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/sclo/$basearch/rh/
gpgcheck=0
enabled=0
EOF
    fi

    # 重写 EPEL 仓库配置
    cat > /etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch
baseurl=https://mirrors.aliyun.com/epel/7/$basearch
gpgcheck=0
enabled=1

[epel-debuginfo]
name=Extra Packages for Enterprise Linux 7 - $basearch - Debug
baseurl=https://mirrors.aliyun.com/epel/7/$basearch/debug
gpgcheck=0
enabled=0

[epel-source]
name=Extra Packages for Enterprise Linux 7 - $basearch - Source
baseurl=https://mirrors.aliyun.com/epel/7/SRPMS
gpgcheck=0
enabled=0
EOF

    # 禁用或删除可能存在的其他失败的仓库
    for repo in /etc/yum.repos.d/*.repo; do
        if [ -f "$repo" ]; then
            # 禁用所有 mirrorlist
            sed -i 's/^mirrorlist=/#mirrorlist=/g' "$repo" 2>/dev/null || true
        fi
    done

    # 禁用所有第三方仓库（remi, webtatic 等），避免它们导致 yum 失败
    print_info "禁用第三方仓库..."
    for repo_file in /etc/yum.repos.d/remi*.repo /etc/yum.repos.d/webtatic*.repo /etc/yum.repos.d/*-release*.repo; do
        if [ -f "$repo_file" ]; then
            # 备份
            cp "$repo_file" "${repo_file}.bak" 2>/dev/null || true
            # 禁用所有 section
            sed -i 's/^enabled=1/enabled=0/g' "$repo_file" 2>/dev/null || true
            print_info "  已禁用: $(basename $repo_file)"
        fi
    done

    # 重建缓存（忽略失败的仓库）
    print_info "重建 yum 缓存..."
    yum clean all &>/dev/null
    yum makecache 2>&1 | grep -E "(成功|Complete|完成)" || true

    print_info "✓ CentOS 7 yum 源已修复（使用阿里云 vault 镜像 + EPEL）"
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
            # 添加容错选项，跳过失败的仓库
            $PKG_MGR clean all &>/dev/null || true
            $PKG_MGR makecache --skip-broken 2>/dev/null || \
            $PKG_MGR makecache 2>/dev/null || \
            print_warning "软件包列表更新失败（已跳过失败的仓库）"
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
            # 添加容错选项，跳过失败的仓库
            $PKG_MGR install -y --skip-broken "$package" 2>&1 | tee -a /tmp/fluffos-install.log
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
                libevent-devel) echo "libevent-dev" ;;
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
                zstd-devel) echo "libzstd-devel" ;;
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
                libevent-devel) echo "libevent" ;;
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
                libevent-devel) echo "libevent-devel" ;;
                gtest-devel) echo "gtest" ;;
                pkgconfig) echo "pkg-config" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
    esac
}

# 从源代码编译安装 OpenSSL 1.1.1
install_openssl_from_source() {
    print_step "从源代码编译安装 OpenSSL 1.1.1..."

    local temp_dir="/tmp/openssl-build-$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # 下载 OpenSSL 1.1.1w (最后的 1.1.1 版本，LTS)
    local openssl_version="1.1.1w"
    print_info "下载 OpenSSL ${openssl_version}..."

    if ! wget "https://www.openssl.org/source/openssl-${openssl_version}.tar.gz" 2>&1 | grep -v "^--"; then
        print_warning "从官方源下载失败，尝试备用源..."
        if ! wget "https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1w.tar.gz" -O "openssl-${openssl_version}.tar.gz" 2>&1 | grep -v "^--"; then
            print_error "下载 OpenSSL 源代码失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    print_info "解压并编译..."
    tar -xzf "openssl-${openssl_version}.tar.gz"
    cd "openssl-${openssl_version}" || cd openssl-OpenSSL* || {
        print_error "无法进入 OpenSSL 源代码目录"
        rm -rf "$temp_dir"
        return 1
    }

    # 配置和编译（安装到 /usr/local/openssl111）
    print_info "配置 OpenSSL（这可能需要几分钟）..."
    if ! ./config --prefix=/usr/local/openssl111 --openssldir=/usr/local/openssl111 shared zlib; then
        print_error "OpenSSL 配置失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "编译 OpenSSL（使用 $(nproc) 个并行任务，这可能需要 5-10 分钟）..."
    if ! make -j$(nproc); then
        print_error "OpenSSL 编译失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "安装 OpenSSL..."
    if ! make install; then
        print_error "OpenSSL 安装失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "✓ OpenSSL ${openssl_version} 编译安装成功"

    # 设置环境变量，让 CMake 能找到新的 OpenSSL
    export OPENSSL_ROOT_DIR=/usr/local/openssl111
    export PKG_CONFIG_PATH=/usr/local/openssl111/lib/pkgconfig:$PKG_CONFIG_PATH
    export LD_LIBRARY_PATH=/usr/local/openssl111/lib:$LD_LIBRARY_PATH

    # 更新动态库缓存
    echo "/usr/local/openssl111/lib" > /etc/ld.so.conf.d/openssl111.conf
    ldconfig

    # 验证安装
    if [ -f "/usr/local/openssl111/bin/openssl" ]; then
        print_info "OpenSSL 版本: $(/usr/local/openssl111/bin/openssl version)"
    fi

    # 清理
    cd /
    rm -rf "$temp_dir"
    return 0
}

# 从源代码编译安装 zstd
install_zstd_from_source() {
    print_step "从源代码编译安装 zstd..."

    local temp_dir="/tmp/zstd-build-$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # 下载 zstd 源代码
    local zstd_version="1.5.6"
    print_info "下载 zstd ${zstd_version}..."

    if ! wget "https://github.com/facebook/zstd/releases/download/v${zstd_version}/zstd-${zstd_version}.tar.gz" 2>&1 | grep -v "^--"; then
        print_warning "从 GitHub 下载失败，尝试备用源..."
        if ! wget "https://gitee.com/mirrors/zstd/repository/archive/v${zstd_version}.tar.gz" -O "zstd-${zstd_version}.tar.gz" 2>&1 | grep -v "^--"; then
            print_error "下载 zstd 源代码失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    print_info "解压并编译..."
    tar -xzf "zstd-${zstd_version}.tar.gz"
    cd "zstd-${zstd_version}" || cd zstd-v* || {
        print_error "无法进入 zstd 源代码目录"
        rm -rf "$temp_dir"
        return 1
    }

    # 编译安装
    print_info "编译 zstd（使用 $(nproc) 个并行任务）..."
    if make -j$(nproc) && make install; then
        print_info "✓ zstd 编译安装成功"

        # 更新动态库缓存
        ldconfig 2>/dev/null || true

        # 验证安装
        if command -v zstd &> /dev/null; then
            print_info "zstd 版本: $(zstd --version | head -n1)"
        fi

        # 清理
        cd /
        rm -rf "$temp_dir"
        return 0
    else
        print_error "zstd 编译失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
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
        wget
        zlib-devel
        pcre-devel
        openssl-devel
        bzip2-devel
        elfutils-devel
        xz-devel
    )

    # zstd 单独处理（CentOS 7 可能没有或需要特殊处理）
    SPECIAL_PACKAGES=(
        zstd-devel
    )

    OPTIONAL_PACKAGES=(
        sqlite-devel
        # mariadb-devel  # 禁用：CentOS 7 的 MySQL/MariaDB 库与新版 OpenSSL 冲突
        postgresql-devel
        libicu-devel
        jemalloc-devel
        libevent-devel
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

    # 处理特殊包（如 zstd）
    print_info "处理特殊依赖包..."
    for pkg in "${SPECIAL_PACKAGES[@]}"; do
        real_pkg=$(get_package_name "$pkg")
        if [ -z "$real_pkg" ]; then
            continue
        fi

        print_info "尝试安装 $pkg → $real_pkg ..."
        local pkg_installed=0

        # 先尝试从包管理器安装
        for p in $real_pkg; do
            if install_package "$p"; then
                print_info "✓ $p 从包管理器安装成功"
                pkg_installed=1
                break
            fi
        done

        # 如果包管理器安装失败，尝试从源代码编译
        if [ $pkg_installed -eq 0 ]; then
            print_warning "$pkg 从包管理器安装失败，尝试从源代码编译..."
            case "$pkg" in
                zstd-devel)
                    if install_zstd_from_source; then
                        print_info "✓ $pkg 从源代码安装成功"
                    else
                        print_warning "$pkg 从源代码安装也失败，将在 CMake 配置中禁用 zstd"
                        # 设置环境变量，用于后续 CMake 配置
                        export DISABLE_ZSTD=1
                    fi
                    ;;
                *)
                    print_warning "$pkg 安装失败，可能影响部分功能"
                    ;;
            esac
        fi
    done

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

            # 尝试获取远程仓库 URL（优先 origin，然后尝试其他远程仓库）
            local remote_url=$(git remote get-url origin 2>/dev/null)
            if [ -z "$remote_url" ]; then
                # 如果没有 origin，获取第一个远程仓库
                remote_url=$(git remote -v 2>/dev/null | grep fetch | head -1 | awk '{print $2}')
            fi
            if [ -z "$remote_url" ]; then
                remote_url="无远程仓库"
            fi

            # 如果没有远程仓库，添加默认的
            if [ "$remote_url" = "无远程仓库" ]; then
                print_warning "未检测到远程仓库，添加默认远程仓库"
                git remote add origin "$GIT_REPO" 2>/dev/null || true
                git fetch origin 2>/dev/null || true
                remote_url="$GIT_REPO (已自动添加)"
            fi

            echo ""
            print_info "当前项目信息:"
            print_info "  远程仓库: $remote_url"
            print_info "  当前分支: $current_branch"
            print_info "  最新提交: $current_commit"
            echo ""

            # 检查是否已经是最新（带超时）
            print_info "正在检查远程更新（超时 10 秒）..."
            local is_up_to_date=false
            if timeout 10 git fetch origin "$GIT_BRANCH" &>/dev/null; then
                local local_commit=$(git rev-parse HEAD 2>/dev/null)
                local remote_commit=$(git rev-parse origin/"$GIT_BRANCH" 2>/dev/null)
                if [ "$local_commit" = "$remote_commit" ]; then
                    is_up_to_date=true
                    print_info "  状态: ✓ 已是最新版本"
                else
                    print_warning "  状态: 有可用更新"
                fi
            else
                print_warning "  状态: 无法检查更新（网络超时或失败）"
            fi
            echo ""

            # 如果已经是最新，直接使用
            if [ "$is_up_to_date" = true ]; then
                print_info "✓ 使用现有最新代码，跳过更新"
            elif ask_yes_no "是否更新代码？" "n"; then
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
                git --no-pager log -1 --oneline --decorate
            else
                print_info "使用现有代码，跳过更新"
            fi

        else
            print_warning "目录 $PROJECT_DIR 存在但不是 Git 仓库"
            if ask_yes_no "是否删除现有目录并重新克隆？" "n"; then
                rm -rf "$PROJECT_DIR"
                try_clone_from_mirrors
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
            try_clone_from_mirrors
        else
            print_error "用户取消操作"
            exit 1
        fi
    fi
}

# 克隆 Git 仓库
clone_repository() {
    local repo_url="$1"
    local repo_name="$2"

    print_info "克隆 FluffOS 仓库 (${repo_name})..."
    print_info "仓库地址: $repo_url"
    print_info "目标目录: $PROJECT_DIR"
    print_info "分支: $GIT_BRANCH"

    # 创建父目录
    mkdir -p "$(dirname "$PROJECT_DIR")"

    # 克隆仓库（显示进度）
    print_info "开始下载，请稍候..."
    if git clone --progress --branch "$GIT_BRANCH" "$repo_url" "$PROJECT_DIR" 2>&1 | while IFS= read -r line; do
        # 显示 git clone 的输出
        echo "$line"
    done; then
        # 验证克隆是否真的成功
        if [ -d "$PROJECT_DIR/.git" ]; then
            cd "$PROJECT_DIR" || {
                print_error "无法进入项目目录"
                return 1
            }
            print_info "✓ 仓库克隆成功"
            print_info "当前版本:"
            git --no-pager log -1 --oneline --decorate
            return 0
        else
            print_error "✗ 克隆失败：目录创建但不是有效的 Git 仓库"
            return 1
        fi
    else
        print_error "✗ 克隆仓库失败"
        return 1
    fi
}

# 尝试从多个源克隆仓库
try_clone_from_mirrors() {
    # GitHub 官方源
    local github_repo="https://github.com/fluffos/fluffos.git"
    # Gitee 镜像源
    local gitee_repo="https://gitee.com/fluffos/fluffos.git"

    # 如果用户指定了自定义仓库，优先使用
    if [ "$GIT_REPO" != "$github_repo" ] && [ "$GIT_REPO" != "$gitee_repo" ]; then
        print_info "使用自定义仓库: $GIT_REPO"
        if clone_repository "$GIT_REPO" "自定义源"; then
            return 0
        else
            print_warning "自定义仓库克隆失败，尝试官方源"
        fi
    fi

    # 尝试 GitHub 官方源
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "尝试从 GitHub 官方源克隆..."
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if clone_repository "$github_repo" "GitHub"; then
        return 0
    fi

    # GitHub 失败���尝试 Gitee
    print_warning "GitHub 克隆失败（可能是网络问题）"
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "自动切换到 Gitee 镜像源..."
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 清理失败的克隆
    if [ -d "$PROJECT_DIR" ]; then
        print_info "清理失败的克隆目录..."
        rm -rf "$PROJECT_DIR"
    fi

    if clone_repository "$gitee_repo" "Gitee 镜像"; then
        print_info "✓ 已成功从 Gitee 镜像克隆"
        return 0
    fi

    # 都失败了
    print_error "所有源都克隆失败"
    print_error ""
    print_error "请检查："
    print_error "  1. 网络连接是否正常"
    print_error "  2. 是否可以访问 GitHub 或 Gitee"
    print_error "  3. Git 版本是否过旧"
    print_error ""
    print_error "手动克隆命令："
    print_error "  git clone $github_repo $PROJECT_DIR"
    print_error "  或"
    print_error "  git clone $gitee_repo $PROJECT_DIR"
    exit 1
}

# 安装 pip（如果没有）
install_pip() {
    print_step "检查并安装 pip..." >&2

    # 优先使用 pip3
    if command -v pip3 &> /dev/null; then
        print_info "✓ pip3 已安装: $(pip3 --version)" >&2
        echo "pip3"
        return 0
    elif command -v pip &> /dev/null; then
        print_info "✓ pip 已安装: $(pip --version)" >&2
        echo "pip"
        return 0
    fi

    # pip 未安装，尝试安装
    print_info "pip 未安装，正在安装..." >&2

    case "$PKG_MGR" in
        apt)
            if apt install -y python3-pip >&2; then
                print_info "✓ pip3 安装成功" >&2
                echo "pip3"
                return 0
            fi
            ;;
        dnf|yum)
            # 尝试 python3-pip
            if $PKG_MGR install -y python3-pip 2>/dev/null >&2; then
                print_info "✓ pip3 安装成功" >&2
                echo "pip3"
                return 0
            fi
            # 如果失败，尝试 python-pip (Python 2)
            if $PKG_MGR install -y python-pip 2>/dev/null >&2; then
                print_info "✓ pip 安装成功" >&2
                echo "pip"
                return 0
            fi
            # 如果还是失败，尝试 EPEL
            print_info "尝试启用 EPEL 仓库..." >&2
            if $PKG_MGR install -y epel-release 2>/dev/null >&2; then
                # 更新缓存
                print_info "更新包缓存..." >&2
                $PKG_MGR makecache fast 2>/dev/null >&2 || $PKG_MGR makecache 2>/dev/null >&2 || true
                # 再次尝试安装 python3-pip
                if $PKG_MGR install -y python3-pip 2>/dev/null >&2; then
                    print_info "✓ pip3 安装成功（通过 EPEL）" >&2
                    echo "pip3"
                    return 0
                fi
                # 如果还是失败，尝试 python2-pip
                if $PKG_MGR install -y python2-pip 2>/dev/null >&2; then
                    print_info "✓ pip 安装成功（通过 EPEL）" >&2
                    echo "pip"
                    return 0
                fi
            fi
            ;;
        pacman)
            if pacman -S --noconfirm python-pip >&2; then
                print_info "✓ pip 安装成功" >&2
                echo "pip"
                return 0
            fi
            ;;
        zypper)
            if zypper install -y python3-pip >&2; then
                print_info "✓ pip3 安装成功" >&2
                echo "pip3"
                return 0
            fi
            ;;
    esac

    print_warning "pip 安装失败" >&2
    return 1
}

# 使用 pip 安装 CMake（推荐方式）
install_cmake_pip() {
    print_step "使用 pip 安装最新版本 CMake..."

    # 安装或检查 pip
    local pip_cmd=$(install_pip)
    if [ $? -ne 0 ] || [ -z "$pip_cmd" ]; then
        print_error "无法安装 pip，请使用其他安装方式"
        return 1
    fi

    print_info "使用 $pip_cmd 安装 CMake..."

    # 升级 pip 本身
    print_info "升级 pip..."
    $pip_cmd install --upgrade pip 2>&1 | grep -v "WARNING" || true

    # 安装 cmake
    print_info "安装 CMake（这可能需要几分钟）..."
    if $pip_cmd install --upgrade cmake; then
        print_info "✓ pip 安装完成"

        # 刷新命令缓存
        hash -r 2>/dev/null || true

        # 查找 pip 安装的 cmake 位置
        print_info "查找 cmake 可执行文件..."
        local cmake_path=""

        # 常见的 pip 安装位置
        local possible_paths=(
            "/usr/local/bin/cmake"
            "/usr/local/python3/bin/cmake"
            "$HOME/.local/bin/cmake"
            "$(python3 -c 'import sys; print(sys.prefix)' 2>/dev/null)/bin/cmake"
            "$(dirname $(which python3) 2>/dev/null)/cmake"
        )

        for path in "${possible_paths[@]}"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                cmake_path="$path"
                print_info "✓ 找到 cmake: $cmake_path"
                break
            fi
        done

        # 如果上面没找到，使用 find 命令搜索
        if [ -z "$cmake_path" ]; then
            print_info "使用 find 搜索 cmake..."
            local python_prefix=$(python3 -c 'import sys; print(sys.prefix)' 2>/dev/null)
            if [ -n "$python_prefix" ]; then
                cmake_path=$(find "$python_prefix" -name cmake -type f -executable 2>/dev/null | head -1)
                if [ -n "$cmake_path" ]; then
                    print_info "✓ 找到 cmake: $cmake_path"
                fi
            fi
        fi

        # 如果找到了但不在 /usr/local/bin，创建符号链接
        if [ -n "$cmake_path" ] && [ "$cmake_path" != "/usr/local/bin/cmake" ]; then
            print_info "创建符号链接到 /usr/local/bin/cmake..."
            ln -sf "$cmake_path" /usr/local/bin/cmake 2>/dev/null || true
        fi

        # 更新 PATH
        export PATH="/usr/local/bin:$(dirname $(which python3) 2>/dev/null):$PATH"
        hash -r 2>/dev/null || true

        # 获取项目要求的版本
        local required_full=$(get_required_cmake_version)
        local required_major=$(echo "$required_full" | cut -d. -f1)
        local required_minor=$(echo "$required_full" | cut -d. -f2)

        # 验证安装并检查版本
        if command -v cmake &> /dev/null; then
            local new_version=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
            local new_major=$(echo "$new_version" | cut -d. -f1)
            local new_minor=$(echo "$new_version" | cut -d. -f2)

            print_info "检测��� CMake 版本: $new_version"
            print_info "项目要求版本: >= ${required_major}.${required_minor}"

            # 验证版本是否满足项目要求
            if [ "$new_major" -gt "$required_major" ] || ([ "$new_major" -eq "$required_major" ] && [ "$new_minor" -ge "$required_minor" ]); then
                print_info "✓ CMake 升级成功：$new_version >= ${required_major}.${required_minor}"
                return 0
            else
                print_error "CMake 版本仍然过低: $new_version < ${required_major}.${required_minor}"
                print_error "可能是 PATH 问题，请检查："
                print_error "  which cmake: $(which cmake)"
                print_error "  /usr/local/bin/cmake --version:"
                /usr/local/bin/cmake --version 2>&1 | head -1 || true
                return 1
            fi
        else
            print_error "CMake 命令未找到"
            print_error "pip 安装成功但 cmake 不在 PATH 中"
            return 1
        fi
    else
        print_error "pip 安装 CMake 失败"
        return 1
    fi
}

# 从项目 CMakeLists.txt 读取要求的 CMake 版本
get_required_cmake_version() {
    local cmake_file="$PROJECT_DIR/CMakeLists.txt"

    if [ ! -f "$cmake_file" ]; then
        print_warning "未找到项目的 CMakeLists.txt，使用默认版本 3.22" >&2
        echo "3.22.0"
        return
    fi

    # 读取 cmake_minimum_required(VERSION x.y.z) 或 cmake_minimum_required(VERSION x.y)
    local required_version=$(grep -i "cmake_minimum_required" "$cmake_file" | head -1 | grep -oP 'VERSION\s+\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "")

    if [ -z "$required_version" ]; then
        print_warning "无法从 CMakeLists.txt 读取版本要求，使用默认版本 3.22" >&2
        echo "3.22.0"
        return
    fi

    # 确保版本是 x.y.z 格式（如果只有 x.y，补充 .0）
    if [[ ! "$required_version" =~ \.[0-9]+$ ]]; then
        required_version="${required_version}.0"
    fi

    print_info "项目要求 CMake 版本: $required_version (来自 CMakeLists.txt)" >&2
    echo "$required_version"
}

# 从预编译二进制安装 CMake
install_cmake_binary() {
    local cmake_version="${1:-auto}"

    # 如果是 auto，使用项目要求的版本
    if [ "$cmake_version" = "auto" ]; then
        cmake_version=$(get_required_cmake_version)
    fi

    local arch=$(uname -m)

    print_step "从预编译二进制安装 CMake ${cmake_version}..."

    # 确定架构
    if [ "$arch" = "x86_64" ]; then
        cmake_arch="x86_64"
    elif [ "$arch" = "aarch64" ]; then
        cmake_arch="aarch64"
    else
        print_error "不支持的架构: $arch"
        return 1
    fi

    local cmake_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-linux-${cmake_arch}.tar.gz"
    local temp_dir="/tmp/cmake-install-$$"

    mkdir -p "$temp_dir"
    cd "$temp_dir"

    print_info "下载 CMake ${cmake_version}..."
    print_info "下载地址: $cmake_url"

    if ! wget "$cmake_url" -O cmake.tar.gz 2>&1 | grep -v "^--"; then
        print_error "下载失败，可能是版本号不正确或网络问题"
        print_warning "尝试使用备用版本 3.30.2"

        # 尝试备用版本
        cmake_version="3.30.2"
        cmake_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-linux-${cmake_arch}.tar.gz"

        if ! wget "$cmake_url" -O cmake.tar.gz 2>&1 | grep -v "^--"; then
            print_error "备用版本下载也失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    print_info "解压并安装..."
    tar -xzf cmake.tar.gz

    # 安装到 /usr/local
    local cmake_dir=$(ls -d cmake-${cmake_version}-linux-${cmake_arch} 2>/dev/null)
    if [ -d "$cmake_dir" ]; then
        # 备份旧版本（如果存在）
        if [ -d "/usr/local/cmake" ]; then
            print_info "备份旧版本..."
            mv /usr/local/cmake /usr/local/cmake.bak.$(date +%s)
        fi

        # 安装新版本
        mv "$cmake_dir" /usr/local/cmake

        # 创建符号链接
        ln -sf /usr/local/cmake/bin/cmake /usr/local/bin/cmake
        ln -sf /usr/local/cmake/bin/ctest /usr/local/bin/ctest
        ln -sf /usr/local/cmake/bin/cpack /usr/local/bin/cpack

        print_info "✓ CMake ${cmake_version} 安装成功"
        print_info "安装位置: /usr/local/cmake"

        # 验证安装
        /usr/local/bin/cmake --version

        # 清理临时文件
        cd /
        rm -rf "$temp_dir"
        return 0
    else
        print_error "解压失败"
        rm -rf "$temp_dir"
        return 1
    fi
}

# 从源代码编译安装 CMake
install_cmake_source() {
    local cmake_version="${1:-auto}"

    # 如果是 auto，使用项目要求的版本
    if [ "$cmake_version" = "auto" ]; then
        cmake_version=$(get_required_cmake_version)
    fi

    print_step "从源代码编译安装 CMake ${cmake_version}..."
    print_warning "这可能需要 10-30 分钟，请耐心等待..."

    local temp_dir="/tmp/cmake-build-$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    print_info "下载 CMake ${cmake_version} 源代码..."
    local cmake_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}.tar.gz"

    if ! wget "$cmake_url" 2>&1 | grep -v "^--"; then
        print_error "下载失败，可能是版本号不正确或网络问题"
        print_warning "尝试使用备用版本 3.30.2"

        # 尝试备用版本
        cmake_version="3.30.2"
        cmake_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}.tar.gz"

        if ! wget "$cmake_url" 2>&1 | grep -v "^--"; then
            print_error "备用版本下载也失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    print_info "解压源代码..."
    tar -xzf "cmake-${cmake_version}.tar.gz"
    cd "cmake-${cmake_version}"

    print_info "配置编译选项..."
    if ! ./bootstrap --prefix=/usr/local; then
        print_error "配置失败"
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "开始编译（使用 $(nproc) 个并行任务）..."
    if ! make -j$(nproc); then
        print_error "编译失败"
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "安装 CMake..."
    if ! make install; then
        print_error "安装失败"
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "✓ CMake ${cmake_version} 编译安装成功"

    # 验证安装
    /usr/local/bin/cmake --version

    # 清理临时文件
    cd /
    rm -rf "$temp_dir"
    return 0
}

# 检查 OpenSSL 版本
check_openssl_version() {
    print_step "检查 OpenSSL 版本..."

    # 检查是否已经安装了新版本 OpenSSL
    if [ -f "/usr/local/openssl111/bin/openssl" ]; then
        local ssl_version=$(/usr/local/openssl111/bin/openssl version | grep -oP 'OpenSSL \K[0-9]+\.[0-9]+\.[0-9]+')
        print_info "检测到已安装的 OpenSSL 1.1.1: $ssl_version"
        export OPENSSL_ROOT_DIR=/usr/local/openssl111
        export PKG_CONFIG_PATH=/usr/local/openssl111/lib/pkgconfig:$PKG_CONFIG_PATH
        export LD_LIBRARY_PATH=/usr/local/openssl111/lib:$LD_LIBRARY_PATH
        print_info "✓ OpenSSL 版本检查通过"
        return 0
    fi

    # 检查系统 OpenSSL 版本
    if ! command -v openssl &> /dev/null; then
        print_error "OpenSSL 未安装"
        return 1
    fi

    local ssl_version=$(openssl version | grep -oP 'OpenSSL \K[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0")
    local ssl_major=$(echo "$ssl_version" | cut -d. -f1)
    local ssl_minor=$(echo "$ssl_version" | cut -d. -f2)

    print_info "当前 OpenSSL 版本: $ssl_version"
    print_info "FluffOS 要求: OpenSSL 1.1.0+"

    # 检查版本是否满足要求（需要 1.1.0+）
    if [ "$ssl_major" -lt 1 ] || ([ "$ssl_major" -eq 1 ] && [ "$ssl_minor" -lt 1 ]); then
        print_warning "OpenSSL 版本过低，需要 1.1.0 或更高版本（当前: $ssl_version）"
        echo ""

        # CentOS 7 系统，自动升级 OpenSSL
        if [[ "$DISTRO_TYPE" == "centos" ]] || [[ "$DISTRO_TYPE" == "rhel" ]]; then
            print_info "CentOS 7 检测到旧版 OpenSSL，正在自动升级到 1.1.1..."
            if install_openssl_from_source; then
                print_info "✓ OpenSSL 自动升级成功"
                return 0
            else
                print_error "OpenSSL 升级失败"
                exit 1
            fi
        else
            # 其他系统，提示用户
            print_error "请升级 OpenSSL 到 1.1.0+ 版本"
            exit 1
        fi
    else
        print_info "✓ OpenSSL 版本检查通过"
    fi
}

# 检查 CMake 版本
check_cmake_version() {
    print_step "检查 CMake 版本..."

    # 从项目获取要求的版本
    local required_full=$(get_required_cmake_version)
    local required_major=$(echo "$required_full" | cut -d. -f1)
    local required_minor=$(echo "$required_full" | cut -d. -f2)

    if ! command -v cmake &> /dev/null; then
        print_error "CMake 未安装！"
        print_error "这不应该发生，请检查依赖安装步骤"
        exit 1
    fi

    CMAKE_VERSION=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
    CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)

    print_info "当前 CMake 版本: $CMAKE_VERSION"
    print_info "项目要求版本: >= ${required_major}.${required_minor}"

    # 检查版本是否满足项目要求
    if [ "$CMAKE_MAJOR" -lt "$required_major" ] || ([ "$CMAKE_MAJOR" -eq "$required_major" ] && [ "$CMAKE_MINOR" -lt "$required_minor" ]); then
        print_warning "CMake 版本过低，需要 ${required_major}.${required_minor} 或更高版本（当前: $CMAKE_VERSION）"
        echo ""

        # 无论交互还是非交互模式，都先自动尝试 pip 升级（最简单）
        print_info "正在自动升级 CMake（使用 pip，最简单的方式）..."
        if install_cmake_pip; then
            print_info "✓ CMake 自动升级成功，继续构建"
            return 0
        fi

        # pip 失败，提示用户
        print_warning "pip 自动升级失败"
        echo ""

        # 非交互模式，尝试预编译二进制
        if [ -n "$NON_INTERACTIVE" ]; then
            print_info "非交互模式，尝试预编译二进制包..."
            if install_cmake_binary "auto"; then
                print_info "✓ 预编译二进制安装成功，继续构建"
                return 0
            fi

            # 都失败了
            print_error "所有自动安装方式都失败了"
            print_error "请手动安装 CMake 3.22+ 后重新运行脚本"
            print_error ""
            print_error "快速安装方法："
            print_error "  sudo yum install -y python3-pip"
            print_error "  sudo pip3 install cmake --upgrade"
            exit 1
        fi

        # 交互模式，询问用户选择其他方式
        print_info "请选择其他升级方式:"
        local choice=$(ask_choice "如何安装 CMake？" \
            "安装预编译二进制包（推荐，快速，无需编译）" \
            "从源代码编译安装（慢，10-30分钟）" \
            "手动安装，查看安装指南后退出")

        case "$choice" in
            1)
                # 预编译二进制
                if install_cmake_binary "auto"; then
                    print_info "✓ CMake 升级成功，继续构建..."
                else
                    print_error "安装失败"
                    exit 1
                fi
                ;;
            2)
                # 源代码编译
                if install_cmake_source "auto"; then
                    print_info "✓ CMake 编译安装成功，继续构建..."
                else
                    print_error "编译安装失败"
                    exit 1
                fi
                ;;
            3)
                # 手动安装指南
                print_info "请手动升级 CMake 后重新运行脚本"
                echo ""
                print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                print_info "推荐方式 - 使用 pip（最简单）:"
                print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                print_info "  sudo yum install -y python3-pip"
                print_info "  sudo pip3 install cmake --upgrade"
                print_info "  cmake --version  # 验证版本"
                echo ""
                print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                print_info "或使用预编译二进制包:"
                print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                print_info "  wget https://github.com/Kitware/CMake/releases/download/v3.30.2/cmake-3.30.2-linux-x86_64.tar.gz"
                print_info "  tar -xzf cmake-3.30.2-linux-x86_64.tar.gz"
                print_info "  sudo mv cmake-3.30.2-linux-x86_64 /usr/local/cmake"
                print_info "  sudo ln -sf /usr/local/cmake/bin/cmake /usr/local/bin/cmake"
                echo ""
                print_info "更多版本: https://cmake.org/download/"
                exit 1
                ;;
        esac
    else
        print_info "✓ CMake 版本检查通过"
    fi
}

# 检查并升级 GCC 版本（FluffOS 需要 C++17，要求 GCC 7+）
check_gcc_version() {
    print_step "检查 GCC 版本..."

    # 检查 g++ 是否安装
    if ! command -v g++ &> /dev/null; then
        print_error "g++ 未安装"
        exit 1
    fi

    # 获取 GCC 版本（只获取第一个匹配）
    local gcc_version=$(g++ --version | head -n1 | grep -oP '\d+\.\d+\.\d+' | head -1)
    if [ -z "$gcc_version" ]; then
        gcc_version="0.0.0"
    fi
    local gcc_major=$(echo "$gcc_version" | head -1 | cut -d. -f1)

    print_info "当前 GCC 版本: $gcc_version"
    print_info "FluffOS 要求: GCC 7+ (支持 C++17)"

    # 确保 gcc_major 是有效数字
    if [ -z "$gcc_major" ] || ! [[ "$gcc_major" =~ ^[0-9]+$ ]]; then
        print_error "无法检测 GCC 版本"
        exit 1
    fi

    # 检查版本是否满足要求（需要 GCC 7+）
    if [ "$gcc_major" -lt 7 ] 2>/dev/null; then
        print_warning "GCC 版本过低，需要 7.0 或更高版本��当前: $gcc_version）"
        echo ""

        # 对于 CentOS/RHEL，使用 devtoolset
        if [[ "$DISTRO_TYPE" == "centos" ]] || [[ "$DISTRO_TYPE" == "rhel" ]]; then
            print_info "正在安装 Developer Toolset（GCC 7+）..."

            # 安装 SCL
            yum install -y centos-release-scl scl-utils || {
                print_error "无法安装 SCL 仓库"
                exit 1
            }

            # 刷新 yum 缓存
            print_info "刷新 yum 缓存..."
            yum clean all &>/dev/null
            yum makecache fast

            # 尝试安装 devtoolset（从新到旧）
            local devtoolset_installed=false
            for version in 11 10 9 8 7; do
                print_info "尝试安装 devtoolset-${version}..."
                if yum install -y devtoolset-${version}-gcc devtoolset-${version}-gcc-c++; then
                    print_info "✓ devtoolset-${version} 安装成功"

                    # 激活 devtoolset
                    print_info "激活 devtoolset-${version}..."
                    source /opt/rh/devtoolset-${version}/enable

                    # 验证新版本
                    local new_gcc_version=$(g++ --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
                    print_info "✓ GCC 升级成功: $new_gcc_version"

                    # 设置编译器环境变量
                    export CC=/opt/rh/devtoolset-${version}/root/usr/bin/gcc
                    export CXX=/opt/rh/devtoolset-${version}/root/usr/bin/g++

                    devtoolset_installed=true
                    break
                fi
            done

            if [ "$devtoolset_installed" = false ]; then
                print_error "无法安装任何 devtoolset 版本"
                exit 1
            fi

        else
            print_error "不支持的系统类型，请手动安装 GCC 7+"
            print_error "参考: https://gcc.gnu.org/install/"
            exit 1
        fi
    else
        print_info "✓ GCC 版本检查通过"
    fi
}

# 临时卸载 gtest（避免测试编译失败）
disable_gtest() {
    # 如果安装了新版 OpenSSL，需要避免编译测试（gtest 太旧）
    if [ -n "$OPENSSL_ROOT_DIR" ]; then
        print_step "临时移除 gtest（避免测试编译问题）..."

        # 检查是否安装了 gtest
        if rpm -qa | grep -q gtest; then
            # 移动而不是卸载，避免依赖问题
            if [ -f /usr/include/gtest/gtest.h ]; then
                mkdir -p /tmp/fluffos-gtest-backup
                mv /usr/include/gtest /tmp/fluffos-gtest-backup/ 2>/dev/null || true
                print_info "✓ 已临时移除 gtest 头文件"
            fi
        fi
    fi
}

# 恢复 gtest
restore_gtest() {
    if [ -d /tmp/fluffos-gtest-backup/gtest ]; then
        print_info "恢复 gtest 头文件..."
        mv /tmp/fluffos-gtest-backup/gtest /usr/include/ 2>/dev/null || true
        rm -rf /tmp/fluffos-gtest-backup
    fi
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

    # 如果安装了新版本 OpenSSL，告诉 CMake 使用它
    if [ -n "$OPENSSL_ROOT_DIR" ]; then
        CMAKE_OPTS+=(-DOPENSSL_ROOT_DIR="$OPENSSL_ROOT_DIR")
        print_info "使用 OpenSSL: $OPENSSL_ROOT_DIR"

        # 禁用 MySQL 支持，避免 OpenSSL 版本冲突
        # CentOS 7 的 MySQL 库链接了旧版 OpenSSL 1.0，与新版 1.1 冲突
        # 注意：必须使用空字符串 "" 而不是 OFF
        CMAKE_OPTS+=(-DPACKAGE_DB_MYSQL="")
        print_warning "已禁用 MySQL 支持（避免 OpenSSL 版本冲突）"
    fi

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

    # 编译并安装（一步完成）
    if ! make -j"$NPROC" install; then
        print_error "编译失败"
        exit 1
    fi

    print_info "编译完成！"

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
    # 确保 /usr/local/bin 在 PATH 最前面（pip 安装的命令在这里）
    export PATH="/usr/local/bin:$PATH"

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

    # 修复 CentOS 7 EOL 源问题
    fix_centos7_repos

    # 如果只是清理，执行后退出
    if [ -n "$CLEAN_ONLY" ]; then
        clean_build
        print_info "清理完成"
        exit 0
    fi

    # 先检查 Git（必须先有 Git 才能 clone）
    check_git

    # 第一步：先获取项目源代码
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

    # 第二步：安装依赖
    if [ -z "$SKIP_DEPS" ]; then
        install_dependencies
    else
        print_info "跳过依赖安装"
    fi

    # 第三步：检查 OpenSSL 版本（FluffOS 需要 1.1.0+）
    check_openssl_version

    # 第四步：检查 CMake 版本（根据项目要求）
    check_cmake_version

    # 第五步：检查 GCC 版本（C++17 支持）
    check_gcc_version

    # 临时禁用 gtest（避免编译失败）
    disable_gtest

    # 清理旧构建
    clean_build

    # 配置构建
    configure_build

    # 编译
    compile

    # 恢复 gtest
    restore_gtest

    # 安装
    install_driver

    # 运行测试
    run_tests

    # 显示构建信息
    show_build_info
}

# 执行主函数
main "$@"
