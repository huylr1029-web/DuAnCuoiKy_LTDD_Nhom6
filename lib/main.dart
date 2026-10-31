import 'package:flutter/material.dart';

import 'config.dart';
import 'theme.dart';
import 'models/app_user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MessengerCallApp());
}

class MessengerCallApp extends StatefulWidget {
  const MessengerCallApp({super.key});

  @override
  State<MessengerCallApp> createState() => _MessengerCallAppState();
}

class _MessengerCallAppState extends State<MessengerCallApp> {
  late Future<bool> _session = AuthService().restoreSession();

  void _retry() {
    setState(() => _session = AuthService().restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger Call',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      home: FutureBuilder<bool>(
        future: _session,
        builder: (context, session) {
          if (session.hasError) {
            return _StartupError(
              error: session.error.toString(),
              onRetry: _retry,
            );
          }
          if (session.connectionState != ConnectionState.done) {
            return const _LoadingScreen(message: 'Đang kiểm tra đăng nhập...');
          }
          // Sau khi khoi phuc xong, doi theo stream dang nhap:
          // dang nhap -> Home, dang xuat -> Login (thay cho
          // FirebaseAuth.instance.authStateChanges() truoc day).
          return StreamBuilder<AppUser?>(
            stream: AuthService().authChanges,
            initialData: AuthService().currentUser,
            builder: (context, auth) {
              if (auth.hasError) {
                return _StartupError(
                  error: auth.error.toString(),
                  onRetry: _retry,
                );
              }
              return auth.data == null ? const LoginScreen() : const HomeScreen();
            },
          );
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const GradientIcon(icon: Icons.forum_rounded, size: 84),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(message, style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Không thể khởi động')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Không thể kết nối dịch vụ của ứng dụng.',
                    subtitle: 'Hãy kiểm tra backend đã chạy chưa rồi thử lại.'),
                const SizedBox(height: 4),
                const SizedBox(height: 12),
                SelectableText(error, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ]),
            ),
          ),
        ),
      );
}
