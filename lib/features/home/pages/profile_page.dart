import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/student_profile_provider.dart';
import '../providers/student_provider.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';

/// 「我的」页面：学生头像 + 名字 + 学习报告 / 设置入口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(studentProfileProvider);
    final studentId = ref.watch(studentIdProvider);
    final displayName = profile.name.isNotEmpty
        ? profile.name
        : (studentId.isNotEmpty ? studentId : '未设置');

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 头像 + 名字 ──────────────────────────────
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _pickAvatar(context, ref),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        backgroundImage: profile.hasAvatar
                            ? MemoryImage(
                                base64Decode(
                                  profile.avatarBase64.split(',').last,
                                ),
                              )
                            : null,
                        child: profile.hasAvatar
                            ? null
                            : const Icon(
                                Icons.person,
                                size: 52,
                                color: AppColors.primary,
                              ),
                      ),
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: '修改名字',
                      onPressed: () => _editName(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 入口列表 ──────────────────────────────────
          Card(
            child: Column(
              children: [
                _MotionListTile(
                  leading: const Icon(Icons.assessment_outlined),
                  title: const Text('学习报告'),
                  subtitle: const Text('生成你的学习报告'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/report'),
                ),
                const Divider(height: 1, indent: 56),
                _MotionListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('设置'),
                  subtitle: const Text('修改各板块的 AI 配置与提示词'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            _MotionListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (ref.read(studentProfileProvider).hasAvatar)
              _MotionListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除头像'),
                onTap: () {
                  ref.read(studentProfileProvider.notifier).setAvatar('');
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;
    final b64 = await _toAvatarBase64(image);
    if (b64 != null) ref.read(studentProfileProvider.notifier).setAvatar(b64);
  }

  /// 把图片压缩为方形小图 base64（头像用，约 200px）。
  Future<String?> _toAvatarBase64(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      const size = 200.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        decoded,
        Rect.fromLTWH(
          0,
          0,
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final img = await recorder.endRecording().toImage(
        size.round(),
        size.round(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return 'data:image/png;base64,${base64Encode(byteData.buffer.asUint8List())}';
    } catch (e) {
      return null;
    }
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final current = ref.read(studentProfileProvider);
    final ctrl = TextEditingController(text: current.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改名字'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入名字'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      ref.read(studentProfileProvider.notifier).setName(newName);
    }
  }
}

class _MotionListTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MotionListTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressScale(
      pressedScale: 0.864,
      hoverScale: 1.01,
      enabled: onTap != null,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
