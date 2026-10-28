// lib/components/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/typewriter_text.dart';
import '../widgets/particle_bg.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, String>> _buildHistory() {
    return _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 2000) {
      setState(() => _error = 'Message too long.');
      return;
    }

    final historySnapshot = _buildHistory();
    setState(() {
      _messages.add(_Msg(role: 'user', text: text));
      _sending = true;
      _error = null;
    });
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());

    try {
      final uri = Uri.parse('$apiBase/chat');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': text, 'history': historySnapshot}),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = (data['reply'] ?? '').toString();
        final rawSources = data['sources'] as List<dynamic>? ?? [];
        final sources = rawSources
            .map(
              (s) => {
                'label': s['label'].toString(),
                'url': s['url'].toString(),
              },
            )
            .toList();
        if (mounted) {
          setState(() {
            _messages.add(
              _Msg(
                role: 'assistant',
                text: reply,
                animate: true,
                sources: sources,
              ),
            );
            _sending = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Server error ${res.statusCode}';
            _sending = false;
          });
        }
      }
    } on TimeoutException {
      if (mounted)
        setState(() {
          _error = 'Request timed out.';
          _sending = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Network error: $e';
          _sending = false;
        });
    }
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: Text(
          'Clear conversation?',
          style: GoogleFonts.cookie(color: Colors.white, fontSize: 22),
        ),
        content: Text(
          'This will delete all messages.',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF555555)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _messages.clear();
                _error = null;
              });
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Color(0xFFE07070)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Column(
          children: [
            Text(
              'ASK LUMI',
              style: GoogleFonts.cinzel(
                color: const Color(0xFFD4AF37),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            Text(
              'Ingredient Intel',
              style: GoogleFonts.cinzel(
                color: const Color(0xFF555555),
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Color(0xFF444444),
                size: 20,
              ),
              onPressed: _clearChat,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFD4AF37).withOpacity(0.1),
          ),
        ),
      ),
      body: ParticleBg(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyChat(onPrompt: (p) => _send(p))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (_sending && i == _messages.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111111),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF222222),
                                ),
                              ),
                              child: _TypingDots(),
                            ),
                          );
                        }

                        final m = _messages[i];
                        final isUser = m.role == 'user';

                        // Parse follow-up suggestion if present
                        String mainText = m.text;
                        String? followUpDisplay;
                        String? followUpSend;
                        if (!isUser && m.text.contains('|||')) {
                          final parts = m.text.split('|||');
                          mainText = parts[0].trim();
                          final rawFollowUp = parts[1].trim();
                          if (rawFollowUp.contains('^^^')) {
                            final fparts = rawFollowUp.split('^^^');
                            followUpDisplay = fparts[0].trim();
                            followUpSend = fparts[1].trim();
                          } else {
                            followUpDisplay = rawFollowUp;
                            followUpSend = rawFollowUp;
                          }
                        }

                        Widget content;
                        if (!isUser && m.animate && !m.done) {
                          content = TypewriterText(
                            text: mainText,
                            speed: const Duration(milliseconds: 10),
                            style: GoogleFonts.cinzel(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
                              height: 1.6,
                            ),
                            onTick: () {
                              if (_scroll.hasClients &&
                                  _scroll.position.maxScrollExtent -
                                          _scroll.position.pixels <
                                      100) {
                                _scrollToEnd();
                              }
                            },
                            onDone: () {
                              if (mounted) setState(() => m.done = true);
                            },
                          );
                        } else {
                          content = _MarkdownText(
                            text: mainText,
                            isUser: isUser,
                          );
                        }

                        return Column(
                          crossAxisAlignment: isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? const Color(0xFFD4AF37)
                                      : const Color(0xFF111111),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: isUser
                                        ? const Radius.circular(16)
                                        : const Radius.circular(4),
                                    bottomRight: isUser
                                        ? const Radius.circular(4)
                                        : const Radius.circular(16),
                                  ),
                                  border: isUser
                                      ? null
                                      : Border.all(
                                          color: const Color(0xFF222222),
                                        ),
                                  boxShadow: isUser
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFD4AF37,
                                            ).withOpacity(0.2),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: content,
                              ),
                            ),

                            // Source chips
                            if (!isUser && m.done && m.sources.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 4,
                                  top: 2,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: m.sources
                                      .map(
                                        (s) => GestureDetector(
                                          onTap: () async {
                                            final uri = Uri.parse(s['url']!);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(
                                                uri,
                                                mode: LaunchMode
                                                    .externalApplication,
                                              );
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF111111),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFFD4AF37,
                                                ).withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.open_in_new,
                                                  size: 10,
                                                  color: Color(0xFFD4AF37),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  s['label']!,
                                                  style: GoogleFonts.cinzel(
                                                    color: const Color(
                                                      0xFFD4AF37,
                                                    ),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),

                            // Follow-up suggestion chip
                            if (!isUser && m.done && followUpDisplay != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 6,
                                ),
                                child: GestureDetector(
                                  onTap: () => _send(followUpSend),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF9B59D4,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF9B59D4,
                                        ).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.auto_awesome,
                                          size: 13,
                                          color: Color(0xFF9B59D4),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            followUpDisplay!,
                                            style: GoogleFonts.cinzel(
                                              color: Color(0xFF9B59D4),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Color(0xFFE07070),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFE07070),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFFE07070),
                      ),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),

            // Composer
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF080808),
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFD4AF37).withOpacity(0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF222222)),
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask Lumi anything…',
                            hintStyle: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sending ? null : _send,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _sending
                              ? const Color(0xFF222222)
                              : const Color(0xFFD4AF37),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _sending
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFD4AF37,
                                    ).withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: _sending
                            ? const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF555555),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.arrow_upward_rounded,
                                color: Color(0xFF080808),
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Typing dots ───────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = ((_ctrl.value * 3 - i) % 3) / 3;
            final opacity = (offset < 0.5 ? offset * 2 : (1 - offset) * 2)
                .clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withOpacity(opacity),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  final void Function(String) onPrompt;
  const _EmptyChat({required this.onPrompt});

  static const _suggestions = [
    'Is niacinamide safe for sensitive skin?',
    'What does hyaluronic acid do?',
    'Are parabens harmful?',
    'How do I build a morning routine?',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFD4AF37).withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD4AF37).withOpacity(0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFFD4AF37),
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Ask Lumi',
              style: GoogleFonts.cookie(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ingredient questions, routine advice, product safety.',
              style: GoogleFonts.cinzel(
                color: Colors.white.withOpacity(0.3),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ..._suggestions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => onPrompt(s),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E1E1E)),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.cinzel(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Msg {
  final String role;
  final String text;
  final bool animate;
  final List<Map<String, String>> sources;
  bool done;
  _Msg({
    required this.role,
    required this.text,
    this.animate = false,
    this.done = false,
    this.sources = const [],
  });
}

// ── Markdown text renderer ────────────────────────────────────────────────────
class _MarkdownText extends StatelessWidget {
  final String text;
  final bool isUser;
  const _MarkdownText({required this.text, required this.isUser});

  List<InlineSpan> _parse(String input, TextStyle base) {
    final spans = <InlineSpan>[];
    // Handle **bold**, *italic*, bullet points
    final lines = input.split('\n');
    for (int li = 0; li < lines.length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      String line = lines[li];
      // Bullet points
      if (line.startsWith('- ') || line.startsWith('* ')) {
        line = '• ${line.substring(2)}';
      }
      // Numbered list
      final numMatch = RegExp(r'^\d+\. ').firstMatch(line);
      if (numMatch != null) {
        line =
            '${numMatch.group(0)!.replaceFirst(RegExp(r'\d+'), '  ${numMatch.group(0)!.trim().replaceAll('.', '')}')}'
            '${line.substring(numMatch.end)}';
      }
      // Parse bold/italic inline
      spans.addAll(_parseInline(line, base));
    }
    return spans;
  }

  List<InlineSpan> _parseInline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: base.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0xFF1E1E1E),
              color: const Color(0xFFD4AF37),
            ),
          ),
        );
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.cinzel(
      fontSize: 15,
      color: isUser ? const Color(0xFF080808) : Colors.white.withOpacity(0.8),
      height: 1.7,
    );
    return SelectableText.rich(TextSpan(children: _parse(text, base)));
  }
}
