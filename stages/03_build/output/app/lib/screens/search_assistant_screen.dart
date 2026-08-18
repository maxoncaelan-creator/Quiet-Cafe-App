// Real chat, proxied through the `search-assistant` Edge Function (see
// supabase/functions/search-assistant) — no Anthropic key in this file or
// anywhere in this app. Empty state (illustration + prompt) shows before
// the first message; once a conversation starts, it's a normal thread.

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const _ChatMessage({required this.role, required this.content});
}

class SearchAssistantScreen extends StatefulWidget {
  const SearchAssistantScreen({super.key});

  @override
  State<SearchAssistantScreen> createState() => _SearchAssistantScreenState();
}

class _SearchAssistantScreenState extends State<SearchAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _supabaseService = SupabaseService();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    if (!SupabaseService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search Assistant needs a configured backend to work.')),
      );
      return;
    }

    final history = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final reply = await _supabaseService.askSearchAssistant(text, history);
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage(role: 'assistant', content: reply)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(const _ChatMessage(
            role: 'assistant',
            content: "Sorry, I couldn't reach the search assistant just now. Try again in a moment.",
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Assistant')),
      drawer: const AppDrawer(currentRoute: AppRoute.searchAssistant),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty ? const _EmptyState() : _MessageList(
                messages: _messages,
                sending: _sending,
                scrollController: _scrollController,
              ),
            ),
            _Composer(controller: _controller, sending: _sending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.local_cafe_outlined, color: scheme.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'Ready to start searching for quiet eating spots?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<_ChatMessage> messages;
  final bool sending;
  final ScrollController scrollController;

  const _MessageList({required this.messages, required this.sending, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: messages.length + (sending ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        if (index >= messages.length) return const _TypingIndicator();
        final message = messages[index];
        return message.role == 'user' ? _UserBubble(text: message.content) : _AssistantMessage(text: message.content);
      },
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  final String text;
  const _AssistantMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primary,
          child: Icon(Icons.auto_awesome, size: 14, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primary,
          child: Icon(Icons.auto_awesome, size: 14, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.sending, required this.onSend});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechAvailable = false;
  bool _initAttempted = false;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  // Not called from initState — speech_to_text's initialize() triggers the
  // OS microphone-permission prompt immediately, which showed up on this
  // screen's very first load (before any user interaction) when tested on
  // a real device. Deferred to the first tap of the mic button instead.
  Future<void> _initSpeech() async {
    if (_initAttempted) return;
    _initAttempted = true;
    final available = await _speech.initialize(onStatus: (status) {
      if ((status == 'done' || status == 'notListening') && mounted) {
        setState(() => _listening = false);
      }
    });
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_initAttempted) await _initSpeech();
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Speech recognition isn't available on this device.")),
        );
      }
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        widget.controller.text = result.recognizedWords;
        widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: !widget.sending,
                  decoration: const InputDecoration(
                    hintText: 'Ask about quiet restaurants…',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
              IconButton(
                icon: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: _listening ? scheme.primary : scheme.onSurfaceVariant,
                ),
                onPressed: widget.sending ? null : _toggleListening,
              ),
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward),
                onPressed: widget.sending ? null : widget.onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
