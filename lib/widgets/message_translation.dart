import 'package:flutter/material.dart';

import '../services/translation_service.dart';

typedef TranslateMessage = Future<TranslationResult> Function(
  String text,
  String target,
);

/// Kept separate from the original message so translation never changes chat history.
class MessageTranslation extends StatefulWidget {
  final String text;
  final bool automatic;
  final TranslateMessage? translate;
  const MessageTranslation({
    super.key,
    required this.text,
    this.automatic = false,
    this.translate,
  });

  @override
  State<MessageTranslation> createState() => _MessageTranslationState();
}

class _MessageTranslationState extends State<MessageTranslation> {
  static const _languages = {
    'vi': 'Tiếng Việt',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'fr': 'Français',
    'th': 'ไทย',
  };
  String _target = 'vi';
  TranslationResult? _result;
  String? _error;
  bool _busy = false;
  bool _visible = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.automatic) _schedule();
  }

  @override
  void didUpdateWidget(MessageTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _request++;
      _result = null;
      _busy = false;
      _visible = false;
      _error = null;
      if (widget.automatic) _schedule();
    } else if (!oldWidget.automatic && widget.automatic && _result == null) {
      _schedule();
    }
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _show();
  });

  Future<void> _show() async {
    if (_busy) return;
    if (_result != null) {
      setState(() => _visible = !_visible);
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await (widget.translate ?? TranslationService.instance.translate)(
            widget.text,
            _target,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _visible = true;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(
        () => _error = e is StateError
            ? e.message.toString()
            : 'Không dịch được. Hãy thử lại.',
      );
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _show,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.translate, size: 16),
            label: Text(
              _busy
                  ? 'Đang dịch / tải mô hình...'
                  : _visible
                  ? 'Ẩn bản dịch'
                  : 'Xem bản dịch',
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ngôn ngữ bản dịch',
            enabled: !_busy,
            initialValue: _target,
            onSelected: (language) {
              if (language == _target) return;
              setState(() {
                _target = language;
                _result = null;
                _visible = false;
                _error = null;
              });
              _show();
            },
            itemBuilder: (_) => _languages.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '${_languages[_target]} ▾',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      if (_visible && _result != null)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _result!.sameLanguage
                    ? 'Tin nhắn đã ở ngôn ngữ đã chọn'
                    : 'Bản dịch tự động · ${_result!.source} → ${_result!.target}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              SelectableText(_result!.text),
            ],
          ),
        ),
    ],
  );
}
