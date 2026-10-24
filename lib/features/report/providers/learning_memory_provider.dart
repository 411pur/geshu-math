import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;
import '../models/learning_memory.dart';

export '../models/learning_memory.dart';

class LearningMemoryNotifier extends Notifier<LearningMemory> {
  static const storageKey = 'geshu_math_learning_memory_v1';
  @override
  LearningMemory build() {
    try {
      return LearningMemory.fromJson(
        jsonDecode(web.window.localStorage.getItem(storageKey) ?? '{}'),
      );
    } catch (_) {
      return const LearningMemory();
    }
  }

  // Persist before publishing: a quota/storage failure must not look like success.
  void _save(LearningMemory next) {
    web.window.localStorage.setItem(storageKey, jsonEncode(next.toJson()));
    state = next;
  }

  void record(
    int questionId,
    PracticeOutcome outcome, {
    required bool viewedExplanation,
  }) {
    final now = DateTime.now();
    final records = [
      ...state.records,
      PracticeRecord(
        id: '${now.microsecondsSinceEpoch}-$questionId',
        questionId: questionId,
        at: now.millisecondsSinceEpoch,
        outcome: viewedExplanation && outcome == PracticeOutcome.independent
            ? PracticeOutcome.prompted
            : outcome,
        viewedExplanation: viewedExplanation,
      ),
    ];
    _save(
      LearningMemory(
        records: records.length > 500
            ? records.sublist(records.length - 500)
            : records,
        preference: state.preference,
      ),
    );
  }

  void remove(String id) => _save(
    LearningMemory(
      records: state.records.where((r) => r.id != id).toList(),
      preference: state.preference,
    ),
  );

  void setPreference(String value) {
    if (!LearningMemory.preferences.contains(value)) return;
    _save(LearningMemory(records: state.records, preference: value));
  }
}

final learningMemoryProvider =
    NotifierProvider<LearningMemoryNotifier, LearningMemory>(
      LearningMemoryNotifier.new,
    );
