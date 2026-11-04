import 'api_client.dart';

class RtcCredentials {
  final String appId;
  final String channelId;
  final String token;
  final int uid;
  const RtcCredentials(this.appId, this.channelId, this.token, this.uid);
}

class RtcService {
  static Future<void> ensureReady() async {
    try {
      final status = await ApiClient.instance.getJson('Rtc/status');
      if (status is! Map || status['configured'] != true) {
        throw const ApiException(
          'Máy chủ chưa cấu hình Agora. Cần điền App ID và App Certificate trên backend.',
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        throw const ApiException(
          'Máy chủ đang chạy backend cũ. Cần deploy backend mới lên Render để hai điện thoại gọi qua Internet.',
        );
      }
      rethrow;
    }
  }

  static Future<RtcCredentials> credentials(
    String callId, {
    bool isGroup = false,
  }) async {
    dynamic body;
    try {
      body = await ApiClient.instance.postJson('Rtc/token', {
        'callId': callId,
        'isGroup': isGroup,
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        throw const ApiException(
          'API đang dùng chưa có chức năng cấp token cuộc gọi. Cần triển khai backend mới lên máy chủ.',
        );
      }
      rethrow;
    }
    if (body is! Map ||
        body['appId'] is! String ||
        body['token'] is! String ||
        (body['token'] as String).isEmpty ||
        body['uid'] is! num ||
        body['channelId'] != callId) {
      throw const ApiException('Máy chủ trả cấu hình cuộc gọi không hợp lệ.');
    }
    return RtcCredentials(
      body['appId'] as String,
      callId,
      body['token'] as String,
      (body['uid'] as num).toInt(),
    );
  }
}
