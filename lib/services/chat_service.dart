import '../models/api_models.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Thay cho ChatService Firestore cu. Moi thao tac deu la REST:
///   users            -> GET /api/Users
///   chats cua toi    -> GET /api/Chats/my
///   tin nhan         -> GET /api/Chats/{peerId}/messages
///   gui tin / call-log -> POST /api/Chats/{peerId}/...
/// Realtime (tin moi ve ngay) chay qua RealtimeService (SignalR);
/// cac man hinh van poll dinh ky de chac chan khong sot tin neu
/// SignalR mat ket noi.
class ChatService {
  final _api = ApiClient.instance;

  String get myUid => AuthService().myUid ?? '';
  String get myName => AuthService().myName;

  /// Hai nguoi luon co cung 1 chatId (sap xep uid theo thu tu).
  /// Backend cung tinh y hec vay, dung de JoinChat qua SignalR.
  static String chatIdOf(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  Future<List<AppUser>> otherUsers() async {
    final body = await _api.getJson('Users');
    final list = body as List<dynamic>;
    return list
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .where((u) => u.uid != myUid)
        .toList();
  }

  Future<AppUser?> userById(String uid) async {
    try {
      final body = await _api.getJson('Users/$uid');
      return AppUser.fromJson(body as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ChatItem>> myChats() async {
    final body = await _api.getJson('Chats/my');
    final list = body as List<dynamic>;
    return list
        .map((e) => ChatItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageItem>> messages(String peerId) async {
    final body = await _api.getJson('Chats/$peerId/messages');
    final list = body as List<dynamic>;
    return list
        .map((e) => MessageItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendMessage(AppUser peer, String text,
      {String type = 'text', bool isVideo = false}) async {
    await _api.postJson('Chats/${peer.uid}/messages', {
      'text': text,
      'type': type,
      'isVideo': isVideo,
    });
  }

  /// Ghi lich su cuoc goi vao doan chat (giong Messenger).
  /// Backend tu dinh dang text giong ban goc: "Cuoc goi video · 02:15",
  /// "Cuoc goi thoai bi tu choi", "Cuoc goi video nho".
  Future<void> sendCallLog(AppUser peer,
      {required bool isVideo, required String outcome, int? seconds}) async {
    await _api.postJson('Chats/${peer.uid}/call-log', {
      'isVideo': isVideo,
      'outcome': outcome,
      'seconds': seconds,
    });
  }

  /// Gui hinh anh trong chat: multipart, backend tra ve tin nhan
  /// type=image, Text = URL tuyet doi cua anh.
  Future<void> sendImageMessage(AppUser peer, String filename, List<int> bytes, String contentType) async {
    await _api.postMultipart(
      'Chats/${peer.uid}/image',
      {},
      {'image': (filename: filename, bytes: bytes, contentType: contentType)},
    );
  }

  /// Gui vi tri: dung luon endpoint gui tin, type=location,
  /// Text = "lat,lng" de ben nhan mo ban do.
  Future<void> sendLocationMessage(AppUser peer, double lat, double lng) async {
    await sendMessage(peer, '$lat,$lng', type: 'location');
  }

  /// Gui tin nhan thoai: multipart audio, backend tra ve tin nhan
  /// type=voice, Text = URL tuyet doi cua file am thanh.
  Future<void> sendVoiceMessage(AppUser peer, String filename, List<int> bytes, String contentType) async {
    await _api.postMultipart(
      'Chats/${peer.uid}/voice',
      {},
      {'audio': (filename: filename, bytes: bytes, contentType: contentType)},
    );
  }

  /// Cam xuc cho tin nhan trong doan chat voi peer.
  /// Tra ve map messageId -> list (userId, emoji).
  Future<Map<int, List<({String userId, String emoji})>>> reactions(String peerId) async {
    final body = await _api.getJson('Chats/$peerId/reactions');
    final list = body as List<dynamic>;
    final map = <int, List<({String userId, String emoji})>>{};
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final id = (m['messageId'] as num?)?.toInt() ?? 0;
      map.putIfAbsent(id, () => []).add((
      userId: (m['userId'] ?? '').toString(),
      emoji: (m['emoji'] ?? '').toString(),
      ));
    }
    return map;
  }

  Future<void> setReaction(int messageId, String emoji) async {
    await _api.putJson('Chats/messages/$messageId/reactions', {'emoji': emoji});
  }

  Future<void> removeReaction(int messageId) async {
    await _api.deleteJson('Chats/messages/$messageId/reactions');
  }

  /// Luu tru / khoi phuc doan chat, chi rieng minh (nguoi kia khong biet).
  Future<void> archiveChat(String peerId) async {
    await _api.putJson('Chats/$peerId/archive', {});
  }

  Future<void> unarchiveChat(String peerId) async {
    await _api.deleteJson('Chats/$peerId/archive');
  }

  /// Danh dau tin cua doi phuong la da xem.
  Future<void> markRead(String peerId) async {
    try {
      await _api.putJson('Chats/$peerId/read', {});
    } catch (_) {}
  }

  /// Bao doi phuong la minh dang nhap (goi toi da moi 2 giay ben UI).
  Future<void> sendTyping(String peerId) async {
    try {
      await _api.postJson('Chats/$peerId/typing', {});
    } catch (_) {}
  }

  Future<bool> isPeerTyping(String peerId) async {
    try {
      final body = await _api.getJson('Chats/$peerId/typing');
      return (body as Map<String, dynamic>)['isTyping'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setOnline(bool online) async {
    if (myUid.isEmpty) return;
    await _api.putJson('Users/me/online', {'online': online});
  }
}
