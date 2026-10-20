# LocalChat 验收记录

日期：2026-10-20。基线：LocalSend v1.18.2 / `af0416be50770a97760f7070684bc667b759a15c`。
Flutter 3.41.9 / Dart 3.11.5 / Rust 1.97.1 / FRB 2.12.0 / sqlite3 3.5.2。
这是一份发布前本机开发验收记录，不代表五平台发布完成。
远程 CI 状态以对应提交的 GitHub Actions 为准，不能由本机测试结果推断。

## 平台矩阵

| 平台 | 构建 | native SQLite | 发现 / 手动地址 | 双向文字 | 大文件同时聊天 | 双方重启 | 原版互传 / 安装共存 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Windows x64，本机 | 最终 debug 通过 | 真实应用与 native smoke 均通过 | 真实 UDP 核心测试通过；含端口/scoped IPv6 的手动地址解析测试通过，原生输入 UI 未验证 | 两真实进程通过 | 128 MiB 上传期间双向文字通过 | 历史去重、文件卡片保留及离线重连补发通过 | 发布版 LocalSend 互传、安装器共存未验证 |
| Linux / Ubuntu 24.04 | CI 已配置；本机验收时未执行 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| macOS | CI 已配置；本机验收时未执行 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| Android | FOSS arm64 debug CI 已配置；本机验收时未执行 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| iOS | 无签名 debug CI 已配置；本机验收时未执行 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |

Windows 运行探针使用两个独立便携配置和临时测试身份，程序化预授权后测试真实应用
outbox、HTTP 控制器、文件保存和 SQLite。文件上传由持有测试身份的探针发起；不是
点击 UI 的端到端发送测试。两进程位于同一主机，不等同于两台实体设备或五平台互通。

## 已取得证据

- 自动化应用测试：最终 **127 项通过**，包含真实数据库事务、迁移、邀请许可、
  去重、有限重试、附件映射、旧端不携带扩展、聊天不清空普通待发列表、关闭进度页后的迟到结果。
- 桥接测试：24 项通过，1 项 macOS 专用测试在 Windows 跳过；Rust responder 及过期决定
  测试通过。绑定重新生成，旧 LocalSend v2 测试与新证书绑定测试纳入完整核心测试。
- Windows 实际应用：双向文字、重复 ACK 不重复入库、两端终止后重启保留历史；
  128 MiB 文件传输尚未结束时双向文字已送达，接收文件长度和 SHA-256 一致，文件卡片重启后保留。
- HTTP 53317 占用时回退至实际空闲端口；UDP 仍使用 53317。桌面第二实例安全转交、
  异常退出释放锁、重启后重新发布端口均有实际进程验证。
- 分别覆盖 scoped IPv6 地址显示、同 IP 换证书不能继承权限、数据库写锁错误无成功 ACK、
  身份重置保留历史并撤销许可、部分拒绝/失败/取消及重复回调。模拟错误不冒充物理磁盘满。
- 最终离线恢复：确认对端在线后终止对端真实进程，16 秒内仅保留一次失败尝试；
  对端重启、实际端口重新发现后，原消息在第二次尝试送达一次。不是丢弃旧消息后新建重发。

详细日志保存在验收机器的仓库外工具目录，未纳入源码仓库。日志文件名：
`task7-done.log`、`task7-core-green.log`、`task7-isolates-tests.log`、
`final-app-analyze.log`、`final-app-tests.log`、`final-isolates-tests.log`、
`task8-core-tests.log`、`task8-windows-smoke.log`、`final-windows-build.log`、
`final-localchat-runtime.log`、`final-offline-runtime.log`。
`app/tool/localchat_runtime_probe.dart`、`localchat_file_runtime_probe.dart`、
`localchat_offline_runtime_probe.dart` 是可复用探针。
测试进程在脚本 finally 中关闭；测试身份不可打进发行包。

最后一个离线探针最初放在包外，无法解析 SQLite native assets，尚未进入队列检查即失败。
移到 `app/tool/`、从 `app/` 执行后通过；没有为探针修改产品 SQLite 加载方式。

## 尚需实机验收

1. 在保留局域网的条件下断开外网，确认五平台发现、手动地址、双向消息和文件传输；
   当前未修改用户网络、VPN 或防火墙。
2. Android/iOS 前后台、局域网权限拒绝后恢复、Wi-Fi 切换、真实 IPv6 scope、
   手机睡眠后的重新发现与补发。移动端保证范围是应用打开期间。
3. 与正式发布的 LocalSend 双向传文件，以及独立安装、卸载、自启动、分享扩展和系统权限。
   兼容协议测试不能替代发布版程序实测。
4. 原生界面截图、邀请接受流程和聊天文件接受/取消的人工交互。Computer Use 获取窗口
   时等待应用授权超时，未声称完成视觉验收；已有窄屏/宽屏、粘贴与导航 widget 测试。
5. Apple 签名/App Group/组播 entitlement、Windows 安装器及发布签名。CI 只产测试构建。

## 最终验证

应用和 isolates 静态分析均无问题；应用 127 项通过；isolates 24 项通过、1 项 macOS
专用测试在本机跳过。Rust core 150 项通过，默认跳过 1 项要求真实 LAN 组播的用例；
该组播用例在任务 2 已显式执行通过。core clippy 和 bridge/CLI 检查通过，clippy 仍有
上游样式警告。Windows 原生 SQLite 集成 smoke 1 项通过；最终普通应用重新构建通过。

一次独立整分支审查报告六项 Important，无 Critical、无单列 Minor。六项均已修复：
手动端口、异常时间戳渲染、发现状态过期与失联重试、Linux glibc 声明、附件新消息重发、
拒绝邀请后的名额回收。对应回归测试先失败再通过，最终完整套件为绿色；没有用第二次
评审代替测试。未执行的平台和原生交互项目维持上面的“未验证”标记。

本机开发预览包：`build/preview/LocalChat-Windows-x64-dev-2026-10-20.zip`。
解压后运行 `Start-LocalChat.cmd`，也可打开同目录 `localchat.exe`。这是 Debug 构建，
不是已签名安装包；其他 Windows 电脑的运行库兼容性未验证。包内 `localchat-data` 为空，
不含测试身份或历史，首次启动自行生成身份。
公开下载见[本项目 Releases](https://github.com/Jaron-admin/localchat/releases)；
远程构建结果见[GitHub Actions](https://github.com/Jaron-admin/localchat/actions/workflows/localchat-ci.yml)。
