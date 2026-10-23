import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/knowledge_entity.dart';
import '../../domain/entities/wrong_question_entity.dart';
import '../../domain/entities/exam_entity.dart';

/// Simple in-memory data store that works on all platforms (web, mobile, desktop).
///
/// Knowledge nodes are loaded from the seed JSON on initialization.
/// Wrong questions and exam records are stored in memory (lists).
class DataStore {
  static const _wqKey = 'wrong_questions';
  static const _examKey = 'exam_records';
  static const _examDetailKey = 'exam_details';

  // ── Knowledge ────────────────────────────────────────────
  List<KnowledgeNode> _knowledgeNodes = [];

  // ── Wrong Questions ─────────────────────────────────────
  final List<WrongQuestion> _wrongQuestions = [];
  final wrongQuestionRevision = ValueNotifier<int>(0);
  int _nextWqId = 1;

  // ── Exam Records ────────────────────────────────────────
  final List<ExamRecord> _examRecords = [];
  final List<ExamQuestionDetail> _examDetails = [];
  int _nextExamId = 1;
  int _nextDetailId = 1;

  // ── Initialization ──────────────────────────────────────

  /// Load seed data from the assets JSON. Idempotent.
  Future<void> initialize() async {
    if (_knowledgeNodes.isNotEmpty) return;
    final raw = await rootBundle.loadString('assets/knowledge/initial_knowledge_structure.json');
    final list = json.decode(raw) as List<dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    _knowledgeNodes = list.map((e) {
      final m = e as Map<String, dynamic>;
      return KnowledgeNode(
        id: m['id'] as String,
        parentId: m['parentId'] as String?,
        title: m['title'] as String,
        description: m['description'] as String?,
        level: m['level'] as int,
        sortOrder: m['sortOrder'] as int? ?? 0,
        source: m['source'] as String? ?? 'static',
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
    _loadFromStorage();
  }

  // ── localStorage Persistence ──────────────────────────────────

  void _loadFromStorage() {
    try {
      final raw = web.window.localStorage.getItem(_wqKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List<dynamic>;
        _wrongQuestions.clear();
        for (final item in list) {
          _wrongQuestions.add(WrongQuestion.fromJson(item as Map<String, dynamic>));
        }
        _nextWqId = _wrongQuestions.fold(1, (max, w) => (w.id ?? 0) >= max ? (w.id! + 1) : max);
      }
    } catch (_) {}
    try {
      final raw = web.window.localStorage.getItem(_examKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List<dynamic>;
        _examRecords.clear();
        for (final item in list) {
          _examRecords.add(ExamRecordJson.fromJson(item as Map<String, dynamic>));
        }
        _nextExamId = _examRecords.fold(1, (max, e) => (e.id ?? 0) >= max ? (e.id! + 1) : max);
      }
    } catch (_) {}
    try {
      final raw = web.window.localStorage.getItem(_examDetailKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List<dynamic>;
        _examDetails.clear();
        for (final item in list) {
          _examDetails.add(ExamQuestionDetailJson.fromJson(item as Map<String, dynamic>));
        }
        _nextDetailId = _examDetails.fold(1, (max, d) => (d.id ?? 0) >= max ? (d.id! + 1) : max);
      }
    } catch (_) {}
  }

  void _saveWqToStorage() {
    try {
      web.window.localStorage.setItem(_wqKey, json.encode(_wrongQuestions.map((w) => w.toJson()).toList()));
    } catch (_) {}
    wrongQuestionRevision.value++;
  }

  void _saveExamsToStorage() {
    try {
      web.window.localStorage.setItem(_examKey, json.encode(_examRecords.map((e) => e.toJson()).toList()));
      web.window.localStorage.setItem(_examDetailKey, json.encode(_examDetails.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  // ── Knowledge Queries ───────────────────────────────────

  List<KnowledgeNode> getAllNodes() => List.unmodifiable(_knowledgeNodes);

  List<KnowledgeNode> getRootNodes() =>
      _knowledgeNodes.where((n) => n.parentId == null).toList();

  List<KnowledgeNode> getChildrenOf(String parentId) =>
      _knowledgeNodes.where((n) => n.parentId == parentId).toList();

  KnowledgeNode? getNodeById(String id) =>
      _knowledgeNodes.where((n) => n.id == id).firstOrNull;

  List<KnowledgeNode> searchNodes(String query) =>
      _knowledgeNodes.where((n) => n.title.contains(query)).take(20).toList();

  /// Add a node (from Dify enrichment). Dedup by id.
  void addNode(KnowledgeNode node) {
    _knowledgeNodes.removeWhere((n) => n.id == node.id);
    _knowledgeNodes.add(node);
  }

  int get nodeCount => _knowledgeNodes.length;

  // ── Wrong Question Queries ──────────────────────────────

  List<WrongQuestion> getWrongQuestions({
    int limit = 20,
    int offset = 0,
    String? subject,
    String? topic,
    int? difficultyLevel,
    bool? favoritedOnly,
  }) {
    var result = _wrongQuestions.reversed.toList();
    if (subject != null) result = result.where((w) => w.subject == subject).toList();
    if (topic != null) result = result.where((w) => w.topic == topic).toList();
    if (difficultyLevel != null) result = result.where((w) => w.difficultyLevel == difficultyLevel).toList();
    if (favoritedOnly == true) result = result.where((w) => w.isFavorited).toList();
    return result.skip(offset).take(limit).toList();
  }

  int get favoritedCount => _wrongQuestions.where((w) => w.isFavorited).length;

  WrongQuestion? getWrongQuestionById(int id) =>
      _wrongQuestions.where((w) => w.id == id).firstOrNull;

  int insertWrongQuestion(WrongQuestion wq) {
    final id = _nextWqId++;
    _wrongQuestions.add(WrongQuestion(
      id: id,
      subject: wq.subject,
      topic: wq.topic,
      subTopic: wq.subTopic,
      questionText: wq.questionText,
      questionImagePath: wq.questionImagePath,
      guidanceResultJson: wq.guidanceResultJson,
      difficultyLevel: wq.difficultyLevel,
      keyConcept: wq.keyConcept,
      knowledgeNodeId: wq.knowledgeNodeId,
      tagsJson: wq.tagsJson,
      reviewCount: wq.reviewCount,
      lastReviewedAt: wq.lastReviewedAt,
      createdAt: wq.createdAt,
      isFavorited: wq.isFavorited,
    ));
    _saveWqToStorage();
    return id;
  }

  int get wrongQuestionCount => _wrongQuestions.length;

  void deleteWrongQuestion(int id) {
    _wrongQuestions.removeWhere((w) => w.id == id);
    _saveWqToStorage();
  }

  void markWrongQuestionPrinted(int id) {
    _updateById(id, (w) => WrongQuestion(
      id: w.id, subject: w.subject, topic: w.topic, subTopic: w.subTopic,
      questionText: w.questionText, questionImagePath: w.questionImagePath,
      guidanceResultJson: w.guidanceResultJson, difficultyLevel: w.difficultyLevel,
      keyConcept: w.keyConcept, knowledgeNodeId: w.knowledgeNodeId,
      tagsJson: w.tagsJson, reviewCount: w.reviewCount, lastReviewedAt: w.lastReviewedAt,
      createdAt: w.createdAt, mastery: w.mastery, isFavorited: w.isFavorited,
      printedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _saveWqToStorage();
  }

  void updateWrongQuestionMastery(int id, int mastery) {
    _updateById(id, (w) => WrongQuestion(
      id: w.id, subject: w.subject, topic: w.topic, subTopic: w.subTopic,
      questionText: w.questionText, questionImagePath: w.questionImagePath,
      guidanceResultJson: w.guidanceResultJson, difficultyLevel: w.difficultyLevel,
      keyConcept: w.keyConcept, knowledgeNodeId: w.knowledgeNodeId,
      tagsJson: w.tagsJson, reviewCount: w.reviewCount, lastReviewedAt: w.lastReviewedAt,
      createdAt: w.createdAt, mastery: mastery, isFavorited: w.isFavorited,
      printedAt: w.printedAt,
    ));
    _saveWqToStorage();
  }

  void toggleFavorite(int id) {
    _updateById(id, (w) => WrongQuestion(
      id: w.id, subject: w.subject, topic: w.topic, subTopic: w.subTopic,
      questionText: w.questionText, questionImagePath: w.questionImagePath,
      guidanceResultJson: w.guidanceResultJson, difficultyLevel: w.difficultyLevel,
      keyConcept: w.keyConcept, knowledgeNodeId: w.knowledgeNodeId,
      tagsJson: w.tagsJson, reviewCount: w.reviewCount, lastReviewedAt: w.lastReviewedAt,
      createdAt: w.createdAt, mastery: w.mastery, isFavorited: !w.isFavorited,
      printedAt: w.printedAt,
    ));
    _saveWqToStorage();
  }

  void updateWrongQuestionTags(int id, List<String> tags) {
    _updateById(id, (w) => WrongQuestion(
      id: w.id, subject: w.subject, topic: w.topic, subTopic: w.subTopic,
      questionText: w.questionText, questionImagePath: w.questionImagePath,
      guidanceResultJson: w.guidanceResultJson, difficultyLevel: w.difficultyLevel,
      keyConcept: w.keyConcept, knowledgeNodeId: w.knowledgeNodeId,
      tagsJson: json.encode(tags), reviewCount: w.reviewCount, lastReviewedAt: w.lastReviewedAt,
      createdAt: w.createdAt, mastery: w.mastery, isFavorited: w.isFavorited,
      printedAt: w.printedAt,
    ));
    _saveWqToStorage();
  }

  void _updateById(int id, WrongQuestion Function(WrongQuestion) updater) {
    for (var i = 0; i < _wrongQuestions.length; i++) {
      if (_wrongQuestions[i].id == id) {
        _wrongQuestions[i] = updater(_wrongQuestions[i]);
        break;
      }
    }
  }

  // ── Exam Record Queries ─────────────────────────────────

  List<ExamRecord> getExamRecords({int limit = 20, int offset = 0}) {
    final sorted = _examRecords.reversed.toList();
    return sorted.skip(offset).take(limit).toList();
  }

  ExamRecord? getExamRecordById(int id) =>
      _examRecords.where((r) => r.id == id).firstOrNull;

  int insertExamRecord(ExamRecord record) {
    final id = _nextExamId++;
    _examRecords.add(ExamRecord(
      id: id,
      examName: record.examName,
      examDate: record.examDate,
      subjectsJson: record.subjectsJson,
      totalScore: record.totalScore,
      studentScore: record.studentScore,
      rawOcrText: record.rawOcrText,
      analysisResultJson: record.analysisResultJson,
      createdAt: record.createdAt,
    ));
    _saveExamsToStorage();
    return id;
  }

  void insertExamDetails(List<ExamQuestionDetail> details) {
    for (final d in details) {
      final id = _nextDetailId++;
      _examDetails.add(ExamQuestionDetail(
        id: id,
        examRecordId: d.examRecordId,
        questionNumber: d.questionNumber,
        topic: d.topic,
        subTopic: d.subTopic,
        maxScore: d.maxScore,
        studentScore: d.studentScore,
        isWrong: d.isWrong,
        errorType: d.errorType,
        knowledgeNodeIdsJson: d.knowledgeNodeIdsJson,
      ));
    }
    _saveExamsToStorage();
  }

  List<ExamQuestionDetail> getExamDetailsByRecordId(int recordId) =>
      _examDetails.where((d) => d.examRecordId == recordId).toList();
}
