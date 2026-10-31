import '../models/api_models.dart';
import '../models/app_user.dart';
import 'api_client.dart';

/// Bao hieu cuoc goi (signaling) qua REST + SignalR, thay cho Firestore.
///   tao cuoc goi   -> POST /api/Calls
///   goi den        -> GET /api/Calls/incoming
///   1 cuoc goi     -> GET /api/Calls/{id}
///   lich su        -> GET /api/Calls/my?direction=...
///   doi trang thai -> PUT /api/Calls/{id}/status
/// Am thanh / hinh anh VAN chay qua Agora, channelId chinh la Id cua
/// Call nay (giong ban goc: callId lam ten kenh Agora).
class CallService {
  final _api = ApiClient.instance;

  /// Dang trong cuoc goi hay khong (de bao "ban" khi co nguoi khac goi toi).
  static bool inCall = false;

  Future<String> startCall({required AppUser peer, required bool isVideo}) async {
    final body = await _api.postJson('Calls', {
      'peerId': peer.uid,
      'isVideo': isVideo,
    });
    return (body as Map<String, dynamic>)['id'].toString();
  }

  /// Cac cuoc goi dang do chuong toi minh (backend tu chuyen ringing
  /// qua 40 giay thanh missed, khong can xu ly o Flutter nua).
  Future<List<CallItem>> incomingCalls() async {
    final body = await _api.getJson('Calls/incoming');
    final list = body as List<dynamic>;
    return list
        .map((e) => CallItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CallItem?> callById(String callId) async {
    try {
      final body = await _api.getJson('Calls/$callId');
      return CallItem.fromJson(body as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<CallItem>> myCalls({String direction = 'all'}) async {
    final body = await _api.getJson(
      'Calls/my',
      query: {'direction': direction},
    );
    final list = body as List<dynamic>;
    return list
        .map((e) => CallItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateStatus(String callId, String status) async {
    await _api.putJson('Calls/$callId/status', {'status': status});
  }
}
