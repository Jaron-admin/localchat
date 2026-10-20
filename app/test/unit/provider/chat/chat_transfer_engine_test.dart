import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../mocks.mocks.dart';
import 'chat_capabilities_provider_test.dart' show CapabilityTransport;

class _Token implements RsCancellationToken {
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  @override
  RsCancellationToken crateApiCancelCreateCancellationToken() => _Token();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements RsHttpClient {
  final requests = <wire.PrepareUploadRequestDto>[];
  Future<void> Function(wire.PrepareUploadRequestDto)? beforeReply;
  @override
  Future<PrepareUploadResult> prepareUpload({
    required wire.ProtocolType protocol,
    required String ip,
    required int port,
    required wire.PrepareUploadRequestDto payload,
    String? publicKey,
    String? pin,
    required RsCancellationToken cancelToken,
  }) async {
    requests.add(payload);
    await beforeReply?.call(payload);
    return const PrepareUploadResult(statusCode: 204);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clients extends HttpClientCollection {
  final _Client client;
  String? pinnedFingerprint;
  _Clients(this.client) : super(privateKey: '', certificate: '', discovery: client);
  @override
  RsHttpClient pinnedTo(String fingerprint) {
    pinnedFingerprint = fingerprint;
    return client;
  }
}

class _SeededSend extends SendNotifier {
  final SendSessionState session;
  _SeededSend(this.session);
  @override
  Map<String, SendSessionState> init() => {session.sessionId: session};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _Api()));
  late Directory dir;
  late ChatRepository repository;
  late RefenaContainer container;
  late _Client client;
  late _Clients clients;
  late CapabilityTransport transport;
  late ChatTransferContext context;
  final owner = 'A' * 64, peer = 'B' * 64;
  final target = Device.empty.copyWith(fingerprint: peer, ip: '127.0.0.1', port: 53317, https: true);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat-send-engine-');
    repository = await ChatRepository.open('${dir.path}/chat.sqlite3', localFingerprint: owner);
    final invitation = const Uuid().v4();
    await repository.recordInvitation(peer, invitation);
    await repository.decideInvitation(peer, invitation, true);
    context = ChatTransferContext(
      conversationId: (await repository.ensureConversation(peer)).id,
      messageId: const Uuid().v4(),
      transferId: const Uuid().v4(),
    );
    final persistence = MockPersistenceService();
    when(persistence.getCreateChecksums()).thenReturn(false);
    when(persistence.isHttps()).thenReturn(true);
    when(persistence.getSendMode()).thenReturn(SendMode.single);
    when(persistence.getCustomColor()).thenReturn(const Color(0xff000000));
    when(persistence.getSecurityContext()).thenReturn(StoredSecurityContext(privateKey: '', publicKey: '', certificate: '', certificateHash: owner));
    client = _Client();
    clients = _Clients(client);
    transport = CapabilityTransport();
    container = RefenaContainer(
      overrides: [
        persistenceProvider.overrideWithValue(persistence),
        deviceFullInfoProvider.overrideWithBuilder((_) => target.copyWith(fingerprint: owner)),
        httpProvider.overrideWithBuilder((_) => clients),
        chatRepositoryProvider.overrideWithValue(repository),
        chatCapabilitiesProvider.overrideWithValue(ChatCapabilitiesService(transport)),
        globalReduxProvider.overrideWithGlobalReducer(reducer: {ClearCacheAction: null}),
      ],
    );
    container.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: 'Unrelated nearby selection'));
  });
  tearDown(() async {
    container.disposeContainer();
    await repository.close();
    await dir.delete(recursive: true);
  });
  test('legacy request has no extension or capability probe, retains normal single-send cleanup', () async {
    await container.notifier(sendProvider).startSession(target: target, files: container.read(selectedSendingFilesProvider), background: true);
    expect(client.requests.single.localchat, isNull);
    expect(transport.calls, 0);
    expect(clients.pinnedFingerprint, peer);
    expect(container.read(selectedSendingFilesProvider), isEmpty);
  });
  test('chat mapping is durable before prepare, rejection ends cards without clearing nearby selection', () async {
    final selection = container.read(selectedSendingFilesProvider);
    client.beforeReply = (payload) async {
      final files = await repository.listAttachments(MessageKey(owner, context.messageId));
      expect(files, hasLength(1));
      expect(payload.localchat!.attachments[files.single.fileId], files.single.attachmentId);
      expect(files.single.state, AttachmentState.offered);
    };
    await container.notifier(sendProvider).startSession(target: target, files: selection, background: true, chatContext: context);
    expect(container.read(selectedSendingFilesProvider), same(selection));
    expect(container.read(sendProvider), isEmpty);
    expect(client.requests.single.localchat!.messageId, context.messageId);
    expect((await repository.listAttachments(MessageKey(owner, context.messageId))).single.state, AttachmentState.rejected);
  });
  test('a legacy peer cannot receive a chat extension or create an attachment message', () async {
    transport.failure = const ChatTransportException('unsupported', retryable: false, status: 404);
    final selection = container.read(selectedSendingFilesProvider);
    await expectLater(
      container.notifier(sendProvider).startSession(target: target, files: selection, background: true, chatContext: context),
      throwsStateError,
    );
    expect(client.requests, isEmpty);
    expect(await repository.listMessages(context.conversationId), isEmpty);
    expect(container.read(selectedSendingFilesProvider), same(selection));
  });
  test('chat retry cannot reuse an old remote session or start another upload', () async {
    const file = SendingFile(
      file: FileDto(id: 'file', fileName: 'failed.bin', size: 4, fileType: FileType.other, hash: null, preview: null, metadata: null),
      token: 'old-token',
      thumbnail: null,
      asset: null,
      path: '/old/failed.bin',
      bytes: null,
      errorMessage: 'network',
    );
    final session = SendSessionState(
      sessionId: 'old',
      remoteSessionId: 'remote-old',
      background: true,
      status: SessionStatus.finishedWithErrors,
      target: target,
      files: {'file': file},
      chatContext: context,
      hashedFileCount: 0,
      startTime: null,
      endTime: null,
      sendingTasks: null,
      errorMessage: null,
    );
    final isolated = RefenaContainer(overrides: [sendProvider.overrideWithNotifier((_) => _SeededSend(session))]);
    try {
      await expectLater(isolated.notifier(sendProvider).sendFile(sessionId: 'old', file: file, isRetry: true), throwsStateError);
      expect(isolated.read(sendProvider)['old'], same(session));
    } finally {
      isolated.disposeContainer();
    }
  });
}
