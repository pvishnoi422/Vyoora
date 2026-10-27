// lib/components/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../widgets/typewriter_text.dart';



class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _sending = false;
  String? _error;
  Timer? _typingDotsTimer;
  int _dots = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _typingDotsTimer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Msg(role: 'user', text: text));
      _sending = true;
      _error = null;
      _dots = 0;
    });
    _controller.clear();
    await Future.delayed(const Duration(milliseconds: 30));
    _scrollToEnd();

    _typingDotsTimer?.cancel();
    _typingDotsTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
      _scrollToEnd();
    });

    try {
      final uri = Uri.parse('$apiBase/chat');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': text}),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = (data['reply'] ?? '').toString();
        setState(() {
          _messages.add(_Msg(role: 'assistant', text: reply, animate: true));
          _sending = false;
        });
      } else {
        setState(() {
          _error = 'Server error: ${res.statusCode} ${res.body}';
          _sending = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _sending = false;
      });
    } finally {
      _typingDotsTimer?.cancel();
      _typingDotsTimer = null;
    }

    await Future.delayed(const Duration(milliseconds: 30));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Vyoora Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (_sending && i == _messages.length) {
                  final dots = '.' * _dots;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('typing$dots',
                          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                    ),
                  );
                }

                final m = _messages[i];
                final isUser = m.role == 'user';
                final bgColor = isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceVariant;

                Widget content;
                if (!isUser && m.animate && !m.done) {
                  content = TypewriterText(
                    text: m.text,
                    speed: const Duration(milliseconds: 12),
                    style: const TextStyle(fontSize: 15),
                    onTick: _scrollToEnd,
                    onDone: () {
                      if (!mounted) return;
                      setState(() => m.done = true);
                      _scrollToEnd();
                    },
                  );
                } else {
                  content = SelectableText(m.text, style: const TextStyle(fontSize: 15));
                }

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),

          _Composer(controller: _controller, onSend: _send, sending: _sending),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Ask anything…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Msg {
  final String role; // 'user' or 'assistant'
  final String text;
  final bool animate;
  bool done;
  _Msg({
    required this.role,
    required this.text,
    this.animate = false,
    this.done = false,
  });
}
