import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'translation_service.dart';

/// Thay cho AuthService Firebase cu: dang ky / dang nhap / Google / quen
/// mat khau / dang xuat deu goi API ASP.NET, token JWT luu o
/// SharedPreferences de mo app lai khong phai dang nhap lai.
///
/// Dung dang singleton: AuthService() o bat ky man hinh nao cung chung
/// 1 trang thai dang nhap va 1 stream [authChanges] (thay cho
/// FirebaseAuth.instance.authStateChanges()).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  factory AuthService() => instance;

  final _api = ApiClient.instance;
  final _authController = StreamController<AppUser?>.broadcast();

  Stream<AppUser?> get authChanges => _authController.stream;
  AppUser? get currentUser => _api.currentUser;
  String? get myUid => _api.currentUser?.uid;
  String get myName => _api.currentUser?.name ?? 'Tôi';
  bool get isLoggedIn => _api.currentUser != null && _api.token != null;

  static String? normalizePhone(String raw) {
    final value = raw.replaceAll(RegExp(r'[\s.()-]'), '');
    String digits;
    if (RegExp(r'^0[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(1);
    } else if (RegExp(r'^\+84[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(3);
    } else if (RegExp(r'^84[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(2);
    } else {
      return null;
    }
    return '+84$digits';
  }

  Future<void> _saveSession(String token, AppUser user) async {
    _api.token = token;
    _api.currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    await prefs.setString(
      'auth_user',
      jsonEncode({
        'uid': user.uid,
        'name': user.name,
        'email': user.email,
        'phone': user.phone,
        'online': user.online,
        'avatarUrl': user.avatarUrl,
      }),
    );
    _authController.add(user);
  }

  Future<void> _clearSession() async {
    _api.token = null;
    _api.currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('auth_user');
    _authController.add(null);
  }

  AppUser _userFromAuthResponse(dynamic body) {
    final userJson =
        (body as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    return AppUser.fromJson(userJson);
  }

  String _tokenFromAuthResponse(dynamic body) =>
      (body as Map<String, dynamic>)['token'].toString();

  Future<void> register(
    String name,
    String email,
    String password,
    String phone,
  ) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      throw StateError('Số điện thoại không hợp lệ');
    }
    if (name.trim().isEmpty) {
      throw StateError('Vui lòng nhập họ tên');
    }
    final body = await _api.postJson('Authenticate/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'phone': normalized,
    });
    await _saveSession(
      _tokenFromAuthResponse(body),
      _userFromAuthResponse(body),
    );
  }

  Future<void> login(String email, String password) async {
    final body = await _api.postJson('Authenticate/login', {
      'email': email.trim(),
      'password': password,
    });
    await _saveSession(
      _tokenFromAuthResponse(body),
      _userFromAuthResponse(body),
    );
  }

  /// Doi ten hien thi / biet danh cua chinh minh.
  /// Chi doi ten, khong doi email / so dien thoai. Luu lai session
  /// de cac man hinh hien ten moi ngay ma khong can dang nhap lai.
  Future<AppUser> updateMyName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Tên hiển thị không được để trống');
    }
    final body = await _api.putJson('Users/me', {'name': trimmed});
    final user = AppUser.fromJson(body as Map<String, dynamic>);
    _api.currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_user',
      jsonEncode({
        'uid': user.uid,
        'name': user.name,
        'email': user.email,
        'phone': user.phone,
        'online': user.online,
        'avatarUrl': user.avatarUrl,
      }),
    );
    _authController.add(user);
    return user;
  }

  /// Doi anh dai dien: multipart, backend ghi de avatar.jpg.
  /// Sau khi doi, dong bo lai ho so de Avatar hien ngay.
  Future<void> updateAvatar(
    String filename,
    List<int> bytes,
    String contentType,
  ) async {
    await ApiClient.instance.postMultipart('Users/me/avatar', {}, {
      'image': (filename: filename, bytes: bytes, contentType: contentType),
    });
    await me();
  }

  /// Doi mat khau khi dang dang nhap. Sau khi doi thanh cong, app
  /// se dang xuat o man hinh Cai dat de nguoi dung dang nhap lai
  /// bang mat khau moi (JWT cu van con han, dang xuat la cach ro
  /// rang nhat de kiem chung mat khau moi).
  Future<void> changeMyPassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _api.putJson('Users/me/password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  /// Lay ho so hien tai tu backend (thay cho ensureUserProfile()).
  /// Backend tu dong danh dau online = true khi goi API nay.
  Future<AppUser> me() async {
    final body = await _api.getJson('Authenticate/me');
    final user = AppUser.fromJson(body as Map<String, dynamic>);
    _api.currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_user',
      jsonEncode({
        'uid': user.uid,
        'name': user.name,
        'email': user.email,
        'phone': user.phone,
        'online': user.online,
        'avatarUrl': user.avatarUrl,
      }),
    );
    return user;
  }

  /// Khoi phuc phien dang nhap khi mo app.
  /// Tra ve true neu dang nhap hop le, false neu het han / chua dang nhap.
  /// Chi nem loi khi khong ket noi duoc backend (de man hinh khoi dong
  /// hien dung loi "backend chua chay").
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final userJson = prefs.getString('auth_user');
    if (token == null || token.isEmpty || userJson == null) return false;
    _api.token = token;
    try {
      _api.currentUser = AppUser.fromJson(
        jsonDecode(userJson) as Map<String, dynamic>,
      );
    } catch (_) {
      await _clearSession();
      return false;
    }
    try {
      final user = await me();
      _authController.add(user);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearSession();
        return false;
      }
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    // serverClientId la bat buoc de Android tra ve idToken cho backend
    // xac thuc. Neu de trong, Google se khong tra idToken va ham nay
    // bao loi o duoi thay vi gui token rong len backend.
    await google.initialize(
      serverClientId: googleServerClientId.isEmpty
          ? null
          : googleServerClientId,
    );
    if (!google.supportsAuthenticate()) {
      throw StateError(
        'Thiết bị này chưa hỗ trợ đăng nhập Google theo cách này.',
      );
    }
    final account = await google.authenticate();
    final googleAuth = account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError(
        'Google không trả về ID token. Kiểm tra Web OAuth Client ID (serverClientId), OAuth Android package com.example.nhom6 và SHA-1 của khóa ký APK.',
      );
    }
    // Backend xac thuc idToken voi Google (can Google:ClientId trong
    // appsettings.json), roi cap JWT cua app, khong dung Firebase nua.
    final body = await _api.postJson('Authenticate/google', {
      'idToken': idToken,
    });
    await _saveSession(
      _tokenFromAuthResponse(body),
      _userFromAuthResponse(body),
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) {
      throw StateError('Vui lòng nhập địa chỉ email hợp lệ');
    }
    // Backend CHUA gui email that (chua cau hinh SMTP). O Development,
    // goi truc tiep POST /api/Authenticate/forgot-password bang Swagger
    // se thay them resetToken de demo doi mat khau.
    await _api.postJson('Authenticate/forgot-password', {'email': address});
  }

  Future<void> logout() async {
    TranslationService.instance.clear();
    try {
      await _api.postJson('Authenticate/logout', {});
    } catch (_) {
      // Loi mang khong duoc chan dang xuat o may.
    }
    await _clearSession();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nguoi dung email/password co the khong co phien Google.
    }
  }

  static String message(Object e) {
    if (e is ApiException) return e.message;
    if (e is StateError) return e.message.toString();
    return e.toString();
  }
}
