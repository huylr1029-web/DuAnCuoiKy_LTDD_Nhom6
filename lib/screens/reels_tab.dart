import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../models/api_models.dart';
import '../services/reels_service.dart';
import '../theme.dart';

class ReelsTab extends StatefulWidget {
  const ReelsTab({super.key});
  @override
  State<ReelsTab> createState() => _ReelsTabState();
}

class _ReelsTabState extends State<ReelsTab> {
  final _reels = ReelsService();
  List<ReelItem> _posts = [];
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
      final posts = await _reels.list();
      if (!mounted) return;
      setState(() {
        _posts = posts;
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

  Future<void> _createPost() async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const _CreateReelScreen()));
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đăng ảnh kèm nhạc thành công')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('Không tải được Reels: $_error',
                            textAlign: TextAlign.center)))
                : _posts.isEmpty
                    ? const EmptyState(
                        icon: Icons.video_library_outlined,
                        title: 'Chưa có bài đăng',
                        subtitle: 'Nhấn + để đăng ảnh kèm nhạc đầu tiên.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                            itemCount: _posts.length,
                            itemBuilder: (_, index) => _ReelCard(
                                key: ValueKey(_posts[index].id),
                                data: _posts[index])),
                      ),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _createPost,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Đăng Reels')),
      );
}

class _ReelCard extends StatefulWidget {
  final ReelItem data;
  const _ReelCard({super.key, required this.data});
  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard> {
  final _player = AudioPlayer();
  bool _playing = false;
  late ReelItem _data = widget.data;
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final wasLiked = _data.likedByMe;
    setState(() {
      _data = _data.copyWith(
          likedByMe: !wasLiked, likeCount: _data.likeCount + (wasLiked ? -1 : 1));
    });
    try {
      if (wasLiked) {
        await ReelsService().unlike(_data.id);
      } else {
        await ReelsService().like(_data.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _data = _data.copyWith(
              likedByMe: wasLiked, likeCount: _data.likeCount + (wasLiked ? 1 : -1));
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showComments() async {
    final comments = await ReelsService().comments(_data.id);
    if (!mounted) return;
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(children: [
              Text('Bình luận (${comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: comments.isEmpty
                    ? const Center(child: Text('Chưa có bình luận.'))
                    : ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(comments[i].authorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(comments[i].text),
                        ),
                      ),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'Viết bình luận...', border: OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    try {
                      final added = await ReelsService().addComment(_data.id, text);
                      setSheetState(() => comments.insert(0, added));
                      controller.clear();
                      if (mounted) {
                        setState(() => _data = _data.copyWith(commentCount: _data.commentCount + 1));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        final url = widget.data.musicUrl ?? '';
        if (url.isEmpty) return;
        if (_player.audioSource == null) await _player.setUrl(url);
        unawaited(_player.play());
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi phát nhạc: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _data.imageUrl;
    final music = _data.musicUrl ?? '';
    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundImage: _data.authorAvatarUrl.isEmpty ? null : NetworkImage(_data.authorAvatarUrl),
                      child: _data.authorAvatarUrl.isEmpty ? Text(_data.authorName.isEmpty ? '?' : _data.authorName[0].toUpperCase()) : null,
                    ),
                    const SizedBox(width: 10),
                    Text(_data.authorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ])),
              if (image.isNotEmpty)
                AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.network(image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('Không tải được ảnh')))),
              if (_data.caption.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_data.caption)),
              if (music.isNotEmpty)
                ListTile(
                  leading: IconButton(
                      icon: Icon(
                          _playing ? Icons.pause_circle : Icons.play_circle),
                      onPressed: _toggle),
                  title: Text(_data.musicName ?? 'Âm nhạc',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Nhấn để phát/tạm dừng nhạc'),
                ),
              Row(children: [
                TextButton.icon(
                  onPressed: _toggleLike,
                  icon: Icon(_data.likedByMe ? Icons.favorite : Icons.favorite_border,
                      color: _data.likedByMe ? Colors.red : null),
                  label: Text('${_data.likeCount} Thích'),
                ),
                TextButton.icon(
                  onPressed: _showComments,
                  icon: const Icon(Icons.comment_outlined),
                  label: Text('${_data.commentCount} Bình luận'),
                ),
              ]),
            ]));
  }
}

class _CreateReelScreen extends StatefulWidget {
  const _CreateReelScreen();
  @override
  State<_CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<_CreateReelScreen> {
  final _caption = TextEditingController();
  final _reels = ReelsService();
  XFile? _image;
  PlatformFile? _audio;
  bool _uploading = false;
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (mounted) setState(() => _image = file);
  }

  Future<void> _pickMusic() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: true);
    if (mounted && result != null && result.files.isNotEmpty) {
      setState(() => _audio = result.files.first);
    }
  }

  Future<void> _publish() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hãy chọn một ảnh')));
      return;
    }
    setState(() => _uploading = true);
    try {
      await _reels.create(
        image: _image!,
        music: _audio,
        caption: _caption.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Không đăng được Reels: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Đăng ảnh kèm nhạc')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: Text(_image == null
                          ? 'Chọn ảnh từ điện thoại'
                          : 'Đã chọn: ${_image!.name}')),
                  OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickMusic,
                      icon: const Icon(Icons.music_note),
                      label: Text(_audio == null
                          ? 'Thêm nhạc từ thiết bị (không bắt buộc)'
                          : _audio!.name)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _caption,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Chú thích',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: _uploading ? null : _publish,
                      icon: _uploading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                          _uploading ? 'Đang tải lên...' : 'Đăng bài')),
                  const SizedBox(height: 12),
                  const Text(
                      'Chỉ đăng nhạc bạn có quyền sử dụng. Ảnh và âm thanh được lưu trên server ASP.NET (wwwroot/uploads), không còn Firebase Storage.'),
                ])),
      );
}
