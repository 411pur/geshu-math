import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../data/lesson_frame_policy.dart';

/// 互动讲解播放器：把引擎生成的单文件 HTML 塞进 iframe，并用 postMessage 双向通信。
///
/// 这里用 package:web 而不是已废弃的 dart:html。两处注意点：
///  * package:web 不提供 Dart Stream，事件要用 addEventListener + JS 函数，
///    dispose 时必须用同一个 JSFunction 引用反注册，否则监听器会泄漏；
///  * 跨边界的数据要用 jsify/dartify 显式转换。
class LessonPlayerPage extends StatefulWidget {
  final String htmlText;
  final String title;
  const LessonPlayerPage({
    super.key,
    required this.htmlText,
    required this.title,
  });
  @override
  State<LessonPlayerPage> createState() => _LessonPlayerPageState();
}

class _LessonPlayerPageState extends State<LessonPlayerPage> {
  late final String _dataUrl;
  late final String _viewType;
  web.HTMLIFrameElement? _frame;
  web.EventListener? _messageListener;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _dataUrl = Uri.dataFromString(
      widget.htmlText,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();
    _viewType = 'lesson-player-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = _dataUrl
        // data: URL 的子帧是 opaque origin，fullscreen 的默认 allowlist 只放行同源帧：
        // 不放行的话子帧 document.fullscreenEnabled 为 false，黑板上的「全屏黑板」
        // 会被权限策略直接拒掉、点了没反应。allow 与 allowfullscreen 按规范是「或」，
        // 两个都写上，老一点的实现只认后者。
        ..allow = kLessonFrameAllow
        ..allowFullscreen = true
        ..width = '100%'
        ..height = '100%'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      _frame = frame;
      return frame;
    });
    // 讲解 HTML 会回传播放状态，App 顶栏按钮据此保持同步。
    _messageListener = ((web.MessageEvent event) {
      _onLessonMessage(event);
    }).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  @override
  void dispose() {
    final listener = _messageListener;
    if (listener != null) {
      web.window.removeEventListener('message', listener);
      _messageListener = null;
    }
    super.dispose();
  }

  void _onLessonMessage(web.MessageEvent event) {
    final data = event.data.dartify();
    if (data is! Map) return;
    if (data['__lessonStudioStatus'] != true) return;
    // 讲解页里的「全屏黑板」被宿主权限策略拦下时会主动回传，别让学生以为按钮坏了。
    if (data['fullscreen'] == 'blocked') {
      _reportFullscreenBlocked('${data['reason'] ?? ''}');
    }
    final playing = data['isPlaying'] == true;
    if (mounted && playing != _playing) {
      setState(() => _playing = playing);
    }
  }

  /// 内嵌帧被权限策略拦下全屏时，提示学生换一种打开方式。
  void _reportFullscreenBlocked(String reason) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final detail = reason.trim();
    messenger.showSnackBar(
      SnackBar(
        content: Text(detail.isEmpty
            ? '内嵌播放器不允许全屏：点右上角「浏览器新窗口打开」后按 F 全屏'
            : '内嵌播放器不允许全屏（$detail）：点右上角「浏览器新窗口打开」后按 F 全屏'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _post(String kind) {
    _frame?.contentWindow?.postMessage(
      <String, Object?>{'__lessonStudio': true, 'kind': kind}.jsify(),
      '*'.toJS,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: _playing ? '暂停老师讲课' : '开始老师讲课',
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
            onPressed: _togglePlay,
          ),
          IconButton(
            tooltip: '重新讲一遍',
            icon: const Icon(Icons.replay),
            onPressed: () => _post('replay'),
          ),
          IconButton(
            tooltip: '下载 HTML',
            icon: const Icon(Icons.download),
            onPressed: () => _download(widget.title, widget.htmlText),
          ),
          IconButton(
            tooltip: '浏览器新窗口打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => web.window.open(_dataUrl, '_blank'),
          ),
        ],
      ),
      body: kIsWeb
          ? SingleChildScrollView(
              child: SizedBox(
                height: 720,
                width: double.infinity,
                child: HtmlElementView(viewType: _viewType),
              ),
            )
          : const Center(child: Text('互动讲解首版仅支持 Flutter Web')),
    );
  }

  void _togglePlay() {
    final next = !_playing;
    setState(() => _playing = next);
    _post(next ? 'play' : 'pause');
  }

  /// 把讲解 HTML 存成单文件下载。
  static void _download(String title, String htmlText) {
    final blob = web.Blob(
      <JSAny>[htmlText.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = '${_safe(title)}.html'
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  static String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return safe.isEmpty ? '互动讲解' : safe;
  }
}