import '../models/api_models.dart';
import 'api_client.dart';
import 'auth_service.dart';

class GroupCallService {
  final _api = ApiClient.instance;

  /// inCall cua CallService duoc dung chung de bao "ban" khi co
  /// goi khac den, ca 1-1 va nhom.

  Future<GroupCallItem> create({required List<String> participantIds, required bool isVideo}) async {
    final body = await _api.postJson('GroupCalls', {
      'participantIds': participantIds,
      'isVideo': isVideo,
    });
    return GroupCallItem.fromJson(body as Map<String, dynamic>);
  }

  Future<List<GroupCallItem>> incoming() async {
    final body = await _api.getJson('GroupCalls/incoming');
    final list = body as List<dynamic>;
    return list.map((e) => GroupCallItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<GroupCallItem?> byId(String id) async {
    try {
      final body = await _api.getJson('GroupCalls/$id');
      return GroupCallItem.fromJson(body as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> join(String id) async {
    await _api.putJson('GroupCalls/$id/join', {});
  }

  Future<void> leave(String id) async {
    await _api.putJson('GroupCalls/$id/leave', {});
  }

  Future<void> end(String id) async {
    await _api.putJson('GroupCalls/$id/end', {});
  }

  String get myUid => AuthService().myUid ?? '';
}
