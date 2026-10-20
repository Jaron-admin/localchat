import 'package:localsend_app/util/native/localchat_instance.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Mobile does not need a desktop process lock.
final localChatInstanceProvider = Provider<LocalChatInstance?>((ref) => null);
