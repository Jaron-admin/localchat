# LocalChat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在官方 LocalSend fork 上实现五个平台可用的纯局域网一对一文字聊天与会话内文件传输。

**Architecture:** 复用 LocalSend 的发现、TLS 和文件引擎，增加独立聊天路由及持久化会话。网络使用既有 Rust → FRB → Dart isolate → Flutter 事件链；专用数据库 isolate 提交事务后才允许发送消息确认。聊天不占用文件接收槽。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5、Rust 1.97.1、flutter_rust_bridge 2.12.0、Refena、dart_mappable、SQLite（sqlite3 3.7.1）。

**Spec:** [LocalChat 首版设计](../specs/2026-10-19-localchat-design.md)

## Global Constraints

- Windows、macOS、Linux、Android、iOS 同等纳入产品范围。
- 纯局域网优先；接受手机打开应用时可靠通信，不要求锁屏后持续收消息。
- 自己的多台设备和不同人的设备，两种场景同样重要。
- 首版一对一聊天及文件传输，群聊后续加入。
- 自动发现在线设备，并直接显示 IP 地址。
- 设备身份采用已验证的证书指纹，IP 只是当前地址。聊天不退回明文。
- 正文限制为 32 KiB UTF-8；首次聊天接受一次，聊天许可与文件自动接收独立。
- 接收方提交数据库事务后才确认送达；“已送达”不代表已读。
- 每周期最多自动重试 3 次：首次投递 + 3 次重试，共最多 4 次网络尝试。重试间隔 1、2、4 秒；手动重试开启新周期但复用 messageId。
- 保留 Apache-2.0、版权与适用归属；不自动迁移或修改原版 LocalSend 的证书和数据。
- 使用 FVM 固定 Flutter；Rust core 始终带 `--features full`。生成代码通过工具更新，Dart 格式宽度 150。

## Review Focus

- 原版与 LocalChat 同时运行：HTTP 回退端口必须正确公告，UDP 发现端口不能随之改变；任务 2 验证。
- ACK 丢失后进程重启：同一消息只能出现一次，不能误报已送达或无限重置重试预算；任务 4、5 验证。
- 同 IP 被另一身份接替，或许可撤销与消息同时到达：不继承信任、不向错误身份发送正文；任务 3、4、5 验证。
- 中文、表情、时钟倒退和相同时间戳：按 UTF-8 字节限制正文，按本地序列分页，不丢历史；任务 3、4、6 验证。
- 部分文件被拒绝、保存失败、取消及旧客户端：卡片准确反映各文件结果，不破坏兼容传输；任务 7、8 验证。

---

## 执行顺序与现有环境

工作目录为 `D:/同人/localchat`，开发分支为 `localchat`，基线为 `af0416be50770a97760f7070684bc667b759a15c`。`origin` 指向用户 fork，`upstream` 指向官方；不重置远程 main，不向官方发 PR。当前仅文档未提交，执行前重新检查工作树。

任务依赖为 `1 → 2/3/4 → 5 → 6 → 7 → 8`。任务 2、3、5 都涉及桥接和服务文件，实际修改按任务顺序合并，避免同时改同一接口。任务 3 的协议测试通过并不代表聊天已可用于真实用户；任务 5 接上持久化后才形成端到端消息能力。

已发现 `D:/flutter` 指向 `D:/开发/flutter`，其缓存版本为 Flutter 3.47.5 / Dart 3.13.4；保留该环境。Visual Studio 2022 BuildTools 的 C++ 工具组件已检测到，Rust 和 Android SDK 的可用安装尚未确认。执行时在 `D:/同人/.localchat-tools` 下准备独立 FVM、Flutter 3.41.9 和 Rust 1.97.1，并用进程环境变量隔离缓存，不改变用户全局工具版本。工具目录不入库。

以下命令默认在各任务指定目录执行；FVM 必须解析到上述固定版本。需要安装或下载时仅使用官方来源；不接受 Android SDK 许可、不更改系统防火墙或签名账号来绕过缺失环境。环境不足如实记录，不把其他平台列为通过。

文档和每个通过验证的任务分别提交。若 Git 作者未配置，保留文件并报告未提交，不猜测用户邮箱、不改全局身份。远程写权限不足时保留本地分支和提交，不修改 GitHub 应用权限。

## Task 1: 独立安装与构建基线

**Files:**
- Create: `app/lib/config/app_identity.dart`、`app/lib/util/native/app_data_directory.dart`、`support/docs/localchat-build.md`。
- Modify: `app/lib/provider/persistence_provider.dart`、`app/lib/config/init.dart`、`app/lib/util/native/{autostart_helper,context_menu_helper,cache_helper,tray_helper}.dart`。
- Modify: `app/android/app/build.gradle`、`app/android/app/src/main/AndroidManifest.xml`；`app/ios/Runner.xcodeproj/project.pbxproj`、`app/ios/Runner/Info.plist`、`app/ios/Runner/Runner.entitlements`、`app/ios/ShareExtension/{Info.plist,ShareExtension.entitlements}`。
- Modify: `app/macos/Runner/Configs/AppInfo.xcconfig`、`app/macos/Runner.xcodeproj/project.pbxproj`、`app/macos/Runner/{Info.plist,DebugProfile.entitlements,Release.entitlements}`、`app/macos/ShareExtension/{Info.plist,ShareExtension.entitlements}`。
- Modify: `app/windows/CMakeLists.txt`、`app/windows/runner/{main.cpp,Runner.rc}`、`app/linux/{CMakeLists.txt,my_application.cc}`；`support/scripts/compile_windows_exe-inno.iss`、`support/build/msix/content/AppxManifest.xml` 和引用对应产物名的现有打包脚本。
- Test: `app/test/unit/util/native/app_data_directory_test.dart`；安装共存实测记录写入 build 文档。

**Interfaces:** `AppIdentity` 常量：displayName=`LocalChat`、applicationId=`io.github.jaronadmin.localchat`、Apple share extension 后缀=`.ShareExtension`、app group=`group.io.github.jaronadmin.localchat`、Windows MSIX identity=`JaronAdmin.LocalChat`、Inno AppId=`d635a531-59f6-4645-bd41-7b546c60ad8f`。`Future<Directory> resolveLocalChatDataDirectory({required bool portable})` 返回 LocalChat 独立数据目录；portable 使用可执行文件旁 `localchat-data/`。保留内部 Dart 包名与 Rust crate 名，避免无关导入重命名。

- [ ] **Step 1:** 在固定工具链上先跑 `app/: fvm flutter pub get; fvm flutter analyze; fvm flutter test` 与 `packages/core/: cargo test --features full`，记录基线失败。检查原有修改，安装工具与本任务一起完成。
- [ ] **Step 2:** 为路径隔离写行为测试，在临时目录放原版 settings/certificate 哨兵；调用新路径及初始化后断言 `expect(localchatPath, isNot(originalPath)); expect(originalBytesAfter, originalBytesBefore)`。运行 `fvm flutter test test/unit/util/native/app_data_directory_test.dart`，先确认缺少新入口导致失败。
- [ ] **Step 3:** 实现独立目录与平台标识，生成新证书，不读取原版旧配置迁移路径。更改应用显示名称及安装产物为 LocalChat；同步原生包 ID、分享扩展和 app group。删除安装器中卸载 `LocalSend.App` 的逻辑；自启动/右键菜单只使用 LocalChat 注册项。版权保留，官网入口改为用户 fork；首版禁用沿用原版产品 ID 的购买入口，保留 FOSS 标记。
- [ ] **Step 4:** 重跑路径测试、analyze 和 Windows debug 构建；在隔离测试配置下验证安装/卸载目标，不对用户现有 LocalSend 执行卸载。成功标准是独立数据路径、独立程序标识与可启动构建，不能仅检查字符串。
- [ ] **Step 5:** 提交已核验文件，消息 `feat: isolate LocalChat app identity and storage`；build 文档记录工具版本、构建结果及未验证平台。

## Task 2: 共存端口、发现与桌面单实例

**Files:**
- Modify: `packages/localsend_isolates/rust/src/api/{server,discovery}.rs`、`packages/localsend_isolates/lib/src/task/{server/http_server,discovery/discovery}.dart`、`packages/localsend_isolates/lib/src/isolate/child/server_isolate.dart`。
- Modify: `app/lib/provider/network/server/server_provider.dart`、`app/lib/config/init.dart`、`packages/localsend_isolates/lib/util/show_instance.dart`。
- Create: `app/lib/util/native/localchat_instance.dart`。
- Test: `packages/core/tests/localchat_coexistence.rs`、`packages/localsend_isolates/test/util/show_instance_test.dart`、`app/test/unit/util/native/localchat_instance_test.dart`。

**Interfaces:** `RsHttpServer::port(&self) -> u16`；`HttpServerStartedEvent({required int port})`；Rust `start_discovery` 将原 `port` 拆成 `multicast_port: u16` 与 `http_port: u16`。Dart `DiscoveryConfig.port=53317`，公告的 `device.port=actualHttpPort`。`LocalChatInstance.acquire(Directory dataDirectory) -> Future<LocalChatInstance>` 持有桌面文件锁；`publishEndpoint({required int port})` 写入本机运行端口，`close()` 释放锁。

- [ ] **Step 1:** 写测试：预先占用 TCP 53317 后启动 LocalChat，断言 `actualPort != 53317`、公告端口等于 actualPort、发现仍加入 UDP 53317。单实例测试使用两个子进程和临时数据目录，断言第二实例只请求唤起第一实例、锁释放后可重启。错误证书服务器断言 `receivedArgs.isEmpty`。
- [ ] **Step 2:** 运行 `packages/core/: cargo test --features full --test localchat_coexistence` 与上述 Dart 测试；确认新参数/事件尚未实现的失败。
- [ ] **Step 3:** 默认先监听 53317，只对 AddressInUse 回退到端口 0，取系统实际端口并经 Started 事件同步状态，然后再公告。在 Rust 层判断 I/O ErrorKind，不能解析错误文本或吞掉其他绑定错误。发现固定 UDP 53317，HTTP 端口独立传递；绑定过程暂停公告，实际地址同步后恢复。桌面锁放在独立数据目录，锁持有者原子写实际端口；第二实例最多等待 2 秒端口记录，超时报告启动未就绪，不另开实例。使用自身证书指纹验证本机服务后才传启动参数，不能让原 `badCertificateCallback=true` 接收任意服务并暴露参数；手机无需此桌面锁。
- [ ] **Step 4:** 重新生成 FRB，跑测试与 Rust `cargo check --package rust_lib_localsend_app`。同机原版和 LocalChat 同时运行，验证互相发现、双向文件传输、LocalChat 二次启动只唤起自身；退出后锁自动释放。IPv6 scope 不丢失。
- [ ] **Step 5:** 提交 `feat: support LocalChat discovery alongside LocalSend`。

## Task 3: 独立聊天协议与安全请求处理

**Files:**
- Create: `packages/core/src/http/chat_dto.rs`、`packages/core/src/http/server/chat.rs`、`support/docs/localchat-protocol-v1.md`。
- Modify: `packages/core/src/http/mod.rs`、`packages/core/src/http/server/{mod,v2}.rs`、`packages/core/src/http/client/{mod,v2}.rs`。
- Test: `packages/core/tests/localchat_server.rs`、`packages/core/tests/localchat_tls.rs`、`packages/core/tests/event_backpressure.rs`。

**Interfaces:** 新增 DTO 均 camelCase JSON：`ChatCapabilities {version:u32, features:Vec<String>, max_text_bytes:u32}`；`ChatInvite {version:u32, invitation_id:String}`；`ChatInviteStatus {invitation_id:String,status:Pending|Accepted|Rejected}`；`ChatMessageDto {version:u32,message_id:String,sent_at_ms:i64,text:String}`；`ChatAck {message_id:String,duplicate:bool}`。UUID v4 用于 invitationId/messageId；证书身份不从这些 DTO 获取。

`ServerEventV2::ChatRequest {request_id:String,ip:PeerIp,peer_fingerprint:String,operation:ChatOperation,response_tx:oneshot::Sender<ChatReply>}`。`ChatOperation=Invite(ChatInvite)|InviteStatus(String)|Deliver(ChatMessageDto)`；`ChatReply=Invitation(ChatInviteStatus)|Stored(ChatAck)|Rejected(ChatErrorCode)`。错误码包括 denied/conflict/unavailable/overloaded。Core 的 `LsHttpClientV2` 与外层 `LsHttpClient` 增加 `chat_capabilities(ip:&str,port:u16)`、`chat_invite(ip:&str,port:u16,payload:ChatInvite)`、`chat_invite_status(ip:&str,port:u16,invitation_id:&str)`、`chat_deliver(ip:&str,port:u16,payload:ChatMessageDto)`，各返回 `Result<对应DTO,ClientError>`。V3 backend 明确返回不支持，不影响文件接口。

- [ ] **Step 1:** 写协议测试，断言无客户端证书/HTTP 不能发聊天；开启浏览器传文件模式也不例外。正文 `"中".repeat(10923)` 为 32769 字节应 413，32768 字节应可提交；空白正文/非法 ID 为 400。测试能力接口 200、未知版本拒绝、文件占用槽时仍产生 ChatRequest、队列满明确报错。
- [ ] **Step 2:** 跑 `cargo test --features full --test localchat_server --test localchat_tls`，确认路由不存在或类型缺失导致失败。
- [ ] **Step 3:** 增加 `GET capabilities`、`POST invitations`、`GET invitations/{id}`、`POST messages` 路由。能力版本=1，features=`text,file-ref`，正文 UTF-8 上限 32768，原始 JSON 上限 262144 字节，保留原始正文不 trim 后存储。全局最多 64 个在途聊天请求，每指纹最多 8 个，等待业务响应上限 5 秒；满返回 429，存储不可用 503，等待超时 504。邀请持久化 pending 后 202，状态查询/已决邀请 200；首次消息提交 201，重复提交 200，内容冲突 409，未获许可 403。HTTP 超时/断开释放在途资源；不能占用 v2.session，也不能使事件循环等待用户点击。
- [ ] **Step 4:** 客户端记录是否配置 expected_fingerprint，新聊天方法在未绑定证书时直接返回错误，并强制 HTTPS；不能用 discovery client 传聊天正文。确认 TLS 拒绝发生在发正文前。跑新增测试、`cargo test --features full --test v2_server --test v2_tls_pinning --test event_backpressure` 和 `cargo clippy --features full --all-targets`。此阶段业务 responder 使用测试实现，不声称已具备持久化 ACK。
- [ ] **Step 5:** 将准确请求/响应例子及错误写入协议文档，提交 `feat: add certificate-bound LocalChat protocol`。

## Task 4: SQLite 会话、许可与可靠队列

**Files:**
- Create: `app/lib/model/chat/{chat_peer,chat_conversation,chat_message,chat_attachment,chat_result,chat_invitation}.dart`。
- Create: `app/lib/repository/chat/{chat_repository,sqlite_chat_repository,chat_database_worker,chat_schema}.dart`、`app/lib/provider/chat/chat_repository_provider.dart`。
- Modify: `app/pubspec.yaml`、`pubspec.lock`、`app/lib/config/init.dart`。
- Test: `app/test/unit/repository/chat/sqlite_chat_repository_test.dart`。

**Interfaces:** `ChatRepository.open(String databasePath,{required String localFingerprint}) -> Future<ChatRepository>`；`upsertPeer(ChatPeer)` 只更新显示/地址；`setOwnDevice(String fingerprint,bool value)`；`beginInvitation(String fingerprint,String invitationId)`、`recordInvitation(String verifiedFingerprint,String invitationId)`、`decideInvitation(String fingerprint,String invitationId,bool accept)`、`completeOutgoingInvitation(String verifiedFingerprint,String invitationId,bool accepted)`、`readInvitation(String verifiedFingerprint,String invitationId)`、`revokePermission(String fingerprint,{required bool block})`；除 read 返回 `Future<ChatInvitation>`，以上修改返回 `Future<void>`。

`ensureConversation(String peerFingerprint) -> Future<ChatConversation>`；`listConversations() -> Future<List<ChatConversation>>`；`listMessages(String conversationId,{int? beforeSequence,int limit=50}) -> Future<List<ChatMessage>>`；`enqueueText({required String peerFingerprint,required String messageId,required String text,required int sentAtMs}) -> Future<ChatMessage>`；`commitIncoming({required String verifiedFingerprint,required String messageId,required String text,required int sentAtMs,required int receivedAtMs}) -> Future<IncomingCommit>`。`IncomingCommit {MessageKey key,bool duplicate}` 仅在 COMMIT 成功后返回；`MessageKey {String senderFingerprint,String messageId}`。

队列接口：`loadDueOutbox(DateTime now,{String? peerFingerprint}) -> Future<List<ChatMessage>>`、`tryStartAttempt(MessageKey key,DateTime now) -> Future<bool>`、`recordDelivery(MessageKey key,{required String verifiedPeerFingerprint}) -> Future<void>`、`recordAttemptFailure(MessageKey key,DeliveryFailure failure) -> Future<void>`、`scheduleManualRetry(MessageKey key,DateTime now) -> Future<void>`、`recoverInterruptedAttempts() -> Future<void>`。`DeliveryFailure {bool retryable,String code,DateTime occurredAt}`。`markConversationRead(String id,int throughSequence)`、`close()` 返回 `Future<void>`；`changes` 为事务提交后的 `Stream<ChatChange>`，事件只含受影响会话 ID。

模型固定字段：ChatPeer 包含 fingerprint/alias/platform/host/port/lastSeen/isOwnDevice/localPermission/remotePermission；ChatConversation 包含 id/peerFingerprint/lastActivity/unreadCount；ChatMessage 包含 key/conversationId/peerFingerprint/localSequence/kind/direction/text/sentAtMs/receivedAtMs/deliveryState/attemptCount/nextAttemptAt；ChatInvitation 包含 invitationId/peerFingerprint/direction/status。Permission 为 unknown/pending/allowed/denied/blocked，DeliveryState 为 queued/sending/delivered/unconfirmed/failed/rejected，MessageKind 为 text/attachment。ChatAttachment 包含 attachmentId/messageKey/sessionId/fileId/name/size/localPath/state；AttachmentState 为 offered/waiting/transferring/complete/rejected/cancelled/failed。

- [ ] **Step 1:** 用真实临时 SQLite 文件写测试：重复 ID 只一行、相同 ID 不同正文拒绝、事务失败无正文/摘要残留、磁盘错误不返回 receipt、撤销许可与写入串行、同指纹换 IP 保留会话、同 IP 换指纹不继承许可、重开恢复队列、设备时钟倒退仍能完整分页。本机证书重置后旧待发不得自动用新身份发送。断言 `rows.length==1`、`duplicate==true`、`afterReopen.messageId==before.messageId`。
- [ ] **Step 2:** `app/: fvm flutter test test/unit/repository/chat` 先确认失败。加精确 `sqlite3: 3.7.1` 与 `flutter_test: sdk:flutter` 后实际解析 workspace；不升级不相关依赖、不加 sqlite3_flutter_libs。
- [ ] **Step 3:** 专用 Dart isolate 持唯一连接，路径为任务 1 目录下 `chat.sqlite3`。使用外键、WAL、synchronous=FULL 和 BEGIN IMMEDIATE。四张核心表按 spec，另加 invitations 保存邀请 ID/方向/状态；messages 加 localSequence、attemptCount、nextAttemptAt、lastError；分页按 localSequence，唯一键 `(senderFingerprint,messageId)`。正文及原始发送时间共同检查冲突。DB 命令队列最多 256，待发文字最多 1000，未决邀请最多 64，容量判断与插入同事务；数据库损坏不删除文件。
- [ ] **Step 4:** 将本机接收许可与远端许可分别保存。本地发起表示愿意接收该指纹回复；远端 accepted 只能完成确由本机发起的同 ID 邀请，不能凭空授权。接收方接受/拒绝本地事务落库；查询只对原发起身份可见，拒绝/屏蔽不能被重试改回 pending。sending 遗留记录恢复未确认，保留已用预算；预算耗尽仅手动重开周期。metadata 记录本机指纹，发现本机证书改变时保留历史、撤销旧许可，旧身份未完成待发标记 identity_changed，不自动重新署名。挂载 repository 在桌面单实例判断后、启动网络前。重跑测试和 analyze，确认所有错误均无假 ACK。
- [ ] **Step 5:** 提交 `feat: persist LocalChat conversations and delivery state`。

## Task 5: 桥接、聊天控制器与投递调度

**Files:**
- Modify: `packages/localsend_isolates/rust/src/api/{server,http,model}.rs`、`packages/localsend_isolates/lib/src/isolate/{child/server_isolate,parent/actions}.dart`、`packages/localsend_isolates/lib/src/task/server/http_server.dart`。
- Create: `app/lib/provider/network/server/controller/chat_controller.dart`、`app/lib/provider/chat/{chat_transport,chat_capabilities_provider,chat_outbox_provider}.dart`。
- Modify: `app/lib/provider/network/server/server_provider.dart`、`app/lib/provider/http_provider.dart`、`app/lib/provider/network/nearby_devices_provider.dart`、`app/lib/{main,config/init,config/refena}.dart`。
- Test: `packages/localsend_isolates/test/task/server/chat_response_test.dart`、`app/test/unit/provider/chat/{chat_controller,chat_outbox_provider,chat_capabilities_provider}_test.dart`。

**Interfaces:** `RsHttpServer::respond_chat_request(&self,request_id:String,reply:ChatReply)->anyhow::Result<()>` 使用独立有界 responder map，四个 chat client 方法透传任务 3 DTO。Dart 新增 `HttpServerChatRequestEvent`、`HttpServerChatResponseTask`、`IsolateHttpServerChatResponseAction`，字段沿用 requestId/reply。`ChatController.onRequest(HttpServerChatRequestEvent event)->Future<void>` 消费任务 4 repository。`ChatTransport` 暴露 `capabilities(Device)`、`invite(Device,String invitationId)`、`inviteStatus(Device,String invitationId)`、`deliver(Device,ChatMessage)`，返回对应 Future DTO；实现使用 `httpProvider.pinnedTo(fingerprint)`。`ChatOutboxService.wake({String? peerFingerprint})`、`setForeground(bool)`、`retry(MessageKey)`、`dispose()` 管理调度。

- [ ] **Step 1:** 测试先保存后发请求、COMMIT 前不回复、存储失败回复 503、邀请未决不阻塞其他事件、未知 requestId 迟到回应不误配。fake clock 测试首次 + 3 次重试恰好 4 次且 ID 一致，重启不刷新预算，ACK ID 或目标指纹错误不标 delivered；手机暂停不调度、恢复先校验地址和身份。只将明确 404/不支持判为旧客户端，TLS/网络失败不能缓存成“只支持文件”。
- [ ] **Step 2:** 跑上述 isolates/app 测试，确认缺少接口或行为导致失败。
- [ ] **Step 3:** 实现事件转发与 responder map，断开、超时、停服清理。server isolate 只转发，不能 await 用户决策或 DB 事务挡住事件循环。ChatController 持久化后返回响应；前台当前会话的未决邀请以 2/5/15/30 秒退避查询，离开或暂停即停止，重新打开继续。接收状态只影响本地实际发起的邀请；重复邀请不重复提醒。
- [ ] **Step 4:** 实现有界 outbox 每设备串行、全局最多 4 个投递，文件传输不共享该锁。丢 ACK 按固定 ID 重试；403/409 停止自动重试，429/503/网络超时计入预算。resumed 先恢复服务、重新发现并校验证书，再唤醒队列；detached 有限时间关闭 DB 和调度，意外退出依赖事务恢复。调试观察器不输出正文或全量历史。生成 FRB 2.12.0 绑定与两个 Dart package 的 mapper，再跑测试、analyze、Rust plugin check。
- [ ] **Step 5:** 用两个本地独立测试配置实际发文字并重开检查持久化，记录结果，提交 `feat: connect durable chat delivery to the app`。

## Task 6: 会话界面、附近设备与权限操作

**Files:**
- Create: `app/lib/provider/chat/chat_provider.dart`、`app/lib/pages/tabs/{chat_tab,nearby_tab}.dart`、`app/lib/pages/chat/{chat_page,chat_page_vm}.dart`。
- Create: `app/lib/widget/chat/{chat_message_bubble,chat_composer,peer_address_header}.dart`、`app/lib/widget/dialogs/chat_invitation_dialog.dart`。
- Modify: `app/lib/pages/{home_page,home_page_controller,device_details_page}.dart`、`app/lib/widget/list_tile/device_list_tile.dart`、`app/lib/widget/watcher/shortcut_watcher.dart`、`app/lib/{main,config/init}.dart`、`app/lib/provider/network/send_provider.dart`、`app/lib/provider/network/server/controller/receive_controller.dart`、`app/lib/pages/tabs/receive_tab.dart`、`app/assets/i18n/{en,zh-CN}.json`。
- Test: `app/test/widget/chat/{chat_page,nearby_tab,chat_navigation}_test.dart`。

**Interfaces:** `ChatPage({required String conversationId})`；`ChatComposer({required bool enabled,required Future<void> Function(String) onSend})`；`PeerAddressHeader({required ChatPeer peer})`；`ChatViewService.openPeer(String fingerprint)`、`sendText(String conversationId,String text)`、`setOwnDevice(String fingerprint,bool value)`、`revoke(String fingerprint,{required bool block})`。HomeTab 为 chat/nearby/settings；原 send/receive 的分享、快捷键和返回入口统一映射 nearby 下的传输功能。

- [ ] **Step 1:** Widget 测试断言 IP:port 可见、离线历史仍在、已送达不显示已读、旧客户端没有聊天输入框、首次接受/拒绝绑定正确设备、手机 push 与宽屏双栏均可用。测试外部分享进入附近发送，接收文件不把当前聊天强行切走；中文多行输入和超字节上限有明确反馈。
- [ ] **Step 2:** 跑 `fvm flutter test test/widget/chat`，确认新页面未实现导致失败。
- [ ] **Step 3:** 复用现有自适应导航与文件选择器，新增会话列表、按 localSequence 分页的气泡、未读提示及 composer。列表/会话头部常显地址与平台，本机多地址可展开，scope/IPv6 由统一格式化处理。“我的设备”只是本机分类。首次邀请显示可核对指纹；撤销/屏蔽不删除历史。关闭 HTTPS 时聊天输入不可用并提示开启加密，原文件行为保持兼容。实现精确状态文案和 32 KiB 校验，数据库持久化失败不能把输入当作成功发送。
- [ ] **Step 4:** 枚举并修改所有 `HomeTab.receive/send` 引用，保留旧文件流程和分享入口；运行 slang/build_runner、analyze、widget 测试。Windows 上实际检查窄屏、宽屏、键盘输入及粘贴，不用纯截图替代网络验证。
- [ ] **Step 5:** 提交 `feat: add conversations and nearby-device chat UI`。

## Task 7: 会话附件与兼容文件传输

**Files:**
- Modify: `packages/core/src/http/{dto,dto_v2}.rs`、`packages/core/src/http/server/v2.rs`、`packages/localsend_isolates/rust/src/api/{model,server}.rs`、`packages/localsend_isolates/lib/src/isolate/child/server_isolate.dart`。
- Modify: `app/lib/provider/network/send_provider.dart`、`app/lib/provider/network/server/controller/receive_controller.dart`、`app/lib/model/state/{send/send_session_state,server/receive_session_state}.dart`、任务 4 repository/model 文件。
- Create: `app/lib/model/chat/chat_transfer_context.dart`、`app/lib/widget/chat/chat_attachment_card.dart`。
- Test: `packages/core/tests/localchat_transfer_compat.rs`、`app/test/unit/provider/chat/chat_attachment_mapping_test.dart`、`app/test/widget/chat/chat_attachment_card_test.dart`。

**Interfaces:** `ChatTransferRef {message_id:String,transfer_id:String,attachments:HashMap<wireFileId,stableAttachmentId>}` 放在 prepare-upload 顶层可选 `localchat` 字段，None 不序列化。`startSession` 新增可选 `ChatTransferContext? chatContext`，保留旧调用；context 保存 conversationId/messageId/transferId。repository 增加 `recordFileOffer({required String peerFingerprint,required ChatTransferContext context,required List<ChatAttachment> files,required bool incoming})->Future<void>`、`applyAttachmentResult(AttachmentResult result)->Future<void>`；结果包含真实 session/file ID 和状态，必须匹配记录归属。

- [ ] **Step 1:** 测试无扩展 DTO 往返兼容、向旧端绝不带扩展、恶意跨指纹/跨会话引用被拒绝、映射的 fileId 必须存在、重复 transferId 不重复建卡片。断言部分拒绝、取消、保存失败各文件状态准确；只收到文字 ACK 不会把附件标完成。
- [ ] **Step 2:** 跑 `cargo test --features full --test localchat_transfer_compat` 与 Dart 附件测试，确认新字段/映射未实现导致失败。
- [ ] **Step 3:** 仅已协商 file-ref 且获许可的 LocalChat 互传加扩展；本机提前持久化 stableAttachmentId ↔ wireFileId ↔ sessionId，远端响应后补 remoteSessionId。接收端按真实证书校验关联，建立 kind=attachment 记录；沿用既有接受/拒绝及路径安全检查。新的手动重发文件创建新消息，不声称支持新增断点续传。
- [ ] **Step 4:** 从真实上传结果更新卡片，处理 PrepareUploadAborted、取消、部分接受和磁盘失败；聊天附件不自动 push 全屏传输页，旧端仍保留原界面。节流进度刷新，不持久化每个字节事件。重新生成绑定/mapper，跑兼容测试和既有 v2/file_saver 测试，并实测大文件传输期间双向聊天。
- [ ] **Step 5:** 提交 `feat: attach file transfers to LocalChat conversations`。

## Task 8: 五平台构建与发布前验收

**Files:**
- Create: `.github/workflows/localchat-ci.yml`、`app/integration_test/localchat_smoke_test.dart`、`support/docs/localchat-acceptance.md`。
- Modify: `app/pubspec.yaml`（integration_test SDK 依赖）、`pubspec.lock`、`support/docs/localchat-build.md`、`README.md`。

**Interfaces:** CI 面向 localchat 分支/对应 PR，固定 Flutter/Rust 版本；Windows/Linux/macOS 构建，Android debug APK，iOS `--no-codesign` 构建。只产测试构建，不使用上游签名配置或发布凭据。smoke test 打开真实 native SQLite、提交、关闭重开，再验证消息去重与恢复；两设备网络互通用独立运行配置/实机执行。

- [ ] **Step 1:** 从 spec 九条验收建立矩阵：平台、版本、构建、数据库、发现/手动地址、双向文字、大文件同时聊天、离线恢复、原版互传、共存、结果和日志。每个平台均需一行；未执行填“未验证”，不填通过。
- [ ] **Step 2:** 跑固定工具链检查：app 和 localsend_isolates 分别 `fvm flutter analyze` / `fvm flutter test`；core `cargo test --features full` / `cargo clippy --features full --all-targets`；workspace `cargo check --package rust_lib_localsend_app --package localsend-cli`。格式检查仅覆盖修改的非生成 Dart 文件；不无关重排现有 generated/mocks 文件。
- [ ] **Step 3:** 各自宿主上运行 `fvm flutter build windows --debug`、`build linux --debug`、`build macos --debug`、`build apk --debug`、`build ios --debug --no-codesign`。同平台运行 `fvm flutter test integration_test/localchat_smoke_test.dart -d <实际设备ID>`。确认 sqlite3 hooks 原生资产被打包；构建依赖下载不等于运行时需要联网。
- [ ] **Step 4:** 断外网但保留局域网，实测五平台互通；上游当前 `webRTCEnabled=false` 保持关闭，不启动公共 signaling/STUN。覆盖 Wi-Fi 切换、IPv6 scope、权限拒绝后恢复、IP 换人、证书重置、磁盘错误、ACK 丢失、重复投递、双方重启、文件取消、移动端前后台。记录每条证据；模拟或单平台结果不替代五平台实测。
- [ ] **Step 5:** 更新 README 说明这是独立 fork、已完成能力及当前限制，保留上游归属。安排独立整分支审查并修复阻塞项；验证通过后提交 `test: verify LocalChat across supported platforms`。未具备签名/设备条件时保留未验证项，不宣布五平台发布完成。

## 生成命令

在 `packages/localsend_isolates/` 使用与锁定 FRB 一致的 `flutter_rust_bridge_codegen` 2.12.0 执行 `flutter_rust_bridge_codegen generate` 和 `fvm dart run build_runner build`；在 `app/` 执行 `fvm dart run build_runner build`、`fvm dart run slang`。先读取生成 diff，避免顺带重排 `app/test/mocks.mocks.dart`。

## 依赖依据

- [sqlite3 3.7.1 pubspec](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.7.1/sqlite3/pubspec.yaml)：SDK 下限 3.10，声明五平台；完整依赖解析仍由任务 4 实测。
- [sqlite3 hooks 文档](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.7.1/sqlite3/doc/hook.md)：v3 打包原生 SQLite 的方式。
- [Flutter 3.41.9 DEPS](https://github.com/flutter/flutter/blob/3.41.9/DEPS) 与[对应 Dart VERSION](https://github.com/dart-lang/sdk/blob/c70f78e7d682c158c15ca0c26c729b3ccb932284/tools/VERSION)：核对固定 SDK 兼容范围。

## 计划审阅状态

设计和本实施计划已于 2026-10-19 获用户认可，执行方式为 A：当前对话主代理按任务顺序实施，末尾独立审查。服务端、桥接和客户端接口交叉较多，顺序实现便于保持一致。执行进度和环境结果见本地执行台账及 `support/docs/localchat-build.md`；未验证平台不标为通过。
