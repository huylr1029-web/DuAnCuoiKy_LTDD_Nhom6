import '../widgets/message_translation.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/location_service.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/api_models.dart';
import '../services/group_chat_service.dart';
import '../theme.dart';

/// Man hinh chat nhom: giong ChatScreen 1-1 nhung tin nhan co them
/// ten nguoi gui, va khong co goi / biet danh / cam xuc (cam xuc
/// hien tai chi cho tin 1-1 vi bang MessageReaction dung MessageId
/// cua chat 1-1, dung chung se nham tin nhom).
/// Poll 3 giay giong chat 1-1 de chac chan khong sot tin.
class GroupChatScreen extends StatefulWidget {
  final GroupChatItem group;
  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _service = GroupChatService();
  final _input = TextEditingController();
  List<GroupChatMessageItem> _messages = [];
  bool _loading = true;
  Object? _error;
  bool _hasText = false;
  bool _autoTranslate = false;
  Timer? _pollTimer;
  bool _sending = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _load(silent: false);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  bool _fetching = false;

  Future<void> _load({bool silent = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      await _fetch(silent: silent);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _fetch({bool silent = false}) async {
    final version = ++_loadVersion;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final messages = await _service.messages(widget.group.id);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _messages = messages;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(widget.group.id, text);
      if (mounted && _input.text.trim() == text) _input.clear();
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không gửi được tin nhắn: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'image.jpg' : picked.name;
      final contentType = name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      await _service.sendImageMessage(
        widget.group.id,
        name,
        bytes,
        contentType,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không gửi được hình ảnh: $e')));
      }
    }
  }

  Future<void> _sendLocation() async {
    try {
      final position = await LocationService.currentPosition();
      await _service.sendLocationMessage(
        widget.group.id,
        position.latitude,
        position.longitude,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không lấy được vị trí: $e')));
      }
    }
  }

  Future<void> _openMap(String text) async {
    try {
      await LocationService.openMap(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không mở được bản đồ: $e')));
      }
    }
  }

  Widget _buildMessage(GroupChatMessageItem m) {
    final isMe = m.senderId == _service.myUid;
    final timeText = DateFormat('HH:mm').format(m.createdAt);
    Widget content;
    if (m.type == 'image') {
      content = GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: Image.network(
                m.text,
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            m.text,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) =>
                const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    } else if (m.type == 'location') {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.bubbleOther,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: isMe ? Colors.white : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Vị trí: ${m.text}',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => _openMap(m.text),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
              ),
              child: Text(
                'Mở bản đồ',
                style: TextStyle(
                  color: isMe ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.bubbleOther,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            fontSize: 15,
            color: isMe ? Colors.white : Colors.black87,
          ),
        ),
      );
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Tooltip(
        message: timeText,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    m.senderName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              content,
              if (!isMe && m.type == 'text' && m.text.trim().isNotEmpty)
                MessageTranslation(
                  key: ValueKey('group-translate-${m.id}'),
                  text: m.text,
                  automatic: _autoTranslate,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberNames = widget.group.members.map((m) => m.userName).join(', ');
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: _autoTranslate
                ? 'Tắt dịch tự động'
                : 'Tự dịch tin nhắn đến',
            icon: Icon(
              Icons.translate,
              color: _autoTranslate ? Colors.green : Colors.grey,
            ),
            onPressed: () => setState(() => _autoTranslate = !_autoTranslate),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name),
            Text(
              memberNames,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Lỗi: $_error'))
                : _messages.isEmpty
                ? const EmptyState(
                    icon: Icons.group_rounded,
                    title: 'Chưa có tin nhắn trong nhóm',
                    subtitle: 'Gửi tin nhắn đầu tiên cho cả nhóm nhé.',
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessage(_messages[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: Colors.grey),
                    tooltip: 'Gửi hình ảnh',
                    onPressed: _sendImage,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.location_on_outlined,
                      color: Colors.grey,
                    ),
                    tooltip: 'Gửi vị trí',
                    onPressed: _sendLocation,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Nhắn tin cho nhóm',
                        filled: true,
                        fillColor: AppColors.inputFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _hasText ? Icons.send : Icons.thumb_up,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      if (_hasText) {
                        _send();
                      } else {
                        _input.text = '👍';
                        _send();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
