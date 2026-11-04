import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/nickname_service.dart';
import '../services/realtime_service.dart';
import '../widgets/avatar.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'incoming_call_screen.dart';
import 'incoming_group_call_screen.dart';
import 'group_chat_screen.dart';
import '../services/group_call_service.dart';
import '../services/group_chat_service.dart';
import 'calls_tab.dart';
import 'reels_tab.dart';
import 'profile_tab.dart';
import 'friends_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _chat = ChatService();
  final _calls = CallService();
  Timer? _pollTimer;
  StreamSubscription<CallItem>? _incomingSub;
  final _seenIncoming = <String>{};
  final _seenGroupIncoming = <String>{};
  bool _showingIncoming = false;
  int _selectedTab = 0;
  Object? _profileError;

  List<AppUser> _users = [];
  List<ChatItem> _chats = [];
  List<GroupChatItem> _groupChats = [];
  Map<String, String> _nicknames = {};
  bool _showArchived = false;
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncProfile();
    _loadData();
    _checkIncoming();
    // Realtime + polling: SignalR bao ngay khi co cuoc goi den,
    // polling 4 giay dam bao khong sot neu SignalR mat ket noi.
    RealtimeService().connect();
    _incomingSub = RealtimeService().incomingCallStream.listen(_onIncomingCall);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkIncoming();
      _loadData(silent: true);
    });
  }

  Future<void> _syncProfile() async {
    try {
      await AuthService().me();
      if (mounted) setState(() => _profileError = null);
    } catch (error) {
      if (mounted) setState(() => _profileError = error);
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final users = await _chat.otherUsers();
      final chats = await _chat.myChats();
      List<GroupChatItem> groupChats = [];
      try {
        groupChats = await GroupChatService().myGroupChats();
      } catch (_) {}
      Map<String, String> nicknames = {};
      try {
        nicknames = await NicknameService().load();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _users = users;
        _chats = chats;
        _groupChats = groupChats;
        _nicknames = nicknames;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _incomingSub?.cancel();
    super.dispose();
  }

  /// Cap nhat trang thai online khi mo / thoat app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chat.setOnline(true).catchError((Object _) {});
      RealtimeService().connect();
      _checkIncoming();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _chat.setOnline(false).catchError((Object _) {});
    }
  }

  /// Lang nghe cuoc goi den -> bat man hinh do chuong.
  bool _checkingIncoming = false;
  Future<void> _checkIncoming() async {
    if (!mounted || _checkingIncoming) return;
    _checkingIncoming = true;
    try {
      await _pollIncoming();
    } finally {
      _checkingIncoming = false;
    }
  }

  Future<void> _pollIncoming() async {
    try {
      final incoming = await _calls.incomingCalls();
      for (final call in incoming) {
        _onIncomingCall(call);
      }
    } catch (_) {
      // Polling loi thi bo qua luot nay, luot sau thu lai.
    }
    try {
      final groupIncoming = await GroupCallService().incoming();
      for (final call in groupIncoming) {
        _onIncomingGroupCall(call);
      }
    } catch (_) {}
  }

  void _onIncomingGroupCall(GroupCallItem call) {
    if (!mounted || navigatorKey.currentState == null) return;
    if (_seenGroupIncoming.contains(call.id)) return;
    _seenGroupIncoming.add(call.id);
    if (CallService.inCall || _showingIncoming) {
      GroupCallService().leave(call.id).catchError((Object _) {});
      return;
    }
    _showingIncoming = true;
    navigatorKey.currentState!
        .push(
          MaterialPageRoute(
            builder: (_) => IncomingGroupCallScreen(call: call),
          ),
        )
        .then((_) => _showingIncoming = false);
  }

  void _onIncomingCall(CallItem call) {
    if (!mounted || navigatorKey.currentState == null) return;
    if (_seenIncoming.contains(call.id)) return;
    // Backend da tu chuyen ringing qua 40 giay thanh missed.
    if (call.status != 'ringing') return;
    _seenIncoming.add(call.id);
    // Dang ban -> tu choi
    if (CallService.inCall || _showingIncoming) {
      _calls.updateStatus(call.id, 'rejected').catchError((Object _) {});
      return;
    }
    _showingIncoming = true;
    navigatorKey.currentState!
        .push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(callId: call.id, call: call),
          ),
        )
        .then((_) => _showingIncoming = false);
  }

  void _openChat(AppUser peer) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ['Đoạn chat', 'Cuộc gọi', 'Reels', 'Cá nhân'][_selectedTab],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          if (_selectedTab == 0)
            IconButton(
              tooltip: 'Kết bạn bằng QR',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Cuộc gọi',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildChatTab(),
          const CallsTab(),
          const ReelsTab(),
          const ProfileTab(),
        ],
      ),
    );
  }

  Widget _buildChatTab() => Column(
    children: [
      if (_profileError != null)
        MaterialBanner(
          content: Text('Không đồng bộ được tài khoản: $_profileError'),
          actions: [
            TextButton(onPressed: _syncProfile, child: const Text('Thử lại')),
          ],
        ),
      // Hang ngang nguoi dung (giong thanh "dang hoat dong" cua Messenger)
      SizedBox(
        height: 112,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Không tải được người dùng: $_loadError',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _users.isEmpty
            ? const EmptyState(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Chưa có bạn bè',
                subtitle: 'Hãy kết bạn bằng QR hoặc số điện thoại ở nút + trên góc phải.',
              )
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                itemCount: _users.length,
                itemBuilder: (_, i) {
                  final u = _users[i];
                  return GestureDetector(
                    onTap: () => _openChat(u),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          Avatar(
                            name: u.name,
                            radius: 28,
                            online: u.online,
                            imageUrl: u.avatarUrl,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      const Divider(height: 1),
      // Danh sach doan chat: doan dang hien + doan da luu tru
      // (luu tru chi giau o may minh, nguoi kia van thay binh thuong).
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(child: Text('Lỗi: $_loadError'))
            : _chats.isEmpty
            ? const EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Chưa có đoạn chat nào',
                subtitle: 'Chọn một người ở trên để bắt đầu nhắn tin.',
              )
            : RefreshIndicator(
                onRefresh: () => _loadData(),
                child: ListView(
                  children: [
                    ..._chats
                        .where((c) => !c.isArchived)
                        .map((chat) => _chatTile(chat)),
                    if (_groupChats.isNotEmpty) ...[
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: SectionTitle(
                          icon: Icons.group_rounded,
                          title: 'Nhóm chat',
                        ),
                      ),
                      ..._groupChats.map(
                        (g) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.group_outlined),
                          ),
                          title: Text(
                            g.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            g.lastMessage.isEmpty
                                ? g.members.map((m) => m.userName).join(', ')
                                : g.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _fmt(g.updatedAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatScreen(group: g),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_chats.any((c) => c.isArchived)) ...[
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(
                          'Đã lưu trữ (${_chats.where((c) => c.isArchived).length})',
                        ),
                        subtitle: const Text('Chỉ mình bạn thấy mục này'),
                        trailing: Icon(
                          _showArchived ? Icons.expand_less : Icons.expand_more,
                        ),
                        onTap: () =>
                            setState(() => _showArchived = !_showArchived),
                      ),
                      if (_showArchived)
                        ..._chats
                            .where((c) => c.isArchived)
                            .map((chat) => _chatTile(chat, archived: true)),
                    ],
                  ],
                ),
              ),
      ),
    ],
  );

  Widget _chatTile(ChatItem chat, {bool archived = false}) {
    final peerId = chat.peerId;
    final peerName = NicknameService.display(_nicknames, peerId, chat.peerName);
    final isMine = chat.lastSenderId == _chat.myUid;
    return ListTile(
      leading: Avatar(
        name: peerName,
        online: chat.peerOnline,
        imageUrl: chat.peerAvatarUrl,
      ),
      title: Text(
        peerName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${isMine ? 'Bạn: ' : ''}${chat.lastMessage}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _fmt(chat.updatedAt),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: () => _openChat(
        AppUser(uid: peerId, name: peerName, online: chat.peerOnline),
      ),
      onLongPress: () async {
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              archived ? 'Đoạn chat đã lưu trữ' : 'Lưu trữ đoạn chat?',
            ),
            content: Text(
              archived
                  ? 'Khôi phục để đoạn chat với $peerName hiện lại ở danh sách chính.'
                  : 'Đoạn chat với $peerName sẽ bị giấu khỏi danh sách chính, chỉ mình bạn biết. Người kia vẫn thấy bình thường, tin nhắn không bị xóa.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, archived ? 'unarchive' : 'archive'),
                child: Text(archived ? 'Khôi phục' : 'Lưu trữ'),
              ),
            ],
          ),
        );
        if (action == null || !mounted) return;
        try {
          if (action == 'archive') {
            await _chat.archiveChat(peerId);
          } else {
            await _chat.unarchiveChat(peerId);
          }
          await _loadData(silent: true);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      },
    );
  }

  String _fmt(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    return DateFormat('dd/MM').format(t);
  }
}
