# LocalChat 构建与验证记录

LocalChat 从官方 LocalSend v1.18.2（`af0416be50770a97760f7070684bc667b759a15c`）派生。
保留 Apache-2.0 许可、原作者版权和内部 Dart/Rust 包名。用户项目：
<https://github.com/Jaron-admin/localchat>。

## 固定工具链

- Flutter 3.41.9 / Dart 3.11.5，遵循根目录 `.fvmrc`。
- Rust 1.97.1，遵循根目录 `rust-toolchain.toml`。
- flutter_rust_bridge_codegen 2.12.0。
- Windows 需要 Visual Studio C++ Build Tools 和 Windows SDK。
- Android 需要 Android SDK / NDK；iOS 与 macOS 的构建、签名需要 macOS/Xcode。

使用 `fvm flutter` / `fvm dart`。本机安装隔离在 `D:/同人/.localchat-tools`，
没有替换原有 Flutter，也没有修改全局 PATH。因 GitHub 连接失败，FVM 从本机已有的
官方 Flutter Git 仓库克隆了同一版本标签，校验 revision 为
`00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`。部分 Windows 引擎下载在官方源超时后，
使用 Flutter 文档列出的 CFUG 镜像 `https://storage.flutter-io.cn` 完成；设置仅作用于构建进程。

```sh
fvm install
fvm use 3.41.9
cd app
fvm flutter pub get
fvm dart run build_runner build
fvm dart run slang
fvm flutter analyze
fvm flutter test
```

在当前 Windows 中文路径环境，build_runner 的 AOT 启动器写入失败，使用其自带选项
`fvm dart run build_runner build --force-jit` 已成功。FRB 自动 build_runner 已关闭，
因此在 `packages/localsend_isolates` 执行 `flutter_rust_bridge_codegen generate` 后，
需显式执行上述 build_runner 命令。无需更换 Dart 或依赖版本。

Rust core 检查必须启用功能：

```sh
cd packages/core
cargo test --features full
cargo clippy --features full
```

## 独立身份

| 项目 | 值 |
| --- | --- |
| 显示名称 | LocalChat |
| Android / Apple / Linux 标识 | io.github.jaronadmin.localchat |
| Apple 分享扩展 | io.github.jaronadmin.localchat.ShareExtension |
| Apple App Group | group.io.github.jaronadmin.localchat |
| Windows MSIX | JaronAdmin.LocalChat |
| Windows Inno AppId | d635a531-59f6-4645-bd41-7b546c60ad8f |
| 便携数据 | 可执行文件旁 localchat-data/ |

独立安装不得导入或修改 LocalSend 的旧配置、证书、自启动项或卸载记录。
Apple 签名团队和 App Group 授权、Windows 发布证书必须配置为维护者自己的身份。

## 验证状态

2026-10-19：固定 Flutter / Dart 与 Rust / Cargo 版本核验成功。Flutter 引擎下载通过
仅监听本机的临时转接器获取同一 Google 官方文件并核对对象 MD5；Rust 编译器下载
使用镜像，但完整 SHA-256 与已获取的官方清单一致。未关闭 TLS 或校验。

| 验证 | 状态 |
| --- | --- |
| 上游 Flutter lib 静态分析 / test 基线 | 通过；原有 71 项测试通过 |
| Rust core 全功能测试 | 78 项单元测试、58 项集成测试通过；修正上游测试对 Windows 时间精度的假设 |
| 数据隔离、便携路径与损坏配置 | 5 项回归测试通过；原版设置/证书哨兵不变，损坏配置不静默重建身份 |
| 修改后的 Flutter 全套测试 / 静态分析 | 74 项通过；静态分析无问题 |
| Windows 安装共存与卸载 | 安装标识已隔离，未做安装器实测 |
| Windows debug 构建与启动 | 通过；localchat.exe 在隔离便携目录实际启动，真实 HTTPS info 请求通过客户端证书及精确服务端证书校验 |
| Android / iOS / macOS / Linux 构建 | 未验证 |
| 五个平台实体设备互传 | 未验证 |
| 共存端口与发现 | 4 项测试通过，含真实 UDP 53317 公告回退 HTTP 端口 |
| 桌面单实例与安全唤起 | 3 项跨进程锁测试、5 项 TLS 唤起测试通过；完整 Windows 应用二次启动及异常退出后重启通过 |
| 任务 2 应用回归 | 静态分析无问题；77 项测试通过 |

后续仅在命令或实测成功后更新对应状态。CI 编译成功不代表锁屏接收或实体设备互传已验证。

## SQLite 依赖调整

任务 4 实际解析发现：计划中的 sqlite3 3.7.1 → hooks 2.2 → record_use 1.0
要求 meta ≥1.19，而固定 Flutter 3.41.9 锁定 meta 1.17。因此采用兼容的精确
sqlite3 **3.5.2**，不覆盖 Flutter 的依赖约束、不升级全局 SDK。实际解析只新增
sqlite3 与 native_toolchain_c 两项；保留 hooks 2.0.2。该版本使用 native asset
build hooks，五个平台按目标架构打包，不额外添加 sqlite3_flutter_libs。

Windows 首次 hook 下载发生 Dart TLS 握手失败；改用系统 curl 从同一官方 release
下载，SHA-256 核对包内清单后放入 hook 下载缓存，hook 会再次校验。没有改包源码、
跳过校验或手动注入运行时库。Windows x64 SHA-256：
`2bf39f2aadafdc59a90b260f582a8fccebc5b89eb94175fdbaa9148c1e1f084d`。

sqlite3 3.5.2 默认 Linux 预编译库要求 glibc ≥2.38；Linux 验证应使用 Ubuntu 24.04
等兼容环境，不能宣称兼容 Ubuntu 22.04。旧发行版需要后续单独配置源码编译。
Debian 元数据已声明 `libc6 >= 2.38`；Linux GUI 打包宿主和 AppImage 软件源统一为
Ubuntu 24.04 / noble，ARM64 软件源使用 ubuntu-ports。配置一致不等同于 Linux 实机通过。
依据：[3.5.2 清单](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.5.2/sqlite3/pubspec.yaml)、
[官方变更记录](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.7.1/sqlite3/CHANGELOG.md)。

Windows 构建修正了 vendored Cargokit 的两处兼容问题：生成 pubspec 使用 UTF-8，支持
中文项目路径；已安装 Rust 检测接受固定数字版本并移除 CRLF。C++ 源码显式使用 `/utf-8`，
避免中文 Windows 代码页导致插件编译失败。其独立回归测试使用
`fvm dart run test/rustup_test.dart`（在 `cargokit/build_tool` 内执行），已通过。

普通 Windows 开发构建无需 MSIX helper；它会生成 `localchat.exe`。打包 helper 时使用
`support/scripts/compile_windows_msix_helper.ps1`，签名证书必须与 MSIX manifest 和
`app/windows/localchat.exe.manifest` 的 Publisher 一致。`CN=JaronAdmin` 是配置值，
并不代表该证书已存在。EXE 安装器脚本要求显式传入本项目的已签名 helper。
完整 MSIX / Store 脚本暂不可用，须先配置维护者自己的发布产品与证书。

Windows 普通模式数据在 `%APPDATA%/LocalChat`；其他系统在应用自己的 support 目录下
的 `LocalChat` 子目录。桌面传 `--portable` 或在程序旁建立 `localchat-data` 文件夹即可
使用便携模式。此目录包含新设置与新身份，不从原版 `settings.json` 导入。

运行端口写入独立数据目录的 `instance.json`。HTTP 首选端口占用时自动使用空闲端口，
UDP 发现端口保持 53317；不把临时端口写回用户的首选设置。关闭 HTTPS 时，已经运行的
窗口仍可使用原文件功能，但第二进程不能安全转交文件参数，会提示在现有窗口开启加密。

## 最终测试入口

新增 `.github/workflows/localchat-ci.yml` 只针对 localchat 分支及相应 PR，
固定上述工具链。Windows/Linux/macOS 构建 debug，Android 构建 FOSS arm64 debug，
iOS 使用 `--no-codesign`。不使用上游发布签名或发行凭据。
本机验收记录不包含远程 CI 结果；请查看对应提交的 GitHub Actions 状态。

```sh
cargo build --locked -p rust_lib_localsend_app
cd app
fvm flutter analyze --no-pub
fvm flutter test --no-pub
fvm flutter test integration_test/localchat_smoke_test.dart -d windows --no-pub
fvm flutter build windows --debug --no-pub
```

native bridge 测试从根目录 `target/debug` 加载库，因此不要为这条命令更改
`CARGO_TARGET_DIR` 或额外加 `--target`。在 `app/` 与 `packages/localsend_isolates/`
各自运行 Flutter 测试，避免相对 fixture 路径错误。Linux 原生 smoke 用
`xvfb-run -a` 和 `-d linux`；macOS 用 `-d macos`。原生集成测试会替换构建产物
入口，打包前必须重新执行普通 `flutter build`，不可将测试宿主作为应用发出。

2026-10-20 Windows native SQLite smoke 已通过：真实宿主加载打包库，提交、
重复投递、关闭重开和有限重试状态恢复。最终应用 127 项测试通过；具体功能与未验证范围
以 [验收记录](localchat-acceptance.md) 为准。没有 Android SDK 和 Apple/Linux 宿主，
没有接受 SDK 许可、改系统网络或代填签名账号来绕过这些条件。

本地产物位于 `build/preview/LocalChat-Windows-x64-dev-2026-10-20.zip`，不包含测试数据；
公开下载见[本项目 Releases](https://github.com/Jaron-admin/localchat/releases)。
运行探针必须位于 `app/tool/` 并从 `app/` 执行，才能使用项目 native asset hooks；仅给
包外脚本传 `--packages` 不足以提供 SQLite 的 native assets 映射。
