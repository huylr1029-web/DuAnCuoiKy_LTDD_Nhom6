import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/api_models.dart';
import 'api_client.dart';

/// Thay cho Reels Firestore + Firebase Storage cu:
///   danh sach  -> GET /api/Reels (50 moi nhat)
///   cua toi    -> GET /api/Reels/my
///   cua 1 user -> GET /api/Reels/user/{userId}
///   dang bai   -> POST /api/Reels (multipart: image, music, caption)
/// Anh / nhac luu o wwwroot/uploads/reels tren server ASP.NET, URL tra
/// ve la URL tuyet doi de Flutter phat truc tiep (giong getDownloadURL
/// cua Firebase truoc day).
class ReelsService {
  final _api = ApiClient.instance;

  Future<List<ReelItem>> list() async {
    final body = await _api.getJson('Reels');
    final list = body as List<dynamic>;
    return list
        .map((e) => ReelItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReelItem>> myReels() async {
    final body = await _api.getJson('Reels/my');
    final list = body as List<dynamic>;
    return list
        .map((e) => ReelItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReelItem>> userReels(String userId) async {
    final body = await _api.getJson('Reels/user/$userId');
    final list = body as List<dynamic>;
    return list
        .map((e) => ReelItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> like(int reelId) async {
    await _api.postJson('Reels/$reelId/like', {});
  }

  Future<void> unlike(int reelId) async {
    await _api.deleteJson('Reels/$reelId/like');
  }

  Future<List<ReelCommentItem>> comments(int reelId) async {
    final body = await _api.getJson('Reels/$reelId/comments');
    final list = body as List<dynamic>;
    return list.map((e) => ReelCommentItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ReelCommentItem> addComment(int reelId, String text) async {
    final body = await _api.postJson('Reels/$reelId/comments', {'text': text});
    return ReelCommentItem.fromJson(body as Map<String, dynamic>);
  }

  Future<ReelItem> create({
    required XFile image,
    PlatformFile? music,
    required String caption,
  }) async {
    final imageBytes = await image.readAsBytes();
    final files = <String, ({String filename, List<int> bytes, String contentType})>{
      'image': (
        filename: image.name,
        bytes: imageBytes,
        contentType: 'image/jpeg',
      ),
    };
    // ReelsTab luon goi pickFiles(withData: true) nen music.bytes co san.
    // Neu khong co bytes thi bo qua nhac, van dang duoc anh + caption.
    if (music != null && music.bytes != null) {
      files['music'] = (
        filename: music.name,
        bytes: music.bytes!,
        contentType: 'audio/mpeg',
      );
    }
    final body = await _api.postMultipart(
      'Reels',
      {'caption': caption},
      files,
    );
    return ReelItem.fromJson(body as Map<String, dynamic>);
  }
}
