import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import '../services/reels_service.dart';
import '../widgets/avatar.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// Trang Ca nhan theo yeu cau moi:
/// - Phan dau: thong tin tai khoan.
/// - Lich su hoat dong: TAT CA hoat dong (bai dang, cuoc goi,
///   tin nhan, ket ban) gop chung 1 danh sach, moi nhat truoc,
///   khong tach thanh nhieu muc rieng nua.
/// - Cai dat: doi ten cua minh, doi mat khau, dang xuat.
/// Khong co muc cai dat ao: moi muc trong Cai dat deu goi API that
/// hoac dang xuat that.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

enum _ActivityKind { reel, call, chat, friend }

class _Activity {
  final _ActivityKind kind;
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final AppUser? peer;
  const _Activity({
    required this.kind,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    this.peer,
  });
}

class _ProfileTabState extends State<ProfileTab> {
  bool _signingOut = false;
  List<_Activity> _activities = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final posts = await ReelsService().myReels();
      final calls = await CallService().myCalls(direction: 'all');
      final chats = await ChatService().myChats();
      List<FriendRequestItem> friends = [];
      try {
        final out = await FriendService().list(direction: 'outgoing', status: 'accepted');
        final inc = await FriendService().list(direction: 'incoming', status: 'accepted');
        friends = [...out, ...inc];
      } catch (_) {
        friends = [];
      }
      final current = AuthService().currentUser;
      final activities = <_Activity>[];
      for (final post in posts) {
        activities.add(_Activity(
          kind: _ActivityKind.reel,
          date: post.createdAt,
          title: post.caption.isEmpty ? 'Bài đăng không có chú thích' : post.caption,
          subtitle: 'Bài đăng Reels${post.musicUrl != null && post.musicUrl!.isNotEmpty ? ' · Có nhạc' : ''}',
          icon: Icons.image_outlined,
          imageUrl: post.imageUrl.isEmpty ? null : post.imageUrl,
        ));
      }
      for (final call in calls.take(20)) {
        final isOutgoing = current != null && call.callerId == current.uid;
        final peerName = isOutgoing ? call.calleeName : call.callerName;
        final peerId = isOutgoing ? call.calleeId : call.callerId;
        activities.add(_Activity(
          kind: _ActivityKind.call,
          date: call.createdAt,
          title: '${isOutgoing ? 'Gọi đi' : 'Gọi đến'} · $peerName',
          subtitle: '${call.isVideo ? 'Video' : 'Thoại'} · ${call.status}',
          icon: call.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
          peer: AppUser(uid: peerId, name: peerName),
        ));
      }
      for (final chat in chats) {
        activities.add(_Activity(
          kind: _ActivityKind.chat,
          date: chat.updatedAt,
          title: 'Nhắn tin với ${chat.peerName}',
          subtitle: chat.lastMessage.isEmpty ? 'Chưa có tin nhắn' : chat.lastMessage,
          icon: Icons.chat_outlined,
          peer: AppUser(uid: chat.peerId, name: chat.peerName, online: chat.peerOnline),
        ));
      }
      for (final item in friends) {
        final isOutgoing = current != null && item.senderId == current.uid;
        final peerName = isOutgoing ? item.receiverName : item.senderName;
        final peerId = isOutgoing ? item.receiverId : item.senderId;
        final date = item.respondedAt ?? item.createdAt;
        activities.add(_Activity(
          kind: _ActivityKind.friend,
          date: date,
          title: 'Đã kết bạn với $peerName',
          subtitle: 'Bạn bè',
          icon: Icons.person_add_outlined,
          peer: AppUser(uid: peerId, name: peerName),
        ));
      }
      activities.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _activities = activities;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _editMyName() async {
    final current = AuthService().currentUser;
    if (current == null) return;
    final controller = TextEditingController(text: current.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi tên của mình'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tên hiển thị / biệt danh của bạn',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Lưu')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await AuthService().updateMyName(name);
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi tên của bạn.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _changePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: currentCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu mới (tối thiểu 6 ký tự)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đổi mật khẩu')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (newCtrl.text != confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu mới nhập lại không khớp.')));
      return;
    }
    if (newCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu mới tối thiểu 6 ký tự.')));
      return;
    }
    try {
      await AuthService().changeMyPassword(currentCtrl.text, newCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi mật khẩu. Hãy đăng nhập lại bằng mật khẩu mới.')));
      await AuthService().logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _changeAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'avatar.jpg' : picked.name;
      final contentType = name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      await AuthService().updateAvatar(name, bytes, contentType);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi ảnh đại diện.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có muốn đăng xuất khỏi tài khoản này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await AuthService().logout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể đăng xuất: $error')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Bạn chưa đăng nhập.'));
    }
    final name = currentUser.name.isEmpty ? 'Người dùng' : currentUser.name;
    final email = currentUser.email;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(children: [
          Avatar(name: name, radius: 40, imageUrl: currentUser.avatarUrl),
          const SizedBox(height: 12),
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(email, style: Theme.of(context).textTheme.bodyMedium),
          if (currentUser.phone != null && currentUser.phone!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(currentUser.phone!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Chip(
            avatar: Icon(Icons.circle, size: 10, color: currentUser.online ? AppColors.success : AppColors.muted),
            label: Text(currentUser.online ? 'Đang hoạt động' : 'Không hoạt động'),
          ),
        ])),
        const SizedBox(height: 24),
        const SectionTitle(icon: Icons.history_rounded, title: 'Lịch sử hoạt động'),
        const SizedBox(height: 4),
        const Text('Tất cả bài đăng, cuộc gọi, tin nhắn và kết bạn, mới nhất trước.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text('Không tải được lịch sử: $_error')
        else if (_activities.isEmpty)
          const EmptyState(icon: Icons.history_rounded, title: 'Chưa có hoạt động nào', subtitle: 'Nhắn tin, gọi điện hoặc đăng Reels để thấy lịch sử ở đây.')
        else
          Column(
            children: _activities.map((a) {
              final tile = ListTile(
                contentPadding: EdgeInsets.zero,
                leading: a.imageUrl != null
                    ? SizedBox(
                        width: 54,
                        height: 54,
                        child: Image.network(a.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined)))
                    : CircleAvatar(child: Icon(a.icon, size: 20)),
                title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_fmt(a.date)} · ${a.subtitle}'),
                onTap: a.peer == null
                    ? null
                    : () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ChatScreen(peer: a.peer!)));
                      },
              );
              return tile;
            }).toList(),
          ),
        const SizedBox(height: 24),
        const SectionTitle(icon: Icons.settings_rounded, title: 'Cài đặt'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên của mình'),
              subtitle: Text(name),
              onTap: _editMyName,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Đổi ảnh đại diện'),
              subtitle: const Text('Chọn ảnh từ thư viện'),
              onTap: _changeAvatar,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Đổi mật khẩu'),
              subtitle: const Text('Cần mật khẩu hiện tại, sau khi đổi sẽ đăng nhập lại'),
              onTap: _changePassword,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text('Đăng xuất tài khoản', style: TextStyle(color: Colors.red[700])),
              onTap: _signingOut ? null : _signOut,
            ),
          ]),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
