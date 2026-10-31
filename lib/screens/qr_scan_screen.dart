import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

/// Quet ma QR ket ban.
/// Ma QR cua app co dang JSON: {"t":"friend","uid":"...","name":"..."}
///
/// Tra ve (uid, name) qua Navigator.pop khi quet duoc ma hop le.
/// Ten lay tu chinh ma QR (nguoi dua ma da tu nguyen chia se),
/// khong goi API tra ho so nguoi la, dung quy tac bao mat:
/// nguoi la khong duoc tim / xem tai khoan khi chua la ban be.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['t'] != 'friend') return;
      final uid = (data['uid'] ?? '').toString();
      final name = (data['name'] ?? '').toString();
      if (uid.isEmpty) return;
      _handled = true;
      Navigator.pop(context, (uid: uid, name: name.isEmpty ? 'Người dùng' : name));
    } catch (_) {
      // Ma khong phai cua app: bo qua, tiep tuc quet.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quét QR kết bạn')),
      body: Column(children: [
        Expanded(
          child: MobileScanner(controller: _controller, onDetect: _onDetect),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: const Column(children: [
            Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 32),
            SizedBox(height: 8),
            Text(
              'Đưa camera về phía mã QR của người bạn muốn kết bạn.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Chỉ mã QR của app (chứa tên và mã người dùng) mới kết bạn được.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ]),
        ),
      ]),
    );
  }
}
