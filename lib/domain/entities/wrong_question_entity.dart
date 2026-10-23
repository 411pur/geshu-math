/// A wrong-question entry persisted in the local database.
class WrongQuestion {
  final int? id;
  final String subject;
  final String? topic;
  final String? subTopic;
  final String questionText;
  final String? questionImagePath;
  final String? guidanceResultJson;
  final int difficultyLevel;
  final String? keyConcept;
  final String? knowledgeNodeId;
  final String? tagsJson;
  final int reviewCount;
  final int? lastReviewedAt;
  final int createdAt;
  final int mastery; // 0=未掌握 1=复习中 2=已掌握
  final int printedAt; // 0=未打印, >0=上次打印时间戳
  final bool isFavorited; // 是否收藏

  const WrongQuestion({
    this.id,
    this.subject = '数学',
    this.topic,
    this.subTopic,
    required this.questionText,
    this.questionImagePath,
    this.guidanceResultJson,
    this.difficultyLevel = 2,
    this.keyConcept,
    this.knowledgeNodeId,
    this.tagsJson,
    this.reviewCount = 0,
    this.lastReviewedAt,
    required this.createdAt,
    this.mastery = 0,
    this.printedAt = 0,
    this.isFavorited = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'subTopic': subTopic,
        'questionText': questionText,
        'questionImagePath': questionImagePath,
        'guidanceResultJson': guidanceResultJson,
        'difficultyLevel': difficultyLevel,
        'keyConcept': keyConcept,
        'knowledgeNodeId': knowledgeNodeId,
        'tagsJson': tagsJson,
        'reviewCount': reviewCount,
        'lastReviewedAt': lastReviewedAt,
        'createdAt': createdAt,
        'mastery': mastery,
        'printedAt': printedAt,
        'isFavorited': isFavorited,
      };

  factory WrongQuestion.fromJson(Map<String, dynamic> json) => WrongQuestion(
        id: json['id'] as int?,
        subject: json['subject'] as String? ?? '数学',
        topic: json['topic'] as String?,
        subTopic: json['subTopic'] as String?,
        questionText: json['questionText'] as String? ?? '',
        questionImagePath: json['questionImagePath'] as String?,
        guidanceResultJson: json['guidanceResultJson'] as String?,
        difficultyLevel: json['difficultyLevel'] as int? ?? 2,
        keyConcept: json['keyConcept'] as String?,
        knowledgeNodeId: json['knowledgeNodeId'] as String?,
        tagsJson: json['tagsJson'] as String?,
        reviewCount: json['reviewCount'] as int? ?? 0,
        lastReviewedAt: json['lastReviewedAt'] as int?,
        createdAt: json['createdAt'] as int? ?? 0,
        mastery: json['mastery'] as int? ?? 0,
        printedAt: json['printedAt'] as int? ?? 0,
        isFavorited: json['isFavorited'] as bool? ?? false,
      );
}