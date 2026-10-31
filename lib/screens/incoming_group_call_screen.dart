import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../widgets/avatar.dart';
import 'group_call_screen.dart';
import '../theme.dart';

/// Man hinh cuoc goi nhom den: hien nguoi tao + danh sach duoc moi,
/// Chap nhan thi join roi vao man hinh goi nhom, Tu choi thi leave.
class IncomingGroupCallScreen extends StatelessWidget {
  final GroupCallItem call;
  const IncomingGroupCallScreen({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final names = call.participants.map((p) => p.userName).join(', ');
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.darkGradient),
        child: SafeArea(
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Avatar(name: call.creatorName, radius: 48),
            const SizedBox(height: 20),
            Text(call.creatorName,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(call.isVideo ? 'Đang mời bạn vào cuộc gọi video nhóm' : 'Đang mời bạn vào cuộc gọi thoại nhóm',
                style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text('Thành viên: $names',
                  style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 48),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Column(children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      await GroupCallService().leave(call.id);
                    } catch (_) {}
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 30)),
                ),
                const SizedBox(height: 8),
                const Text('Từ chối', style: TextStyle(color: Colors.white)),
              ]),
              const SizedBox(width: 64),
              Column(children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      await GroupCallService().join(call.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    CallService.inCall = true;
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => GroupCallScreen(call: call, isCreator: false)));
                  },
                  child: Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                      child: Icon(call.isVideo ? Icons.videocam : Icons.call, color: Colors.white, size: 30)),
                ),
                const SizedBox(height: 8),
                const Text('Chấp nhận', style: TextStyle(color: Colors.white)),
              ]),
            ]),
          ]),
        ),
        ),
      ),
    );
  }
}
