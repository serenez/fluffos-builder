# FluffOS 自动编译安装工具

一键安装 FluffOS 驱动程序的自动化脚本，支持多种 Linux 发行版。

## ✨ 特性

- 🚀 **一键安装** - 单条命令完成所有操作
- 🔧 **跨平台** - 支持 Ubuntu、Debian、CentOS、RHEL、Fedora、OpenEuler、HCE OS、Arch Linux、openSUSE
- 🤖 **智能检测** - 自动识别系统类型和包管理器
- 💬 **交互友好** - 清晰的提示和确认
- 📦 **自动化支持** - 非交互模式适合 CI/CD
- 🎯 **灵活控制** - 可选是否全局安装

## 🚀 快速开始

### 方式 1：一键安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh)
```

或使用 wget：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh)
```

### 方式 2：下载后运行

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/build.sh -o build.sh

# 添加执行权限
chmod +x build.sh

# 运行
sudo ./build.sh
```

### 方式 3：克隆仓库

```bash
git clone https://github.com/serenez/fluffos-builder.git
cd fluffos-builder
sudo ./build.sh
```

## 📋 系统支持

| 系统 | 版本 | 状态 |
|------|------|------|
| Ubuntu | 18.04+ | ✅ 完全支持 |
| Debian | 10+ | ✅ 完全支持 |
| CentOS | 7+ | ✅ 完全支持 |
| RHEL | 7+ | ✅ 完全支持 |
| Fedora | 30+ | ✅ 完全支持 |
| OpenEuler | 20.03+ | ✅ 完全支持 |
| HCE OS | 2.0+ | ✅ 完全支持 |
| Arch Linux | - | ✅ 完全支持 |
| openSUSE | 15+ | ✅ 完全支持 |

## 💡 使用示例

### 标准安装

```bash
# 交互模式（会询问确认）
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh)
```

### 非交互安装（自动化）

```bash
# 所有确认使用默认值
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y
```

### 生产环境部署

```bash
# Release 构建 + 非交互
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y --release
```

### 开发环境部署

```bash
# Debug 构建 + 运行测试
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y --debug --test
```

### 指定安装目录

```bash
# 安装到自定义目录
INSTALL_DIR=/opt/fluffos bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y
```

### 使用 Gitee 镜像（国内加速）

```bash
# 使用 Gitee 镜像
GIT_REPO="https://gitee.com/mirrors/fluffos.git" \
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y
```

## 🎮 命令选项

### 安装脚本选项

```bash
-h, --help      显示帮助信息
-y, --yes       非交互模式
-d, --debug     Debug 构建
-r, --release   Release 构建
-t, --test      运行测试
--skip-deps     跳过依赖安装
--skip-update   跳过代码更新
```

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `GIT_REPO` | Git 仓库地址 | https://github.com/fluffos/fluffos.git |
| `GIT_BRANCH` | Git 分支 | master |
| `INSTALL_DIR` | 脚本安装目录 | $HOME/fluffos-builder |

## 📖 详细说明

### 工作流程

1. **下载脚本** - 从 GitHub 下载最新的编译脚本
2. **检测系统** - 识别 Linux 发行版类型
3. **安装依赖** - 自动安装编译所需的工具和库
4. **拉取代码** - 从 GitHub/Gitee 克隆 FluffOS 源代码
5. **编译项目** - 使用 CMake 和 Make 编译
6. **安装驱动** - 可选安装到 /usr/local/bin

### 目录结构

```
$HOME/fluffos-builder/     # 脚本目录（默认）
├── build.sh               # 主编译脚本
└── fluffos/               # FluffOS 源代码
    ├── src/
    ├── build/
    │   └── bin/
    │       └── driver     # 编译后的驱动程序
    └── ...
```

### 安装位置

- **脚本**: `$HOME/fluffos-builder/build.sh`
- **源代码**: `$HOME/fluffos-builder/fluffos/`
- **驱动程序** (如果选择全局安装): `/usr/local/bin/driver`

## 🔧 常见问题

### 1. 一键安装命令无法运行？

**原因**: 可能缺少 curl 或 wget

**解决**:
```bash
# Ubuntu/Debian
sudo apt install curl

# CentOS/RHEL
sudo yum install curl
```

### 2. GitHub 访问慢或失败？

**解决**: 使用 Gitee 镜像

```bash
GIT_REPO="https://gitee.com/mirrors/fluffos.git" \
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y
```

### 3. CMake 版本过低？

**解决**: 脚本会提示如何升级 CMake，或者：

```bash
# 从源代码安装最新 CMake
wget https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1.tar.gz
tar -zxvf cmake-3.28.1.tar.gz
cd cmake-3.28.1
./bootstrap && make -j$(nproc) && sudo make install
```

### 4. 需要检查依赖是否安装？

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/build.sh -o build.sh
chmod +x build.sh

# 检查依赖
./build.sh --check
```

### 5. 只想更新已有项目？

```bash
cd $HOME/fluffos-builder
sudo ./build.sh
# 提示使用现有项目时选择 y
```

## 🌟 高级用法

### 自动化部署脚本

创建 `deploy.sh`:

```bash
#!/bin/bash
# 自动部署最新版 FluffOS

# 下载并运行安装脚本
bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) \
  -y \
  --release \
  --skip-deps

# 重启服务（示例）
# systemctl restart fluffos
```

### Cron 定时更新

```bash
# 每天凌晨 2 点自动更新
0 2 * * * cd $HOME/fluffos-builder && sudo ./build.sh -y >> /var/log/fluffos-update.log 2>&1
```

### Docker 构建

```dockerfile
FROM ubuntu:22.04

RUN apt update && apt install -y curl sudo

# 一键安装 FluffOS
RUN bash <(curl -fsSL https://raw.githubusercontent.com/serenez/fluffos-builder/main/install.sh) -y --release

CMD ["/usr/local/bin/driver"]
```


## 📄 许可证

MIT License

## 🔗 相关链接

- [FluffOS 官方仓库](https://github.com/fluffos/fluffos)
- [MUDREN 论坛](https://https://bbs.mud.ren)

## 📞 支持

如果遇到问题：

1. 查看 [常见问题](#常见问题)
2. 运行 `./build.sh --check` 检查依赖
3. 查看日志 `/tmp/fluffos-install.log`
4. [提交 Issue](https://github.com/serenez/fluffos-builder/issues)
5. 联系作者：279631638
---

**一条命令，轻松编译 FluffOS！** 🚀
