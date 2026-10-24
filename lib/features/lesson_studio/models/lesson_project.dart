enum LessonProjectStatus { queued, running, done, warning, failed }

enum LessonProjectStage {
  queued,
  extracting,
  solving,
  verifying,
  planning,
  rendering,
  visualCheck,
  repairing,
  done,
  failed,
}

enum LessonVisualStatus { notChecked, passed, warning }

extension LessonProjectStatusJson on LessonProjectStatus {
  String get wire => switch (this) {
    LessonProjectStatus.queued => 'queued',
    LessonProjectStatus.running => 'running',
    LessonProjectStatus.done => 'done',
    LessonProjectStatus.warning => 'warning',
    LessonProjectStatus.failed => 'failed',
  };

  static LessonProjectStatus parse(Object? value) =>
      LessonProjectStatus.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => LessonProjectStatus.queued,
      );
}

extension LessonProjectStageJson on LessonProjectStage {
  String get wire => switch (this) {
    LessonProjectStage.visualCheck => 'visual_check',
    _ => name,
  };
}

extension LessonVisualStatusJson on LessonVisualStatus {
  String get wire => switch (this) {
    LessonVisualStatus.notChecked => 'not_checked',
    LessonVisualStatus.passed => 'passed',
    LessonVisualStatus.warning => 'warning',
  };

  static LessonVisualStatus parse(Object? value) =>
      LessonVisualStatus.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => LessonVisualStatus.notChecked,
      );
}

class LessonProjectRecord {
  final String id, title, subject, inputText, refKind, externalProjectId;
  final int refId;
  final DateTime createdAt, updatedAt;
  final LessonProjectStatus status;
  final LessonProjectStage stage;
  final double progress;
  final String message, error;
  final LessonVisualStatus visualStatus;
  final List<String> visualWarnings;
  final int renderAttempts;
  final bool hasHtml;

  const LessonProjectRecord({
    required this.id,
    required this.title,
    this.subject = '',
    this.inputText = '',
    this.refKind = '',
    this.externalProjectId = '',
    this.refId = 0,
    required this.createdAt,
    required this.updatedAt,
    this.status = LessonProjectStatus.queued,
    this.stage = LessonProjectStage.queued,
    this.progress = 0,
    this.message = '',
    this.error = '',
    this.visualStatus = LessonVisualStatus.notChecked,
    this.visualWarnings = const [],
    this.renderAttempts = 0,
    this.hasHtml = false,
  });

  factory LessonProjectRecord.fromJson(
    Map<String, dynamic> m,
  ) => LessonProjectRecord(
    id: _string(m['id'], 'id', max: 80),
    title: _string(m['title'], 'title', fallback: '未命名题目', max: 200),
    subject: _string(m['subject'], 'subject', max: 80),
    inputText: _string(m['inputText'], 'inputText', max: 20000),
    refKind: _string(m['refKind'], 'refKind', max: 40),
    externalProjectId: _string(
      m['externalProjectId'],
      'externalProjectId',
      max: 80,
    ),
    refId: _int(m['refId'], 'refId'),
    createdAt:
        DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(m['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    status: LessonProjectStatusJson.parse(m['status']),
    stage: LessonProjectStage.values.firstWhere(
      (e) => e.wire == m['stage'],
      orElse: () => LessonProjectStage.queued,
    ),
    progress: _double(m['progress'], 'progress', min: 0, max: 100),
    message: _string(m['message'], 'message', max: 500),
    error: _string(m['error'], 'error', max: 2000),
    visualStatus: LessonVisualStatusJson.parse(m['visualStatus']),
    visualWarnings: _strings(m['visualWarnings'], 'visualWarnings', max: 30),
    renderAttempts: _int(
      m['renderAttempts'],
      'renderAttempts',
      min: 0,
      max: 10,
    ),
    hasHtml: _bool(m['hasHtml'], 'hasHtml'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'inputText': inputText,
    'refKind': refKind,
    'externalProjectId': externalProjectId,
    'refId': refId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.wire,
    'stage': stage.wire,
    'progress': progress,
    'message': message,
    'error': error,
    'visualStatus': visualStatus.wire,
    'visualWarnings': visualWarnings,
    'renderAttempts': renderAttempts,
    'hasHtml': hasHtml,
  };

  LessonProjectRecord copyWith({
    String? title,
    String? subject,
    String? externalProjectId,
    DateTime? updatedAt,
    LessonProjectStatus? status,
    LessonProjectStage? stage,
    double? progress,
    String? message,
    String? error,
    LessonVisualStatus? visualStatus,
    List<String>? visualWarnings,
    int? renderAttempts,
    bool? hasHtml,
  }) => LessonProjectRecord(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    inputText: inputText,
    refKind: refKind,
    externalProjectId: externalProjectId ?? this.externalProjectId,
    refId: refId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    message: message ?? this.message,
    error: error ?? this.error,
    visualStatus: visualStatus ?? this.visualStatus,
    visualWarnings: visualWarnings ?? this.visualWarnings,
    renderAttempts: renderAttempts ?? this.renderAttempts,
    hasHtml: hasHtml ?? this.hasHtml,
  );
}

class LessonProgressEvent {
  final LessonProjectStage stage;
  final double progress;
  final String message;
  final int attempt;

  const LessonProgressEvent({
    required this.stage,
    required this.progress,
    required this.message,
    this.attempt = 0,
  });
}

String _string(
  Object? value,
  String name, {
  String fallback = '',
  int max = 1000,
}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  return text.length <= max ? text : text.substring(0, max);
}

int _int(Object? value, String name, {int fallback = 0, int? min, int? max}) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? fallback;
  var result = parsed;
  if (min != null && result < min) result = min;
  if (max != null && result > max) result = max;
  return result;
}

double _double(
  Object? value,
  String name, {
  double fallback = 0,
  double? min,
  double? max,
}) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? fallback;
  var result = parsed;
  if (min != null && result < min) result = min;
  if (max != null && result > max) result = max;
  return result;
}

bool _bool(Object? value, String name, {bool fallback = false}) {
  if (value is bool) return value;
  if (value?.toString().toLowerCase() == 'true') return true;
  if (value?.toString().toLowerCase() == 'false') return false;
  return fallback;
}

List<String> _strings(Object? value, String name, {int max = 20}) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .take(max)
      .toList();
}
