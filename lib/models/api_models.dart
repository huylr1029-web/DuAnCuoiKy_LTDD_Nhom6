DateTime _date(dynamic value) {
  if (value == null) return DateTime.now();
  return DateTime.tryParse(value.toString()) ?? DateTime.now();
}

DateTime? _dateOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// 1 doan chat trong GET /api/Chats/my.
class ChatItem {
  final String chatId;
  final String peerId;
  final String peerName;
  final bool peerOnline;
  final String lastMessage;
  final String lastSenderId;
  final DateTime updatedAt;
  final bool isArchived;
  final String peerAvatarUrl;

  const ChatItem({
    required this.chatId,
    required this.peerId,
    required this.peerName,
    required this.peerOnline,
    required this.lastMessage,
    required this.lastSenderId,
    required this.updatedAt,
    this.isArchived = false,
    this.peerAvatarUrl = '',
  });

  factory ChatItem.fromJson(Map<String, dynamic> m) => ChatItem(
        chatId: (m['chatId'] ?? '').toString(),
        peerId: (m['peerId'] ?? '').toString(),
        peerName: (m['peerName'] ?? 'Người dùng').toString(),
        peerOnline: (m['peerOnline'] as bool?) ?? false,
        lastMessage: (m['lastMessage'] ?? '').toString(),
        lastSenderId: (m['lastSenderId'] ?? '').toString(),
        updatedAt: _date(m['updatedAt']),
        isArchived: (m['isArchived'] as bool?) ?? false,
        peerAvatarUrl: (m['peerAvatarUrl'] ?? '').toString(),
      );
}

/// 1 tin nhan trong GET /api/Chats/{peerId}/messages (moi nhat truoc).
class MessageItem {
  final int id;
  final String chatId;
  final String senderId;
  final String text;
  final String type; // text | call
  final bool isVideo;
  final DateTime createdAt;
  final bool isRead;

  const MessageItem({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.isVideo,
    required this.createdAt,
    this.isRead = false,
  });

  factory MessageItem.fromJson(Map<String, dynamic> m) => MessageItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        chatId: (m['chatId'] ?? '').toString(),
        senderId: (m['senderId'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        type: (m['type'] ?? 'text').toString(),
        isVideo: (m['isVideo'] as bool?) ?? false,
        createdAt: _date(m['createdAt']),
        isRead: (m['isRead'] as bool?) ?? false,
      );
}

/// 1 cuoc goi: POST /api/Calls tra ve, GET /api/Calls/my, /incoming.
/// Cuoc goi nhom: 1 kenh Agora chung cho tat ca thanh vien.
/// participants: invited / accepted / declined / left.
class GroupCallItem {
  final String id;
  final String creatorId;
  final String creatorName;
  final bool isVideo;
  final String status;
  final DateTime createdAt;
  final List<GroupCallParticipant> participants;

  const GroupCallItem({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    required this.isVideo,
    required this.status,
    required this.createdAt,
    required this.participants,
  });

  factory GroupCallItem.fromJson(Map<String, dynamic> m) => GroupCallItem(
        id: (m['id'] ?? '').toString(),
        creatorId: (m['creatorId'] ?? '').toString(),
        creatorName: (m['creatorName'] ?? 'Ai đó').toString(),
        isVideo: (m['isVideo'] as bool?) ?? true,
        status: (m['status'] ?? '').toString(),
        createdAt: _date(m['createdAt']),
        participants: ((m['participants'] as List<dynamic>?) ?? [])
            .map((e) => GroupCallParticipant.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class GroupCallParticipant {
  final String userId;
  final String userName;
  final String status;
  const GroupCallParticipant({required this.userId, required this.userName, required this.status});
  factory GroupCallParticipant.fromJson(Map<String, dynamic> m) => GroupCallParticipant(
        userId: (m['userId'] ?? '').toString(),
        userName: (m['userName'] ?? 'Người dùng').toString(),
        status: (m['status'] ?? '').toString(),
      );
}

/// Nhom chat: danh sach o trang chu.
class GroupChatItem {
  final String id;
  final String name;
  final String creatorId;
  final String lastMessage;
  final String lastSenderId;
  final DateTime updatedAt;
  final List<GroupChatMember> members;
  const GroupChatItem({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.lastMessage,
    required this.lastSenderId,
    required this.updatedAt,
    required this.members,
  });
  factory GroupChatItem.fromJson(Map<String, dynamic> m) => GroupChatItem(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? 'Nhóm chat').toString(),
        creatorId: (m['creatorId'] ?? '').toString(),
        lastMessage: (m['lastMessage'] ?? '').toString(),
        lastSenderId: (m['lastSenderId'] ?? '').toString(),
        updatedAt: _date(m['updatedAt']),
        members: ((m['members'] as List<dynamic>?) ?? [])
            .map((e) => GroupChatMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class GroupChatMember {
  final String userId;
  final String userName;
  const GroupChatMember({required this.userId, required this.userName});
  factory GroupChatMember.fromJson(Map<String, dynamic> m) => GroupChatMember(
        userId: (m['userId'] ?? '').toString(),
        userName: (m['userName'] ?? 'Người dùng').toString(),
      );
}

/// 1 tin nhan trong nhom chat, co them SenderName de hien ten nguoi gui.
class GroupChatMessageItem {
  final int id;
  final String groupChatId;
  final String senderId;
  final String senderName;
  final String text;
  final String type;
  final DateTime createdAt;
  const GroupChatMessageItem({
    required this.id,
    required this.groupChatId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.type,
    required this.createdAt,
  });
  factory GroupChatMessageItem.fromJson(Map<String, dynamic> m) => GroupChatMessageItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        groupChatId: (m['groupChatId'] ?? '').toString(),
        senderId: (m['senderId'] ?? '').toString(),
        senderName: (m['senderName'] ?? 'Ai đó').toString(),
        text: (m['text'] ?? '').toString(),
        type: (m['type'] ?? 'text').toString(),
        createdAt: _date(m['createdAt']),
      );
}

class CallItem {
  final String id;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final bool isVideo;
  final String status; // ringing | accepted | rejected | ended | missed
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CallItem({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.isVideo,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory CallItem.fromJson(Map<String, dynamic> m) => CallItem(
        id: (m['id'] ?? '').toString(),
        callerId: (m['callerId'] ?? '').toString(),
        callerName: (m['callerName'] ?? 'Ai đó').toString(),
        calleeId: (m['calleeId'] ?? '').toString(),
        calleeName: (m['calleeName'] ?? 'Người dùng').toString(),
        isVideo: (m['isVideo'] as bool?) ?? false,
        status: (m['status'] ?? '').toString(),
        createdAt: _date(m['createdAt']),
        updatedAt: _dateOrNull(m['updatedAt']),
      );
}

/// 1 loi moi ket ban: GET /api/FriendRequests, POST tra ve.
class FriendRequestItem {
  final int id;
  final String senderId;
  final String receiverId;
  final String senderName;
  final String receiverName;
  final String status; // pending | accepted | rejected
  final DateTime createdAt;
  final DateTime? respondedAt;

  const FriendRequestItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.receiverName,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory FriendRequestItem.fromJson(Map<String, dynamic> m) =>
      FriendRequestItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        senderId: (m['senderId'] ?? '').toString(),
        receiverId: (m['receiverId'] ?? '').toString(),
        senderName: (m['senderName'] ?? 'Người dùng').toString(),
        receiverName: (m['receiverName'] ?? 'Người dùng').toString(),
        status: (m['status'] ?? '').toString(),
        createdAt: _date(m['createdAt']),
        respondedAt: _dateOrNull(m['respondedAt']),
      );
}

/// 1 bai Reels: GET /api/Reels, /my, /user/{userId}, POST tra ve.
class ReelItem {
  final int id;
  final String authorId;
  final String authorName;
  final String caption;
  final String imageUrl;
  final String? musicUrl;
  final String? musicName;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final String authorAvatarUrl;

  const ReelItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.caption,
    required this.imageUrl,
    this.musicUrl,
    this.musicName,
    required this.createdAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
    this.authorAvatarUrl = '',
  });

  factory ReelItem.fromJson(Map<String, dynamic> m) => ReelItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        authorId: (m['authorId'] ?? '').toString(),
        authorName: (m['authorName'] ?? 'Người dùng').toString(),
        caption: (m['caption'] ?? '').toString(),
        imageUrl: (m['imageUrl'] ?? '').toString(),
        musicUrl: m['musicUrl'] as String?,
        musicName: m['musicName'] as String?,
        createdAt: _date(m['createdAt']),
        likeCount: (m['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: (m['likedByMe'] as bool?) ?? false,
        commentCount: (m['commentCount'] as num?)?.toInt() ?? 0,
        authorAvatarUrl: (m['authorAvatarUrl'] ?? '').toString(),
      );

  ReelItem copyWith({int? likeCount, bool? likedByMe, int? commentCount}) => ReelItem(
        id: id,
        authorId: authorId,
        authorName: authorName,
        caption: caption,
        imageUrl: imageUrl,
        musicUrl: musicUrl,
        musicName: musicName,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        commentCount: commentCount ?? this.commentCount,
        authorAvatarUrl: authorAvatarUrl,
      );
}

class ReelCommentItem {
  final int id;
  final int reelId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;
  const ReelCommentItem({
    required this.id,
    required this.reelId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });
  factory ReelCommentItem.fromJson(Map<String, dynamic> m) => ReelCommentItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        reelId: (m['reelId'] as num?)?.toInt() ?? 0,
        authorId: (m['authorId'] ?? '').toString(),
        authorName: (m['authorName'] ?? 'Người dùng').toString(),
        text: (m['text'] ?? '').toString(),
        createdAt: _date(m['createdAt']),
      );
}
