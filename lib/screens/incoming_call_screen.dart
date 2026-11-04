import 'dart:async';

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import '../services/realtime_service.dart';
import '../widgets/avatar.dart';
import 'call_screen.dart';

/// Man hinh do chuong khi co nguoi goi toi.
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final CallItem call;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.call,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<CallItem>? _sub;
  Timer? _pollTimer;
  bool _handled = false;
  // Cung loi PopScope nhu CallScreen: canPop: false chan ca
  // Navigator.pop() tu nut Tu choi, nen phai bat _canPop = true
  // va pop sau frame rebuild.
  bool _canPop = false;

  void _popAfterRebuild() {
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  bool get _isVideo => widget.call.isVideo;
  String get _callerName => widget.call.callerName;

  @override
  void initState() {
    super.initState();
    // Neu nguoi goi huy / het gio -> tu dong dong man hinh.
    // Realtime qua SignalR + poll 2 giay (thay cho Firestore snapshots).
    _sub = RealtimeService().callStatusStream.listen((call) {
      if (call.id == widget.callId) _onStatusChanged(call.status);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_handled) return;
      try {
        final call = await CallService().callById(widget.callId);
        if (call != null) _onStatusChanged(call.status);
      } catch (_) {}
    });
  }

  void _onStatusChanged(String status) {
    if (!_handled && status != 'ringing' && mounted) {
      _handled = true;
      _popAfterRebuild();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_handled) return;
    setState(() => _handled = true);
    try {
      await CallService().updateStatus(widget.callId, 'accepted');
      if (!mounted) return;
      _pollTimer?.cancel();
      await _sub?.cancel();
      if (!mounted) return;
      setState(() => _canPop = true);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: widget.callId,
            peer: AppUser(uid: widget.call.callerId, name: _callerName),
            isVideo: _isVideo,
            isCaller: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _handled = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không nhận được cuộc gọi: $e')));
    }
  }

  Future<void> _decline() async {
    if (_handled) return;
    setState(() => _handled = true);
    try {
      await CallService().updateStatus(widget.callId, 'rejected');
      _pollTimer?.cancel();
      await _sub?.cancel();
      _popAfterRebuild();
    } catch (e) {
      if (!mounted) return;
      setState(() => _handled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không từ chối được cuộc gọi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1E21), Color(0xFF0B3D91)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 80),
                Avatar(name: _callerName, radius: 56),
                const SizedBox(height: 20),
                Text(
                  _callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isVideo ? 'Cuộc gọi video đến...' : 'Cuộc gọi thoại đến...',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _button(Icons.call_end, Colors.red, 'Từ chối', _decline),
                      _button(
                        _isVideo ? Icons.videocam : Icons.call,
                        const Color(0xFF31A24C),
                        'Trả lời',
                        _accept,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 34,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
