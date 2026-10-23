// Model classes for Dify workflow responses.
// Plain Dart classes with manual fromJson/toJson — no code generation needed.

/// 安全解析字符串列表：字段缺失 / null / 非列表时返回空列表，不抛异常。
List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

class WrongQuestionGuidanceResponse {
  final GuidanceResult guidanceResult;
  final ProcessedQuestion processedQuestion;
  const WrongQuestionGuidanceResponse({required this.guidanceResult, required this.processedQuestion});
  factory WrongQuestionGuidanceResponse.fromJson(Map<String, dynamic> json) => WrongQuestionGuidanceResponse(
    guidanceResult: GuidanceResult.fromJson(json['guidance_result']),
    processedQuestion: ProcessedQuestion.fromJson(json['processed_question']));
  Map<String, dynamic> toJson() => {'guidance_result': guidanceResult.toJson(), 'processed_question': processedQuestion.toJson()};
}

class GuidanceResult {
  final String analysis, correctSolution, difficulty;
  final String errorType;
  final List<String> knowledgePoints, relatedConcepts;
  // 错题订正模板 7 段（兼容旧数据：缺失时为空串，用 analysis/correctSolution 兜底展示）
  final String title, correctAnswer, stepAnalysis, errorAnalysis, knowledgeReview, warning, variation, archive;
  const GuidanceResult({
    required this.analysis,
    required this.correctSolution,
    required this.knowledgePoints,
    required this.difficulty,
    required this.relatedConcepts,
    this.errorType = '',
    this.title = '',
    this.correctAnswer = '',
    this.stepAnalysis = '',
    this.errorAnalysis = '',
    this.knowledgeReview = '',
    this.warning = '',
    this.variation = '',
    this.archive = '',
  });
  factory GuidanceResult.fromJson(Map<String, dynamic> json) => GuidanceResult(
    analysis: json['analysis'] as String? ?? '',
    correctSolution: json['correct_solution'] as String? ?? '',
    knowledgePoints: _asStringList(json['knowledge_points']),
    difficulty: json['difficulty'] as String? ?? '',
    relatedConcepts: _asStringList(json['related_concepts']),
    errorType: json['error_type'] is String ? json['error_type'] as String : '',
    title: json['title'] as String? ?? '',
    correctAnswer: json['correct_answer'] as String? ?? '',
    stepAnalysis: json['step_analysis'] as String? ?? '',
    errorAnalysis: json['error_analysis'] as String? ?? '',
    knowledgeReview: json['knowledge_review'] as String? ?? '',
    warning: json['warning'] as String? ?? '',
    variation: json['variation'] as String? ?? '',
    archive: json['archive'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'analysis': analysis,
    'correct_solution': correctSolution,
    'knowledge_points': knowledgePoints,
    'difficulty': difficulty,
    'related_concepts': relatedConcepts,
    'error_type': errorType,
    'title': title,
    'correct_answer': correctAnswer,
    'step_analysis': stepAnalysis,
    'error_analysis': errorAnalysis,
    'knowledge_review': knowledgeReview,
    'warning': warning,
    'variation': variation,
    'archive': archive,
  };
}

class ProcessedQuestion {
  final String subject, topic, subTopic, questionText, keyConcept;
  final int difficultyLevel;
  final List<String> tags, knowledgeNodeIds;
  final List<String> options;
  const ProcessedQuestion({required this.subject, required this.topic, required this.subTopic, required this.questionText, required this.difficultyLevel, required this.keyConcept, required this.tags, required this.knowledgeNodeIds, this.options = const []});
  factory ProcessedQuestion.fromJson(Map<String, dynamic> json) => ProcessedQuestion(
    subject: json['subject'] as String? ?? '数学',
    topic: json['topic'] as String? ?? '',
    subTopic: json['sub_topic'] as String? ?? '',
    questionText: json['question_text'] as String? ?? '',
    difficultyLevel: (json['difficulty_level'] as num?)?.toInt() ?? 0,
    keyConcept: json['key_concept'] as String? ?? '',
    tags: _asStringList(json['tags']),
    knowledgeNodeIds: _asStringList(json['knowledge_node_ids']),
    options: _asStringList(json['options']));
  Map<String, dynamic> toJson() => {'subject': subject, 'topic': topic, 'sub_topic': subTopic, 'question_text': questionText, 'difficulty_level': difficultyLevel, 'key_concept': keyConcept, 'tags': tags, 'knowledge_node_ids': knowledgeNodeIds, 'options': options};
}

class ExamAnalysisResponse {
  final AnalysisResult analysisResult;
  final ProcessedExamRecord processedExamRecord;
  const ExamAnalysisResponse({required this.analysisResult, required this.processedExamRecord});
  factory ExamAnalysisResponse.fromJson(Map<String, dynamic> json) => ExamAnalysisResponse(
    analysisResult: AnalysisResult.fromJson(json['analysis_result']),
    processedExamRecord: ProcessedExamRecord.fromJson(json['processed_exam_record']));
  Map<String, dynamic> toJson() => {'analysis_result': analysisResult.toJson(), 'processed_exam_record': processedExamRecord.toJson()};
}

class AnalysisResult {
  final String overallAssessment, nextExamPrediction;
  final List<StrengthArea> strengthAreas;
  final List<WeaknessArea> weaknessAreas;
  final List<String> improvementSuggestions;
  const AnalysisResult({required this.overallAssessment, required this.strengthAreas, required this.weaknessAreas, required this.improvementSuggestions, required this.nextExamPrediction});
  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
    overallAssessment: json['overall_assessment'] as String,
    strengthAreas: (json['strength_areas'] as List).map((e) => StrengthArea.fromJson(e)).toList(),
    weaknessAreas: (json['weakness_areas'] as List).map((e) => WeaknessArea.fromJson(e)).toList(),
    improvementSuggestions: List<String>.from(json['improvement_suggestions']),
    nextExamPrediction: json['next_exam_prediction'] as String);
  Map<String, dynamic> toJson() => {'overall_assessment': overallAssessment, 'strength_areas': strengthAreas.map((e) => e.toJson()).toList(), 'weakness_areas': weaknessAreas.map((e) => e.toJson()).toList(), 'improvement_suggestions': improvementSuggestions, 'next_exam_prediction': nextExamPrediction};
}

class StrengthArea {
  final String topic, comment;
  final double scoreRate;
  const StrengthArea({required this.topic, required this.scoreRate, required this.comment});
  factory StrengthArea.fromJson(Map<String, dynamic> json) => StrengthArea(topic: json['topic'] as String, scoreRate: (json['score_rate'] as num).toDouble(), comment: json['comment'] as String);
  Map<String, dynamic> toJson() => {'topic': topic, 'score_rate': scoreRate, 'comment': comment};
}

class WeaknessArea {
  final String topic, comment;
  final double scoreRate;
  const WeaknessArea({required this.topic, required this.scoreRate, required this.comment});
  factory WeaknessArea.fromJson(Map<String, dynamic> json) => WeaknessArea(topic: json['topic'] as String, scoreRate: (json['score_rate'] as num).toDouble(), comment: json['comment'] as String);
  Map<String, dynamic> toJson() => {'topic': topic, 'score_rate': scoreRate, 'comment': comment};
}

class ProcessedExamRecord {
  final String examName, examDate;
  final List<String> subjects;
  final double totalScore, studentScore;
  final List<ExamQuestionItem> questionDetails;
  const ProcessedExamRecord({required this.examName, required this.examDate, required this.subjects, required this.totalScore, required this.studentScore, required this.questionDetails});
  factory ProcessedExamRecord.fromJson(Map<String, dynamic> json) => ProcessedExamRecord(
    examName: json['exam_name'] as String, examDate: json['exam_date'] as String,
    subjects: List<String>.from(json['subjects']), totalScore: (json['total_score'] as num).toDouble(),
    studentScore: (json['student_score'] as num).toDouble(),
    questionDetails: (json['question_details'] as List).map((e) => ExamQuestionItem.fromJson(e)).toList());
  Map<String, dynamic> toJson() => {'exam_name': examName, 'exam_date': examDate, 'subjects': subjects, 'total_score': totalScore, 'student_score': studentScore, 'question_details': questionDetails.map((e) => e.toJson()).toList()};
}

class ExamQuestionItem {
  final int questionNumber;
  final String topic, subTopic, errorType;
  final double maxScore, studentScore;
  final bool isWrong;
  final List<String> knowledgeNodeIds;
  const ExamQuestionItem({required this.questionNumber, required this.topic, required this.subTopic, required this.maxScore, required this.studentScore, required this.isWrong, required this.errorType, required this.knowledgeNodeIds});
  factory ExamQuestionItem.fromJson(Map<String, dynamic> json) => ExamQuestionItem(
    questionNumber: json['question_number'] as int, topic: json['topic'] as String, subTopic: json['sub_topic'] as String,
    maxScore: (json['max_score'] as num).toDouble(), studentScore: (json['student_score'] as num).toDouble(),
    isWrong: json['is_wrong'] as bool, errorType: json['error_type'] as String,
    knowledgeNodeIds: List<String>.from(json['knowledge_node_ids']));
  Map<String, dynamic> toJson() => {'question_number': questionNumber, 'topic': topic, 'sub_topic': subTopic, 'max_score': maxScore, 'student_score': studentScore, 'is_wrong': isWrong, 'error_type': errorType, 'knowledge_node_ids': knowledgeNodeIds};
}

class SmartQaResponse {
  final String answer;
  final List<Reference> references;
  final String? suggestedFollowup;
  const SmartQaResponse({required this.answer, this.references = const [], this.suggestedFollowup});
  factory SmartQaResponse.fromJson(Map<String, dynamic> json) => SmartQaResponse(
    answer: json['answer'] as String,
    references: (json['references'] as List?)?.map((e) => Reference.fromJson(e)).toList() ?? [],
    suggestedFollowup: json['suggested_followup'] as String?);
  Map<String, dynamic> toJson() => {'answer': answer, 'references': references.map((e) => e.toJson()).toList(), if (suggestedFollowup != null) 'suggested_followup': suggestedFollowup};
}

class Reference {
  final String title, source;
  const Reference({required this.title, required this.source});
  factory Reference.fromJson(Map<String, dynamic> json) => Reference(title: json['title'] as String, source: json['source'] as String);
  Map<String, dynamic> toJson() => {'title': title, 'source': source};
}
