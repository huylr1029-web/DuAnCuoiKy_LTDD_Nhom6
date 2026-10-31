import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config.dart';
import '../models/api_models.dart';
import 'api_client.dart';

/// SignalR dung chung cho chat va cuoc goi.
/// Neu mat SignalR, chat_screen van tai tin nhan bang REST.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();
  factory RealtimeService() => instance;

  HubConnection? _connection;
  Future<void>? _connecting;
  Timer? _keepAlive;
  String? _connectedToken;
  final Set<String> _joinedChats = <String>{};

  bool get isConnected =>
      _connection?.state == HubConnectionState.Connected;

  final _messageController = StreamController<MessageItem>.broadcast();
  final _incomingController = StreamController<CallItem>.broadcast();
  final _callStatusController = StreamController<CallItem>.broadcast();

  Stream<MessageItem> get messageStream => _messageController.stream;
  Stream<CallItem> get incomingCallStream => _incomingController.stream;
  Stream<CallItem> get callStatusStream => _callStatusController.stream;

  Map<String, dynamic> _normalize(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final item in raw.entries) {
      final key = item.key.toString();
      result[key.isEmpty ? key : '${key[0].toLowerCase()}${key.substring(1)}'] =
          item.value;
    }
    return result;
  }

  Future<void> connect() async {
    final token = ApiClient.instance.token;
    if (token == null || token.isEmpty) return;

    if (isConnected && _connectedToken == token) return;
    if (_connecting != null) return _connecting!;

    final future = _connectInternal(token);
    _connecting = future;
    try {
      await future;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connectInternal(String token) async {
    if (_connection != null) {
      try {
        await _connection!.stop();
      } catch (e) {
        debugPrint('SignalR stop old connection: $e');
      }
      _connection = null;
    }

    try {
      final connection = HubConnectionBuilder()
          .withUrl(
        signalRHubUrl,
        options: HttpConnectionOptions(
          // Lay token moi nhat cho cac request SignalR.
          accessTokenFactory: () async => ApiClient.instance.token ?? '',
        ),
      )
          .build();

      connection.on('NewMessage', (args) {
        if (args == null || args.isEmpty) return;
        try {
          _messageController.add(
            MessageItem.fromJson(_normalize(args.first)),
          );
        } catch (e) {
          debugPrint('SignalR NewMessage parse error: $e');
        }
      });
      connection.on('IncomingCall', (args) {
        if (args == null || args.isEmpty) return;
        try {
          _incomingController.add(
            CallItem.fromJson(_normalize(args.first)),
          );
        } catch (e) {
          debugPrint('SignalR IncomingCall parse error: $e');
        }
      });
      connection.on('CallStatusChanged', (args) {
        if (args == null || args.isEmpty) return;
        try {
          _callStatusController.add(
            CallItem.fromJson(_normalize(args.first)),
          );
        } catch (e) {
          debugPrint('SignalR CallStatusChanged parse error: $e');
        }
      });

      await connection.start();
      _connection = connection;
      _connectedToken = token;
      debugPrint('SignalR connected: $signalRHubUrl');

      // Chat dang mo phai vao lai group khi ket noi moi.
      await _joinActiveChats();

      // Tu phuc hoi neu SignalR bi ngat. Moi 10 gi tham gia lai group
      // de xu ly truong hop ket noi duoc khoi phuc sau mat mang.
      _keepAlive ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (ApiClient.instance.token == null) return;
        if (!isConnected || _connectedToken != ApiClient.instance.token) {
          unawaited(connect());
        } else {
          unawaited(_joinActiveChats());
        }
      });
    } catch (e) {
      debugPrint('SignalR connect failed: $e');
      _connection = null;
      _connectedToken = null;
      // Van tiep tuc polling REST tu ChatScreen.
      _keepAlive ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (ApiClient.instance.token != null) unawaited(connect());
      });
    }
  }

  Future<void> _joinActiveChats() async {
    if (!isConnected) return;
    for (final id in _joinedChats.toList()) {
      try {
        await _connection!.invoke('JoinChat', args: [id]);
      } catch (e) {
        debugPrint('SignalR JoinChat($id): $e');
      }
    }
  }

  Future<void> joinChat(String chatId) async {
    if (chatId.isEmpty) return;
    _joinedChats.add(chatId);
    await connect();
    if (!isConnected) return;
    try {
      await _connection!.invoke('JoinChat', args: [chatId]);
    } catch (e) {
      debugPrint('SignalR JoinChat($chatId): $e');
    }
  }

  Future<void> leaveChat(String chatId) async {
    _joinedChats.remove(chatId);
    if (!isConnected) return;
    try {
      await _connection!.invoke('LeaveChat', args: [chatId]);
    } catch (e) {
      debugPrint('SignalR LeaveChat($chatId): $e');
    }
  }

  Future<void> disconnect() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    _joinedChats.clear();
    try {
      await _connection?.stop();
    } catch (e) {
      debugPrint('SignalR disconnect: $e');
    }
    _connection = null;
    _connectedToken = null;
  }
}
