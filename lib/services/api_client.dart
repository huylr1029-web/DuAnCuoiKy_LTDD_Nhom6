import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/app_user.dart';

/// Loi tra ve tu backend hoac khi ket noi den backend that bai.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// REST client dung chung cho Auth, Chat, Call va cac dich vu khac.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? token;
  AppUser? currentUser;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Ho tro apiBaseUrl la domain goc HOAC domain co /api.
  /// Vi du:
  ///   https://largesparklyrock86.conveyor.cloud
  ///   https://largesparklyrock86.conveyor.cloud/api
  /// Deu tao URL: https://largesparklyrock86.conveyor.cloud/api/Authenticate/login
  Uri _uri(String path, [Map<String, String>? query]) {
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');

    if (base.isEmpty) {
      throw const ApiException('Chua cau hinh dia chi API trong config.dart');
    }

    final baseUri = Uri.tryParse(base);
    if (baseUri == null ||
        (baseUri.scheme != 'https' && baseUri.scheme != 'http') ||
        baseUri.host.isEmpty) {
      throw ApiException('Dia chi API khong hop le: $base');
    }

    // Tranh loi /api/api/... khi da co /api o config.dart hoac path.
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    final rootPath = basePath.endsWith('/api')
        ? basePath.substring(0, basePath.length - 4)
        : basePath;
    final endpoint = cleanPath.startsWith('api/')
        ? cleanPath.substring(4)
        : cleanPath;

    return baseUri.replace(
      path: '$rootPath/api/$endpoint',
      query: null,
      queryParameters: query,
      fragment: null,
    );
  }

  dynamic _decode(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    }
  }

  String _errorMessage(http.Response res, dynamic body) {
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }
    switch (res.statusCode) {
      case 400:
        return 'Du lieu gui len khong hop le';
      case 401:
        return 'Phien dang nhap da het han. Hay dang nhap lai';
      case 403:
        return 'Ban khong co quyen thuc hien hanh dong nay';
      case 404:
        return 'Khong tim thay API (${res.request?.url ?? '404'}). Kiem tra dia chi Conveyor';
      case 409:
        return 'Du lieu da ton tai';
      default:
        return 'May chu tra loi loi ${res.statusCode}';
    }
  }

  Never _throwNetwork(Object e) {
    if (e is ApiException) throw e;
    if (e is SocketException ||
        e is HttpException ||
        e is http.ClientException ||
        e is TimeoutException) {
      throw ApiException(
        'Khong ket noi duoc toi API ($apiBaseUrl). '
            'Kiem tra backend va Conveyor dang chay.',
      );
    }
    throw ApiException(e.toString());
  }

  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    try {
      final res = await http.get(_uri(path, query), headers: _headers);
      final body = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return body;
      throw ApiException(_errorMessage(res, body), res.statusCode);
    } catch (e) {
      _throwNetwork(e);
    }
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.post(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body),
      );
      final decoded = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
      throw ApiException(_errorMessage(res, decoded), res.statusCode);
    } catch (e) {
      _throwNetwork(e);
    }
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.put(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body),
      );
      final decoded = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
      throw ApiException(_errorMessage(res, decoded), res.statusCode);
    } catch (e) {
      _throwNetwork(e);
    }
  }

  Future<dynamic> deleteJson(String path) async {
    try {
      final res = await http.delete(_uri(path), headers: _headers);
      final decoded = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
      throw ApiException(_errorMessage(res, decoded), res.statusCode);
    } catch (e) {
      _throwNetwork(e);
    }
  }

  /// Gui multipart/form-data (dang anh dai dien, Reels...).
  Future<dynamic> postMultipart(
      String path,
      Map<String, String> fields,
      Map<String, ({String filename, List<int> bytes, String contentType})> files,
      ) async {
    try {
      final req = http.MultipartRequest('POST', _uri(path));
      if (token != null && token!.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.fields.addAll(fields);
      for (final entry in files.entries) {
        req.files.add(http.MultipartFile.fromBytes(
          entry.key,
          entry.value.bytes,
          filename: entry.value.filename,
        ));
      }
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final decoded = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
      throw ApiException(_errorMessage(res, decoded), res.statusCode);
    } catch (e) {
      _throwNetwork(e);
    }
  }
}
