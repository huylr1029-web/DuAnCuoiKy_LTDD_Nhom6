import 'api_client.dart';

/// Biet danh rieng cho ban be, luu tren backend theo tung nguoi dat.
/// Chi nguoi dat moi thay: A dat biet danh cho B thi chi A thay,
/// B van thay ten that cua A tru khi B cung tu dat biet danh cho A.
class NicknameService {
  final _api = ApiClient.instance;

  Future<Map<String, String>> load() async {
    final body = await _api.getJson('FriendNicknames');
    final list = body as List<dynamic>;
    final map = <String, String>{};
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final peerId = (m['peerId'] ?? '').toString();
      final nickname = (m['nickname'] ?? '').toString();
      if (peerId.isNotEmpty && nickname.isNotEmpty) map[peerId] = nickname;
    }
    return map;
  }

  Future<void> set(String peerId, String nickname) async {
    await _api.putJson('FriendNicknames/$peerId', {'nickname': nickname});
  }

  Future<void> remove(String peerId) async {
    await _api.deleteJson('FriendNicknames/$peerId');
  }

  static String display(Map<String, String> nicknames, String peerId, String realName) =>
      nicknames[peerId] ?? realName;
}
