import '../models/api_models.dart';
import '../models/app_user.dart';
import 'api_client.dart';

/// Thay cho cac truy van Firestore truc tiep trong FriendsScreen cu:
///   tim bang SDT  -> GET /api/Users/by-phone?phone=...
///   gui loi moi  -> POST /api/FriendRequests
///   danh sach    -> GET /api/FriendRequests?direction=...&status=...
///   tra loi      -> PUT /api/FriendRequests/{id}/respond
/// Logic trung / nguoc cua backend giu nguyen ban goc: loi moi nguoc
/// dang pending thi bao "hay chap nhan ben duoi", da gui / da la ban
/// thi bao tuong ung (backend tra 409 kem message).
class FriendService {
  final _api = ApiClient.instance;

  Future<AppUser> findByPhone(String phone) async {
    final body = await _api.getJson(
      'Users/by-phone',
      query: {'phone': phone},
    );
    return AppUser.fromJson(body as Map<String, dynamic>);
  }

  Future<FriendRequestItem> invite(String receiverId) async {
    final body = await _api.postJson('FriendRequests', {'receiverId': receiverId});
    return FriendRequestItem.fromJson(body as Map<String, dynamic>);
  }

  Future<List<FriendRequestItem>> list({
    required String direction,
    required String status,
  }) async {
    final body = await _api.getJson(
      'FriendRequests',
      query: {'direction': direction, 'status': status},
    );
    final list = body as List<dynamic>;
    return list
        .map((e) => FriendRequestItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> respond(int id, String status) async {
    await _api.putJson('FriendRequests/$id/respond', {'status': status});
  }

  Future<void> deleteFriend(int id) async {
    await _api.deleteJson('FriendRequests/$id');
  }
}
