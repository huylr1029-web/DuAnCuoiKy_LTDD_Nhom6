import '../models/api_models.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Nhom chat, song song voi ChatService 1-1:
///   tao        -> POST /api/GroupChats
///   danh sach  -> GET /api/GroupChats/my
///   tin nhan   -> GET /api/GroupChats/{id}/messages
///   gui tin    -> POST /api/GroupChats/{id}/messages
///   gui anh    -> POST /api/GroupChats/{id}/image (multipart)
class GroupChatService {
  final _api = ApiClient.instance;

  String get myUid => AuthService().myUid ?? '';

  Future<GroupChatItem> create({required String name, required List<String> memberIds}) async {
    final body = await _api.postJson('GroupChats', {'name': name, 'memberIds': memberIds});
    return GroupChatItem.fromJson(body as Map<String, dynamic>);
  }

  Future<List<GroupChatItem>> myGroupChats() async {
    final body = await _api.getJson('GroupChats/my');
    final list = body as List<dynamic>;
    return list.map((e) => GroupChatItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<GroupChatMessageItem>> messages(String groupId) async {
    final body = await _api.getJson('GroupChats/$groupId/messages');
    final list = body as List<dynamic>;
    return list.map((e) => GroupChatMessageItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendMessage(String groupId, String text, {String type = 'text'}) async {
    await _api.postJson('GroupChats/$groupId/messages', {'text': text, 'type': type});
  }

  Future<void> sendImageMessage(String groupId, String filename, List<int> bytes, String contentType) async {
    await _api.postMultipart(
      'GroupChats/$groupId/image',
      {},
      {'image': (filename: filename, bytes: bytes, contentType: contentType)},
    );
  }

  Future<void> sendLocationMessage(String groupId, double lat, double lng) async {
    await sendMessage(groupId, '$lat,$lng', type: 'location');
  }
}
