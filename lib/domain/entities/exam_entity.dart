/// An exam record persisted in the local database.
class ExamRecord {
  final int? id;
  final String examName;
  final int examDate;
  final String? subjectsJson;
  final double? totalScore;
  final double? studentScore;
  final String? rawOcrText;
  final String? analysisResultJson;
  final int createdAt;

  const ExamRecord({
    this.id,
    required this.examName,
    required this.examDate,
    this.subjectsJson,
    this.totalScore,
    this.studentScore,
    this.rawOcrText,
    this.analysisResultJson,
    required this.createdAt,
  });
}

/// Per-question detail within an exam record.
class ExamQuestionDetail {
  final int? id;
  final int examRecordId;
  final int questionNumber;
  final String? topic;
  final String? subTopic;
  final double? maxScore;
  final double? studentScore;
  final bool isWrong;
  final String? errorType;
  final String? knowledgeNodeIdsJson;

  const ExamQuestionDetail({
    this.id,
    required this.examRecordId,
    required this.questionNumber,
    this.topic,
    this.subTopic,
    this.maxScore,
    this.studentScore,
    this.isWrong = false,
    this.errorType,
    this.knowledgeNodeIdsJson,
  });
}
extension ExamRecordJson on ExamRecord {
  Map<String, dynamic> toJson() => {
        'id': id,
        'examName': examName,
        'examDate': examDate,
        'subjectsJson': subjectsJson,
        'totalScore': totalScore,
        'studentScore': studentScore,
        'rawOcrText': rawOcrText,
        'analysisResultJson': analysisResultJson,
        'createdAt': createdAt,
      };

  static ExamRecord fromJson(Map<String, dynamic> json) => ExamRecord(
        id: json['id'] as int?,
        examName: json['examName'] as String? ?? '',
        examDate: json['examDate'] as int? ?? 0,
        subjectsJson: json['subjectsJson'] as String?,
        totalScore: (json['totalScore'] as num?)?.toDouble(),
        studentScore: (json['studentScore'] as num?)?.toDouble(),
        rawOcrText: json['rawOcrText'] as String?,
        analysisResultJson: json['analysisResultJson'] as String?,
        createdAt: json['createdAt'] as int? ?? 0,
      );
}

extension ExamQuestionDetailJson on ExamQuestionDetail {
  Map<String, dynamic> toJson() => {
        'id': id,
        'examRecordId': examRecordId,
        'questionNumber': questionNumber,
        'topic': topic,
        'subTopic': subTopic,
        'maxScore': maxScore,
        'studentScore': studentScore,
        'isWrong': isWrong,
        'errorType': errorType,
        'knowledgeNodeIdsJson': knowledgeNodeIdsJson,
      };

  static ExamQuestionDetail fromJson(Map<String, dynamic> json) =>
      ExamQuestionDetail(
        id: json['id'] as int?,
        examRecordId: json['examRecordId'] as int? ?? 0,
        questionNumber: json['questionNumber'] as int? ?? 0,
        topic: json['topic'] as String?,
        subTopic: json['subTopic'] as String?,
        maxScore: (json['maxScore'] as num?)?.toDouble(),
        studentScore: (json['studentScore'] as num?)?.toDouble(),
        isWrong: json['isWrong'] as bool? ?? false,
        errorType: json['errorType'] as String?,
        knowledgeNodeIdsJson: json['knowledgeNodeIdsJson'] as String?,
      );
}
