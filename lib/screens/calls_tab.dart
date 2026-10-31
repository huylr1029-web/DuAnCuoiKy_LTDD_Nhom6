import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import 'call_screen.dart';
import '../theme.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});
  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  bool _outgoing = false;
  List<CallItem> _calls = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final calls = await CallService()
          .myCalls(direction: _outgoing ? 'outgoing' : 'incoming');
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _startCall(AppUser user, bool video) async {
    try {
      final id = await CallService().startCall(peer: user, isVideo: video);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CallScreen(
                  callId: id, peer: user, isVideo: video, isCaller: true)));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể gọi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Gọi đến')),
                ButtonSegment(value: true, label: Text('Gọi đi'))
              ],
              selected: {_outgoing},
              onSelectionChanged: (value) {
                setState(() => _outgoing = value.first);
                _load();
              })),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text('Không tải được lịch sử cuộc gọi: $_error'))
                : _calls.isEmpty
                    ? const EmptyState(icon: Icons.call_outlined, title: 'Chưa có cuộc gọi nào', subtitle: 'Lịch sử cuộc gọi đến và gọi đi sẽ hiện ở đây.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _calls.length,
                          itemBuilder: (_, i) {
                            final call = _calls[i];
                            final peerId = _outgoing
                                ? call.calleeId
                                : call.callerId;
                            final name = _outgoing
                                ? call.calleeName
                                : call.callerName;
                            final peer = AppUser(uid: peerId, name: name);
                            return Card(
                              child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primarySoft,
                                child: Icon(call.isVideo
                                  ? Icons.videocam_outlined
                                  : Icons.phone_outlined, color: AppColors.primary),
                              ),
                              title: Text(name),
                              subtitle: Text(
                                  '${_outgoing ? 'Gọi đi' : 'Gọi đến'} · ${call.status}'),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        tooltip: 'Gọi thoại',
                                        icon: const Icon(Icons.call),
                                        onPressed: () =>
                                            _startCall(peer, false)),
                                    IconButton(
                                        tooltip: 'Gọi video',
                                        icon: const Icon(Icons.videocam),
                                        onPressed: () =>
                                            _startCall(peer, true)),
                                  ]),
                            ),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}
