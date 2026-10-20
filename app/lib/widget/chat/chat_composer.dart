import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';

class ChatComposer extends StatefulWidget {
  final bool enabled;
  final Future<void> Function(String) onSend;
  final VoidCallback? onAttach;
  const ChatComposer({required this.enabled, required this.onSend, this.onAttach, super.key});
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  bool _saving = false;
  bool _failed = false;
  bool get _tooLarge => utf8.encode(_controller.text).length > 32768;
  bool get _canSend => widget.enabled && !_saving && !_tooLarge && _controller.text.trim().isNotEmpty;
  Future<void> _send() async {
    if (!_canSend) return;
    final draft = _controller.text;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSend(draft);
      if (mounted && _controller.text == draft) _controller.clear();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.onAttach != null)
            IconButton(tooltip: t.chat.attach, onPressed: widget.enabled ? widget.onAttach : null, icon: const Icon(Icons.attach_file)),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
              },
              child: TextField(
                controller: _controller,
                enabled: widget.enabled && !_saving,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() => _failed = false),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: t.chat.placeholder,
                  errorText: _tooLarge
                      ? t.chat.tooLarge
                      : _failed
                      ? t.chat.saveFailed
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(tooltip: t.chat.send, onPressed: _canSend ? _send : null, icon: const Icon(Icons.send)),
        ],
      ),
    ),
  );
}
