import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/rtc_service.dart';
import '../models/api_models.dart';
import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../widgets/avatar.dart';

/// Man hinh goi nhom: tat ca thanh vien vao CUNG 1 kenh Agora
/// (channel = groupCallId), moi nguoi hien 1 o trong luoi.
/// Khac CallScreen 1-1 o 3 cho:
/// - remoteUid la 1 TAP, khong phai 1 nguoi duy nhat.
/// - 1 nguoi roi khoi chi xoa o cua nguoi do, khong ket thuc
///   cuoc goi cho ca nhom.
/// - Chi nguoi tao bam ket thuc moi ket thuc cho tat ca; nguoi
///   khac bam ket thuc chi roi khoi.
/// Nut ket thuc dung cung cach sua loi PopScope nhu CallScreen:
/// bat _canPop = true truoc, cho frame rebuild roi moi pop.
class GroupCallScreen extends StatefulWidget {
  final GroupCallItem call;
  final bool isCreator;
  const GroupCallScreen({
    super.key,
    required this.call,
    required this.isCreator,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  RtcEngine? _engine;
  bool _joined = false;
  final Set<int> _remoteUids = {};
  bool _micOn = true;
  late bool _camOn = widget.call.isVideo;
  late bool _speakerOn = widget.call.isVideo;
  Timer? _durationTimer;
  Timer? _statusTimer;
  int _seconds = 0;
  bool _closing = false;
  bool _canPop = false;
  List<GroupCallParticipant> _participants = [];

  String get _title => widget.isCreator
      ? 'Cuộc gọi nhóm của bạn'
      : 'Cuộc gọi nhóm · ${widget.call.creatorName}';

  @override
  void initState() {
    super.initState();
    CallService.inCall = true;
    _participants = widget.call.participants;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStatus(),
    );
    _startAgora();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _statusTimer?.cancel();
    if (!_closing) {
      CallService.inCall = false;
      unawaited(_releaseEngine());
    }
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_closing) return;
    try {
      final call = await GroupCallService().byId(widget.call.id);
      if (call == null) return;
      if (mounted) setState(() => _participants = call.participants);
      if (call.status == 'ended') _hangUp(updateRemote: false);
    } catch (_) {}
  }

  Future<void> _startAgora() async {
    try {
      final perms = await [
        Permission.microphone,
        if (widget.call.isVideo) Permission.camera,
      ].request();
      if (perms.values.any((s) => !s.isGranted)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần cấp quyền micro/camera để gọi nhóm'),
            ),
          );
        }
        _hangUp();
        return;
      }
      if (_closing || !mounted) return;
      final credentials = await RtcService.credentials(
        widget.call.id,
        isGroup: true,
      );
      if (_closing || !mounted) return;
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(
        RtcEngineContext(
          appId: credentials.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onTokenPrivilegeWillExpire: (connection, token) => _renewToken(),
          onRequestToken: (connection) => _renewToken(),
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) setState(() => _joined = true);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUids.add(remoteUid));
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) setState(() => _remoteUids.remove(remoteUid));
          },
        ),
      );
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      if (widget.call.isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }
      await engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
      if (_closing || !mounted) return;
      await engine.joinChannel(
        token: credentials.token,
        channelId: widget.call.id,
        uid: credentials.uid,
        options: ChannelMediaOptions(
          autoSubscribeVideo: widget.call.isVideo,
          autoSubscribeAudio: true,
          publishCameraTrack: widget.call.isVideo,
          publishMicrophoneTrack: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không vào được cuộc gọi nhóm: $e')),
        );
      }
      _hangUp();
    }
  }

  Future<void> _renewToken() async {
    if (_closing || !mounted) return;
    try {
      final credentials = await RtcService.credentials(
        widget.call.id,
        isGroup: true,
      );
      if (_closing || !mounted) return;
      await _engine?.renewToken(credentials.token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hangUp({bool updateRemote = true}) async {
    if (_closing) return;
    _closing = true;
    _durationTimer?.cancel();
    _statusTimer?.cancel();
    CallService.inCall = false;
    final engine = _engine;
    _engine = null;
    final isCreator = widget.isCreator;
    final id = widget.call.id;
    if (mounted) setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
    unawaited(() async {
      try {
        await engine?.leaveChannel();
      } catch (e) {
        debugPrint('Leave Agora: $e');
      } finally {
        try {
          await engine?.release();
        } catch (e) {
          debugPrint('Release Agora: $e');
        }
      }
    }());
    // Don dep sau khi pop da duoc len lich, de nut luon phan hoi ngay.
    try {
      if (updateRemote) {
        if (isCreator) {
          await GroupCallService().end(id);
        } else {
          await GroupCallService().leave(id);
        }
      }
    } catch (_) {}
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    try {
      await engine?.leaveChannel();
    } finally {
      await engine?.release();
    }
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _videoCell({int? remoteUid, bool isLocal = false}) {
    if (!widget.call.isVideo ||
        _engine == null ||
        !_joined ||
        (isLocal && !_camOn)) {
      return Container(
        color: Colors.grey.shade800,
        child: Center(
          child: Avatar(name: isLocal ? 'Bạn' : 'Người tham gia', radius: 32),
        ),
      );
    }
    if (isLocal) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _engine!,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: remoteUid),
        connection: RtcConnection(channelId: widget.call.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[_videoCell(isLocal: true)];
    for (final uid in _remoteUids) {
      cells.add(_videoCell(remoteUid: uid));
    }
    final accepted = _participants
        .where((p) => p.status == 'accepted')
        .toList();
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_closing) _hangUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _joined
                          ? '${accepted.length} người đang trong cuộc gọi · ${_fmt(_seconds)}'
                          : 'Đang kết nối...',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accepted.map((p) => p.userName).join(', '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _joined
                    ? GridView.count(
                        crossAxisCount: cells.length <= 2 ? 1 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        padding: const EdgeInsets.all(12),
                        children: cells,
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roundButton(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      onTap: () async {
                        await _engine?.muteLocalAudioStream(_micOn);
                        if (!mounted || _closing) return;
                        setState(() => _micOn = !_micOn);
                      },
                    ),
                    const SizedBox(width: 16),
                    if (widget.call.isVideo)
                      _roundButton(
                        icon: _camOn ? Icons.videocam : Icons.videocam_off,
                        onTap: () async {
                          await _engine?.muteLocalVideoStream(_camOn);
                          if (!mounted || _closing) return;
                          setState(() => _camOn = !_camOn);
                        },
                      ),
                    if (widget.call.isVideo) const SizedBox(width: 16),
                    _roundButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                      onTap: () async {
                        await _engine?.setEnableSpeakerphone(!_speakerOn);
                        if (!mounted || _closing) return;
                        setState(() => _speakerOn = !_speakerOn);
                      },
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _hangUp(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
