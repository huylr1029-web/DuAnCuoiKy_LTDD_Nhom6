import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/nickname_service.dart';
import '../services/realtime_service.dart';
import '../widgets/avatar.dart';
import '../theme.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final AppUser peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chat = ChatService();
  final _input = TextEditingController();
  late final String _chatId = ChatService.chatIdOf(_chat.myUid, widget.peer.uid);
  bool _hasText = false;

  List<MessageItem> _messages = [];
  Map<int, List<({String userId, String emoji})>> _reactions = {};
  final _recorder = AudioRecorder();
  final _voicePlayer = AudioPlayer();
  bool _recording = false;
  int? _playingVoiceId;
  bool _peerTyping = false;
  DateTime? _lastTypingSent;
  bool _loading = true;
  Object? _error;
  bool _peerOnline = false;
  String? _nickname;

  String get _displayName => _nickname ?? widget.peer.name;
  Timer? _pollTimer;
  StreamSubscription<MessageItem>? _messageSub;
  int _loadVersion = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      if (has) {
        final now = DateTime.now();
        if (_lastTypingSent == null || now.difference(_lastTypingSent!).inSeconds >= 2) {
          _lastTypingSent = now;
          _chat.sendTyping(widget.peer.uid);
        }
      }
    });
    _peerOnline = widget.peer.online;
    _loadMessages();
    _loadNickname();
    // Vao nhom chat de nhan tin moi qua SignalR, dong thoi poll 3 giay
    // de chac chan khong sot tin neu SignalR mat ket noi.
    _messageSub = RealtimeService().messageStream.listen((msg) {
      if (msg.chatId == _chatId && mounted) {
        _loadMessages(silent: true);
      }
    });
    // joinChat se ket noi SignalR neu chua co connection.
    unawaited(RealtimeService().joinChat(_chatId));
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      unawaited(_loadMessages(silent: true));
      unawaited(_refreshPeer());
      unawaited(_refreshTyping());
      if (!RealtimeService().isConnected) {
        unawaited(RealtimeService().joinChat(_chatId));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageSub?.cancel();
    RealtimeService().leaveChat(_chatId);
    _input.dispose();
    _recorder.dispose();
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _refreshTyping() async {
    try {
      final typing = await _chat.isPeerTyping(widget.peer.uid);
      if (mounted && typing != _peerTyping) setState(() => _peerTyping = typing);
    } catch (_) {}
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final requestVersion = ++_loadVersion;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final messages = await _chat.messages(widget.peer.uid);
      // Du lieu cu khong duoc ghi de du lieu moi khi nhieu request
      // REST (polling + SignalR + gui tin) hoan thanh khac thu tu.
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() {
        _messages = messages;
        _error = null;
        _loading = false;
      });
      unawaited(_chat.markRead(widget.peer.uid));
      try {
        final reactions = await _chat.reactions(widget.peer.uid);
        if (mounted && requestVersion == _loadVersion) {
          setState(() => _reactions = reactions);
        }
      } catch (e) {
        debugPrint('Load reactions: $e');
      }
    } catch (error) {
      if (!mounted || requestVersion != _loadVersion) return;
      debugPrint('Load messages failed: $error');
      setState(() {
        // Mat mang tam thoi thi giu tin nhan da hien thi.
        if (_messages.isEmpty) _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadNickname() async {
    try {
      final map = await NicknameService().load();
      if (mounted) setState(() => _nickname = map[widget.peer.uid]);
    } catch (_) {}
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Biệt danh cho ${widget.peer.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Biệt danh',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (_nickname != null)
            TextButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                child: const Text('Xóa biệt danh')),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'clear') {
        await NicknameService().remove(widget.peer.uid);
        if (mounted) setState(() => _nickname = null);
      } else {
        final nickname = controller.text.trim();
        if (nickname.isEmpty) return;
        await NicknameService().set(widget.peer.uid, nickname);
        if (mounted) setState(() => _nickname = nickname);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _refreshPeer() async {
    try {
      final peer = await _chat.userById(widget.peer.uid);
      if (peer != null && mounted && peer.online != _peerOnline) {
        setState(() => _peerOnline = peer.online);
      }
    } catch (e) {
      debugPrint('Refresh peer: $e');
    }
  }

  Future<void> _send([String? override]) async {
    if (_sending) return;
    final text = (override ?? _input.text).trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _chat.sendMessage(widget.peer, text);
      // Chi xoa noi dung khi backend xac nhan da gui thanh cong.
      if (override == null && _input.text.trim() == text) {
        _input.clear();
      }
      await _loadMessages(silent: true);
    } catch (e) {
      debugPrint('Send message failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không gửi được tin nhắn: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'image.jpg' : picked.name;
      final contentType = name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      await _chat.sendImageMessage(widget.peer, name, bytes, contentType);
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không gửi được hình ảnh: $e')));
      }
    }
  }

  Future<void> _sendLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần cấp quyền vị trí để gửi vị trí.')));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await _chat.sendLocationMessage(widget.peer, position.latitude, position.longitude);
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không lấy được vị trí: $e')));
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      try {
        final path = await _recorder.stop();
        if (mounted) setState(() => _recording = false);
        if (path == null) return;
        final file = await _readVoiceFile(path);
        if (file == null) return;
        await _chat.sendVoiceMessage(widget.peer, 'voice.m4a', file, 'audio/m4a');
        await _loadMessages(silent: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không gửi được tin nhắn thoại: $e')));
        }
      }
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần cấp quyền micro để ghi âm.')));
        }
        return;
      }
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, bitRate: 128000),
          path: '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không ghi âm được: $e')));
      }
    }
  }

  Future<List<int>?> _readVoiceFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleVoicePlay(MessageItem m) async {
    try {
      if (_playingVoiceId == m.id) {
        await _voicePlayer.stop();
        if (mounted) setState(() => _playingVoiceId = null);
        return;
      }
      await _voicePlayer.setUrl(m.text);
      await _voicePlayer.play();
      if (mounted) setState(() => _playingVoiceId = m.id);
      _voicePlayer.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed).then((_) {
        if (mounted && _playingVoiceId == m.id) setState(() => _playingVoiceId = null);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không phát được tin nhắn thoại: $e')));
      }
    }
  }

  Future<void> _openMap(String text) async {
    final parts = text.split(',');
    if (parts.length < 2) return;
    final uri = Uri.parse('https://maps.google.com/?q=${parts[0].trim()},${parts[1].trim()}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không mở được bản đồ: $e')));
      }
    }
  }

  Future<void> _pickReaction(MessageItem m) async {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '🔥'];
    final myEmoji = _reactions[m.id]?.where((r) => r.userId == _chat.myUid).map((r) => r.emoji).firstOrNull;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ...emojis.map((e) => GestureDetector(
                onTap: () => Navigator.pop(context, e),
                child: Text(e, style: const TextStyle(fontSize: 32)),
              )),
              if (myEmoji != null)
                TextButton(onPressed: () => Navigator.pop(context, 'clear'), child: const Text('Gỡ')),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'clear') {
        await _chat.removeReaction(m.id);
      } else {
        await _chat.setReaction(m.id, action);
      }
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _reactionChips(MessageItem m) {
    final list = _reactions[m.id] ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    final grouped = <String, int>{};
    for (final r in list) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: grouped.entries.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
          child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 12)),
        )).toList(),
      ),
    );
  }

  Future<void> _call(bool isVideo) async {
    try {
      final callId =
      await CallService().startCall(peer: widget.peer, isVideo: isVideo);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
              callId: callId, peer: widget.peer, isVideo: isVideo, isCaller: true),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không gọi được: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(name: _displayName, radius: 18, online: _peerOnline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(_peerTyping ? 'Đang nhập...' : (_peerOnline ? 'Đang hoạt động' : 'Không hoạt động'),
                  style: TextStyle(fontSize: 12, color: _peerTyping ? AppColors.primary : Colors.grey)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
              tooltip: 'Đổi biệt danh',
              onPressed: _editNickname),
          IconButton(
              icon: const Icon(Icons.call, color: AppColors.primary),
              tooltip: 'Gọi thoại',
              onPressed: () => _call(false)),
          IconButton(
              icon: const Icon(Icons.videocam, color: AppColors.primary),
              tooltip: 'Gọi video',
              onPressed: () => _call(true)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Lỗi: $_error'))
                : _messages.isEmpty
                ? EmptyState(
              icon: Icons.waving_hand_rounded,
              title: _displayName,
              subtitle: 'Hãy gửi lời chào 👋 để bắt đầu trò chuyện.',
            )
                : ListView.builder(
              reverse: true, // tin moi nhat o duoi cung
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _buildMessage(_messages[i]),
            ),
          ),
          if (_recording)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Đang ghi âm... bấm nút mic lại để gửi', style: TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessage(MessageItem m) {
    final isMe = m.senderId == _chat.myUid;
    final timeText = DateFormat('HH:mm').format(m.createdAt);

    // Tin nhan lich su cuoc goi
    if (m.type == 'call') {
      final missed = m.text.contains('nhỡ') || m.text.contains('từ chối');
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _call(m.isVideo), // bam de goi lai
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.bubbleOther,
                borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: missed ? Colors.red : Colors.grey.shade400,
                child: Icon(m.isVideo ? Icons.videocam : Icons.call,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('Bấm để gọi lại',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ]),
          ),
        ),
      );
    }

    final text = m.text;
    final onlyEmoji = text == '👍';
    Widget content;
    if (m.type == 'voice') {
      final playing = _playingVoiceId == m.id;
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.bubbleOther, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(playing ? Icons.stop : Icons.play_arrow, color: isMe ? Colors.white : Colors.black87),
            onPressed: () => _toggleVoicePlay(m),
          ),
          Text('Tin nhắn thoại', style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
        ]),
      );
    } else if (m.type == 'image') {
      content = GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(child: Image.network(text, errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined))),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(text, width: 220, fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined)),
        ),
      );
    } else if (m.type == 'location') {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.bubbleOther, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.location_on, color: isMe ? Colors.white : Colors.red),
            const SizedBox(width: 6),
            Expanded(child: Text('Vị trí: $text', style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _openMap(text),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
            child: Text('Mở bản đồ', style: TextStyle(color: isMe ? Colors.white : AppColors.primary)),
          ),
        ]),
      );
    } else {
      content = Container(
        padding: onlyEmoji ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: onlyEmoji
            ? null
            : BoxDecoration(color: isMe ? AppColors.primary : AppColors.bubbleOther, borderRadius: BorderRadius.circular(18)),
        child: Text(text, style: TextStyle(fontSize: onlyEmoji ? 40 : 15, color: isMe ? Colors.white : Colors.black87)),
      );
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Tooltip(
        message: timeText,
        child: GestureDetector(
          onLongPress: () => _pickReaction(m),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                content,
                _reactionChips(m),
                if (isMe && _messages.isNotEmpty && m.id == _messages.first.id && m.type != 'call')
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 4),
                    child: Text(m.isRead ? 'Đã xem' : 'Đã gửi', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4))]),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.image_outlined, color: Colors.grey), tooltip: 'Gửi hình ảnh', onPressed: _sendImage),
          IconButton(icon: const Icon(Icons.location_on_outlined, color: Colors.grey), tooltip: 'Gửi vị trí', onPressed: _sendLocation),
          IconButton(
            icon: Icon(_recording ? Icons.mic : Icons.mic_outlined, color: _recording ? Colors.red : Colors.grey),
            tooltip: _recording ? 'Bấm lại để gửi tin nhắn thoại' : 'Ghi âm tin nhắn thoại',
            onPressed: _toggleRecording,
          ),
          Expanded(
            child: TextField(
              controller: _input,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Nhắn tin',
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          // Giong Messenger: o trong -> nut 👍, co chu -> nut gui
          IconButton(
            icon: Icon(_hasText ? Icons.send : Icons.thumb_up, color: AppColors.primary),
            onPressed: _sending ? null : () => _hasText ? _send() : _send('👍'),
          ),
        ]),
      ),
    );
  }
}
