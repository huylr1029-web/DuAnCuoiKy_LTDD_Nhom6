import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import '../services/nickname_service.dart';
import 'chat_screen.dart';
import 'group_call_screen.dart';
import 'group_chat_screen.dart';
import '../services/group_chat_service.dart';
import 'qr_scan_screen.dart';
import '../services/group_call_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friends = FriendService();
  final _chat = ChatService();
  bool _busy = false;
  String? _result;

  // Danh sach loi moi / ban be, nap lai sau moi lan tra loi.
  List<FriendRequestItem> _incomingPending = [];
  List<FriendRequestItem> _outgoingAccepted = [];
  List<FriendRequestItem> _incomingAccepted = [];
  Map<String, String> _nicknames = {};
  bool _loadingLists = true;
  final _phoneCtrl = TextEditingController();
  AppUser? _foundByPhone;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchByPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nhập số điện thoại cần tìm.')));
      }
      return;
    }
    if (mounted) setState(() => _busy = true);
    try {
      final found = await _friends.findByPhone(phone);
      if (!mounted) return;
      setState(() {
        _foundByPhone = found;
        _result = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _foundByPhone = null;
        _result = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteFound() async {
    final found = _foundByPhone;
    if (found == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      await _friends.invite(found.uid);
      await _loadLists();
      if (!mounted) return;
      setState(() {
        _result = 'Đã gửi lời mời kết bạn tới ${found.name}.';
        _foundByPhone = null;
        _phoneCtrl.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ma QR cua chinh minh: nguoi khac quet la co uid + ten cua minh
  /// de gui loi moi, khong can tim minh bang danh sach hay SDT.
  String _myQrData() {
    final me = AuthService().currentUser;
    if (me == null) return '';
    return jsonEncode({'t': 'friend', 'uid': me.uid, 'name': me.name});
  }

  Future<void> _showMyQr() async {
    final me = AuthService().currentUser;
    if (me == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chưa đăng nhập, hãy đăng nhập lại.')));
      }
      return;
    }
    // Doi tu AlertDialog sang trang rieng: tranh truong hop lop chan
    // cua dialog che het man hinh ma noi dung QR khong hien len.
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (qrContext) => Scaffold(
          appBar: AppBar(title: const Text('QR của tôi')),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(data: _myQrData(), version: QrVersions.auto, size: 280),
                  const SizedBox(height: 16),
                  Text(me.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 8),
                  const Text('Đưa mã này cho người khác quét để kết bạn với bạn.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: () => Navigator.pop(qrContext),
                      child: const Text('Đóng')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<({String id, String name})> _friendList() {
    final all = [..._outgoingAccepted, ..._incomingAccepted];
    final seen = <String>{};
    final friends = <({String id, String name})>[];
    for (final item in all) {
      final isOutgoing = _outgoingAccepted.contains(item);
      final peerId = isOutgoing ? item.receiverId : item.senderId;
      final realName = isOutgoing ? item.receiverName : item.senderName;
      if (seen.add(peerId)) friends.add((id: peerId, name: realName));
    }
    return friends;
  }

  Future<void> _createGroupChat() async {
    final friends = _friendList();
    if (friends.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cần ít nhất 2 bạn bè để tạo nhóm chat. Hãy kết bạn thêm bằng QR.')));
      return;
    }
    final nameCtrl = TextEditingController();
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tạo nhóm chat'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên nhóm', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ...friends.map((f) => CheckboxListTile(
                      title: Text(f.name),
                      value: selected.contains(f.id),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            selected.add(f.id);
                          } else {
                            selected.remove(f.id);
                          }
                        });
                      },
                    )),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tạo nhóm')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập tên nhóm.')));
      return;
    }
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chọn ít nhất 2 bạn để tạo nhóm chat.')));
      return;
    }
    try {
      final group = await GroupChatService().create(name: nameCtrl.text.trim(), memberIds: selected.toList());
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Chon it nhat 2 ban de goi nhom (tong cong it nhat 3 nguoi).
  /// Neu chi chon 1 ban thi dung goi 1-1 tu man hinh chat / ban be.
  Future<void> _startGroupCall() async {
    final all = [..._outgoingAccepted, ..._incomingAccepted];
    final seen = <String>{};
    final friends = <({String id, String name})>[];
    for (final item in all) {
      final isOutgoing = _outgoingAccepted.contains(item);
      final peerId = isOutgoing ? item.receiverId : item.senderId;
      final realName = isOutgoing ? item.receiverName : item.senderName;
      if (seen.add(peerId)) friends.add((id: peerId, name: realName));
    }
    if (friends.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cần ít nhất 2 bạn bè để gọi nhóm. Hãy kết bạn thêm bằng QR.')));
      return;
    }
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gọi video nhóm'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: friends.map((f) => CheckboxListTile(
                    title: Text(f.name),
                    value: selected.contains(f.id),
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true) {
                          selected.add(f.id);
                        } else {
                          selected.remove(f.id);
                        }
                      });
                    },
                  )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gọi nhóm')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chọn ít nhất 2 bạn để gọi nhóm.')));
      return;
    }
    try {
      final call = await GroupCallService().create(participantIds: selected.toList(), isVideo: true);
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => GroupCallScreen(call: call, isCreator: true)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.push<({String uid, String name})>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (scanned == null || !mounted) return;
    final me = AuthService().currentUser;
    if (me != null && scanned.uid == me.uid) {
      setState(() => _result = 'Đây là mã QR của chính bạn.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kết bạn bằng QR'),
        content: Text('Bạn muốn gửi lời mời kết bạn tới ${scanned.name} không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kết bạn')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _friends.invite(scanned.uid);
      await _loadLists();
      if (mounted) setState(() => _result = 'Đã gửi lời mời kết bạn tới ${scanned.name}.');
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadLists() async {
    if (mounted) setState(() => _loadingLists = true);
    try {
      final incomingPending = await _friends.list(
          direction: 'incoming', status: 'pending');
      final outgoingAccepted = await _friends.list(
          direction: 'outgoing', status: 'accepted');
      final incomingAccepted = await _friends.list(
          direction: 'incoming', status: 'accepted');
      Map<String, String> nicknames = {};
      try {
        nicknames = await NicknameService().load();
      } catch (_) {
        nicknames = {};
      }
      if (!mounted) return;
      setState(() {
        _incomingPending = incomingPending;
        _outgoingAccepted = outgoingAccepted;
        _incomingAccepted = incomingAccepted;
        _nicknames = nicknames;
        _loadingLists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLists = false);
    }
  }

  Future<void> _deleteFriend(FriendRequestItem item, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bạn?'),
        content: Text('Bạn có chắc muốn xóa $displayName khỏi danh sách bạn bè không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa bạn')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _friends.deleteFriend(item.id);
      await _loadLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa bạn bè.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editNickname(String peerId, String realName) async {
    final current = _nicknames[peerId] ?? '';
    final controller = TextEditingController(text: current);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Biệt danh cho $realName'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Biệt danh',
            hintText: 'Ví dụ: Béo, Boss...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (current.isNotEmpty)
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
        await NicknameService().remove(peerId);
      } else {
        final nickname = controller.text.trim();
        if (nickname.isEmpty) return;
        await NicknameService().set(peerId, nickname);
      }
      await _loadLists();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _respond(FriendRequestItem item, String status) async {
    try {
      await _friends.respond(item.id, status);
      await _loadLists();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _requests({
    required String title,
    required List<FriendRequestItem> items,
    required bool incoming,
    bool showActions = false,
  }) {
    if (_loadingLists) return const LinearProgressIndicator();
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title == 'Lời mời kết bạn'
              ? 'Không có lời mời đang chờ.'
              : 'Chưa có bạn bè.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return Column(
      children: items.map((item) {
        final realName = incoming ? item.senderName : item.receiverName;
        final peerId = incoming ? item.senderId : item.receiverId;
        final displayName =
            NicknameService.display(_nicknames, peerId, realName);
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                displayName.isNotEmpty
                    ? displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          title: Text(displayName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(showActions
              ? 'Muốn kết bạn với bạn'
              : (_nicknames.containsKey(peerId)
                  ? 'Đã kết bạn · Tên thật: $realName'
                  : 'Đã kết bạn')),
          trailing: showActions
              ? Wrap(spacing: 4, children: [
                  TextButton(
                      onPressed: () => _respond(item, 'rejected'),
                      child: const Text('Từ chối')),
                  FilledButton(
                      onPressed: () => _respond(item, 'accepted'),
                      child: const Text('Đồng ý')),
                ])
              : Wrap(spacing: 0, children: [
                  IconButton(
                    tooltip: 'Nhắn tin',
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () async {
                      final user = await _chat.userById(peerId);
                      if (!mounted) return;
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                  peer: user ??
                                      AppUser(uid: peerId, name: realName))));
                    },
                  ),
                  IconButton(
                    tooltip: 'Đổi biệt danh',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editNickname(peerId, realName),
                  ),
                  IconButton(
                    tooltip: 'Xóa bạn',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _deleteFriend(item, displayName),
                  ),
                ]),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    ButtonStyle rounded(WidgetStateProperty<Color?>? bg) =>
        ButtonStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16))),
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
        );
    return Scaffold(
      appBar: AppBar(
          title: const Text('Kết bạn bằng QR',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shield_outlined, color: primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Danh sách tài khoản chỉ hiện với bạn bè. Muốn kết bạn mới, bạn có thể đưa mã QR của bạn cho họ quét, quét mã QR của họ, hoặc tìm đúng số điện thoại của họ để gửi lời mời.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.phone_outlined, size: 20),
                SizedBox(width: 8),
                Text('Thêm bạn bằng số điện thoại',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Nhập số điện thoại, ví dụ 0912345678',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) => _searchByPhone(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _searchByPhone,
                  icon: const Icon(Icons.search),
                  label: const Text('Tìm số điện thoại'),
                ),
              ),
              if (_foundByPhone != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(_foundByPhone!.name.isNotEmpty
                        ? _foundByPhone!.name[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(_foundByPhone!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_foundByPhone!.phone ?? ''),
                  trailing: FilledButton(
                    onPressed: _busy ? null : _inviteFound,
                    child: const Text('Kết bạn'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
            style: rounded(null),
            onPressed: _showMyQr,
            icon: const Icon(Icons.qr_code),
            label: const Text('QR của tôi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            style: rounded(null),
            onPressed: _busy ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Quét QR kết bạn',
                style: TextStyle(fontSize: 16))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _startGroupCall,
                icon: const Icon(Icons.video_call_outlined),
                label: const Text('Gọi video nhóm')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _createGroupChat,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Tạo nhóm chat')),
          ),
        ]),
        if (_busy)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
        if (_result != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_result!),
          ),
        const SizedBox(height: 24),
        Row(children: [
          const Icon(Icons.mail_outline, size: 20),
          const SizedBox(width: 8),
          Text('Lời mời kết bạn (${_incomingPending.length})',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        const SizedBox(height: 10),
        _requests(
            title: 'Lời mời kết bạn',
            items: _incomingPending,
            incoming: true,
            showActions: true),
        const SizedBox(height: 20),
        Row(children: [
          const Icon(Icons.people_outline, size: 20),
          const SizedBox(width: 8),
          Text(
              'Bạn bè (${_outgoingAccepted.length + _incomingAccepted.length})',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        const SizedBox(height: 10),
        _requests(
            title: 'Bạn bè', items: _outgoingAccepted, incoming: false),
        _requests(
            title: 'Bạn bè', items: _incomingAccepted, incoming: true),
      ]),
    );
  }
}
