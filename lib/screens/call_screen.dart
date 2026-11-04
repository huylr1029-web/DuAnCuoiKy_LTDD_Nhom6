import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/rtc_service.dart';
import '../models/app_user.dart';
import '../models/api_models.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/realtime_service.dart';
import '../widgets/avatar.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final AppUser peer;
  final bool isVideo;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peer,
    required this.isVideo,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RtcEngine? _engine;

  bool _joined = false;
  int? _remoteUid;
  bool _remoteVideoOff = false;

  bool _micOn = true;
  late bool _camOn = widget.isVideo;
  late bool _speakerOn = widget.isVideo;

  Timer? _durationTimer;
  Timer? _timeoutTimer;

  int _seconds = 0;
  bool _everConnected = false;

  StreamSubscription<CallItem>? _callSub;
  Timer? _statusTimer;
  bool _closing = false;
  // Ly do nut ket thuc khong hoat dong: PopScope ben duoi dat
  // canPop: false de chan nut Back cua he thong, nhung Flutter
  // cung chan ca Navigator.pop() goi tu nut ket thuc, nen man hinh
  // khong bao gio thoat du _hangUp() da chay. Giai phap: khi ket
  // thuc thi bat _canPop = true truoc, cho frame rebuild xong roi
  // moi pop, va pop truoc khi cho mang / Agora xong de nut luon
  // phan hoi ngay ca khi mang cham.
  bool _canPop = false;

  void _onCallStatus(String? status) {
    if (status == null || _closing) return;
    if (status == 'accepted') {
      _timeoutTimer?.cancel();
    }
    if (status == 'rejected' || status == 'ended' || status == 'missed') {
      _hangUp(status, updateRemote: false);
    }
  }

  Future<void> _checkCallStatus() async {
    if (_closing) return;
    try {
      final call = await CallService().callById(widget.callId);
      if (call != null) _onCallStatus(call.status);
    } catch (_) {
      // Polling loi thi bo qua luot nay, luot sau thu lai.
    }
  }

  @override
  void initState() {
    super.initState();

    CallService.inCall = true;

    // Realtime qua SignalR + poll 2 giay (thay cho Firestore snapshots).
    _callSub = RealtimeService().callStatusStream.listen((call) {
      if (call.id == widget.callId) _onCallStatus(call.status);
    });
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkCallStatus(),
    );

    if (widget.isCaller) {
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!_everConnected && !_closing) {
          _hangUp('missed');
        }
      });
    }

    _startAgora();
  }

  Future<void> _startAgora() async {
    try {
      final perms = await [
        Permission.microphone,
        if (widget.isVideo) Permission.camera,
      ].request();

      if (perms.values.any((status) => !status.isGranted)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần cấp quyền micro/camera để gọi')),
          );
        }

        _hangUp('ended');
        return;
      }

      if (_closing || !mounted) return;

      final credentials = await RtcService.credentials(widget.callId);
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
            if (mounted) {
              setState(() {
                _joined = true;
              });
            }
          },

          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted) return;

            setState(() {
              _remoteUid = remoteUid;
            });

            _onConnected();
          },

          onUserOffline: (connection, remoteUid, reason) {
            _hangUp('ended');
          },

          onRemoteVideoStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
                if (!mounted) return;

                setState(() {
                  _remoteVideoOff =
                      state == RemoteVideoState.remoteVideoStateStopped ||
                      reason ==
                          RemoteVideoStateReason
                              .remoteVideoStateReasonRemoteMuted;
                });
              },

          onError: (err, msg) {
            debugPrint('Agora error: $err $msg');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Agora lỗi $err: $msg. Kiểm tra App ID và chế độ xác thực token trên Agora Console.',
                  ),
                ),
              );
            }
          },
        ),
      );

      if (widget.isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }

      await engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);

      if (_closing || !mounted) return;

      await engine.joinChannel(
        token: credentials.token,
        channelId: widget.callId,
        uid: credentials.uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideo,
        ),
      );
    } catch (e) {
      debugPrint('Lỗi khởi tạo Agora: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không khởi tạo được cuộc gọi: $e')),
        );
      }
      _hangUp('ended');
    }
  }

  void _onConnected() {
    if (_everConnected) return;

    _everConnected = true;
    _timeoutTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  Future<void> _renewToken() async {
    if (_closing || !mounted) return;
    try {
      final credentials = await RtcService.credentials(widget.callId);
      if (_closing || !mounted) return;
      await _engine?.renewToken(credentials.token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hangUp(String reason, {bool updateRemote = true}) async {
    if (_closing) return;

    _closing = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();
    _statusTimer?.cancel();

    await _callSub?.cancel();

    // Lay truoc cac gia tri can cho viec don dep, roi pop ngay,
    // khong cho mang / Agora chan nut ket thuc.
    final engine = _engine;
    _engine = null;
    final callId = widget.callId;
    final peer = widget.peer;
    final isCaller = widget.isCaller;
    final isVideo = widget.isVideo;
    final seconds = _everConnected ? _seconds : null;
    CallService.inCall = false;

    if (mounted) {
      setState(() => _canPop = true);
      // Cho frame rebuild voi canPop = true roi moi pop, neu pop
      // ngay lap tuc thi PopScope cu van chan.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

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
    // Don dep chay nen sau khi da len lich pop, loi mang / Agora
    // chi in log, khong giu man hinh lai.
    try {
      if (updateRemote) {
        await CallService().updateStatus(callId, reason);
      }
      if (isCaller) {
        await ChatService().sendCallLog(
          peer,
          isVideo: isVideo,
          outcome: reason,
          seconds: seconds,
        );
      }
    } catch (e) {
      debugPrint('Lỗi khi kết thúc cuộc gọi: $e');
    }
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;

    if (engine == null) return;

    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      debugPrint('Lỗi giải phóng Agora: $e');
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _timeoutTimer?.cancel();
    _statusTimer?.cancel();

    _callSub?.cancel();

    if (!_closing) {
      _releaseEngine();
    }

    CallService.inCall = false;

    super.dispose();
  }

  void _toggleMic() {
    setState(() {
      _micOn = !_micOn;
    });

    _engine?.muteLocalAudioStream(!_micOn);
  }

  void _toggleCam() {
    setState(() {
      _camOn = !_camOn;
    });

    _engine?.muteLocalVideoStream(!_camOn);

    if (_camOn) {
      _engine?.startPreview();
    } else {
      _engine?.stopPreview();
    }
  }

  void _switchCamera() {
    _engine?.switchCamera();
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });

    _engine?.setEnableSpeakerphone(_speakerOn);
  }

  String get _statusText {
    if (_everConnected) {
      final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');

      final seconds = (_seconds % 60).toString().padLeft(2, '0');

      return '$minutes:$seconds';
    }

    return widget.isCaller ? 'Đang gọi...' : 'Đang kết nối...';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _hangUp('ended');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: widget.isVideo ? _videoLayout() : _audioLayout(),
      ),
    );
  }

  Widget _localView() {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _remoteView() {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: RtcConnection(channelId: widget.callId),
      ),
    );
  }

  Widget _peerPlaceholder() {
    return Container(
      color: const Color(0xFF1C1E21),
      alignment: Alignment.center,
      child: Avatar(
        name: widget.peer.name,
        imageUrl: widget.peer.avatarUrl,
        radius: 56,
      ),
    );
  }

  Widget _videoLayout() {
    final ready = _engine != null && _joined;
    final connected = _remoteUid != null;

    return Stack(
      children: [
        Positioned.fill(
          child: !ready
              ? _peerPlaceholder()
              : connected
              ? (_remoteVideoOff ? _peerPlaceholder() : _remoteView())
              : (_camOn ? _localView() : _peerPlaceholder()),
        ),

        if (ready && connected && _camOn)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            width: 110,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _localView(),
            ),
          ),

        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 6)],
                ),
              ),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 6)],
                ),
              ),
            ],
          ),
        ),

        Positioned(left: 0, right: 0, bottom: 40, child: _controls()),
      ],
    );
  }

  Widget _audioLayout() {
    return Container(
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

            Avatar(
              name: widget.peer.name,
              imageUrl: widget.peer.avatarUrl,
              radius: 60,
            ),

            const SizedBox(height: 20),

            Text(
              widget.peer.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _statusText,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (widget.isVideo) ...[
          _roundButton(Icons.cameraswitch, _switchCamera),
          _roundButton(
            _camOn ? Icons.videocam : Icons.videocam_off,
            _toggleCam,
            active: !_camOn,
          ),
        ] else
          _roundButton(
            _speakerOn ? Icons.volume_up : Icons.volume_down,
            _toggleSpeaker,
            active: _speakerOn,
          ),

        _roundButton(
          _micOn ? Icons.mic : Icons.mic_off,
          _toggleMic,
          active: !_micOn,
        ),

        _roundButton(
          Icons.call_end,
          () => _hangUp('ended'),
          color: Colors.red,
          size: 34,
        ),
      ],
    );
  }

  Widget _roundButton(
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
    Color? color,
    double size = 28,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CircleAvatar(
        radius: size,
        backgroundColor: color ?? (active ? Colors.white : Colors.white24),
        child: Icon(
          icon,
          color: color != null
              ? Colors.white
              : (active ? Colors.black : Colors.white),
          size: size * 0.9,
        ),
      ),
    );
  }
}
