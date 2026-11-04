import 'package:flutter/material.dart';

// Agora App ID and short-lived tokens are supplied by the authenticated backend.

// Mau xanh Messenger.
const Color messengerBlue = Color(0xFF0084FF);

// Navigator toan cuc cho cuoc goi den.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Dia chi API ASP.NET Core tren Render.
String get apiBaseUrl => const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://duancuoiky-ltdd-api.onrender.com',
).trim().replaceAll(RegExp(r'/+$'), '');

// Web OAuth Client ID dung cho Google Sign-In.
const String googleServerClientId =
    '456041320178-ed0fovwvksdu8tt1fofqihntaegt3.apps.googleusercontent.com';

// Dia chi SignalR Hub cho nhan tin va cuoc goi realtime.
String get signalRHubUrl {
  final base = apiBaseUrl;
  final root = base.endsWith('/api')
      ? base.substring(0, base.length - 4)
      : base;
  return '$root/hubs/chat';
}
