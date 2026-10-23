import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/db_provider.dart';
import '../../../domain/entities/wrong_question_entity.dart';

/// Full library, including records beyond the list page's pagination limit.
final analyticsQuestionsProvider = Provider.autoDispose<List<WrongQuestion>>((
  ref,
) {
  final store = ref.watch(dataStoreProvider);
  void refresh() => ref.invalidateSelf();
  store.wrongQuestionRevision.addListener(refresh);
  ref.onDispose(() => store.wrongQuestionRevision.removeListener(refresh));
  return store.getWrongQuestions(limit: store.wrongQuestionCount);
});
