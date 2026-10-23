import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_provider.dart';
import '../../../data/database/db_provider.dart';
import '../../../data/datasources/local/wrong_question_datasource.dart';
import '../../../data/repositories/wrong_question_repository.dart';
import '../../../domain/entities/wrong_question_entity.dart';

final wrongQuestionDataSourceProvider = Provider<WrongQuestionDataSource>((ref) {
  final store = ref.watch(dataStoreProvider);
  return WrongQuestionDataSource(store);
});

final wrongQuestionRepositoryProvider = Provider<WrongQuestionRepository>((ref) {
  final ds = ref.watch(wrongQuestionDataSourceProvider);
  final ai = ref.watch(aliyunApiClientProvider);
  return WrongQuestionRepository(ds, ai);
});

final wrongQuestionsProvider = FutureProvider.family<List<WrongQuestion>, WrongQuestionFilter>((ref, filter) async {
  final repo = ref.watch(wrongQuestionRepositoryProvider);
  return repo.getList(limit: filter.limit, offset: filter.offset, subject: filter.subject, topic: filter.topic, difficultyLevel: filter.difficultyLevel);
});

final wrongQuestionDetailProvider = FutureProvider.family<WrongQuestion?, int>((ref, id) async {
  final repo = ref.watch(wrongQuestionRepositoryProvider);
  return repo.getById(id);
});

final wrongQuestionCountProvider = FutureProvider<int>((ref) async {
  final ds = ref.watch(wrongQuestionDataSourceProvider);
  return ds.count();
});

class WrongQuestionFilter {
  final int limit, offset;
  final String? subject, topic;
  final int? difficultyLevel;
  const WrongQuestionFilter({this.limit = 20, this.offset = 0, this.subject, this.topic, this.difficultyLevel});
  @override bool operator ==(Object other) => identical(this, other) || other is WrongQuestionFilter && limit == other.limit && offset == other.offset && subject == other.subject && topic == other.topic && difficultyLevel == other.difficultyLevel;
  @override int get hashCode => Object.hash(limit, offset, subject, topic, difficultyLevel);
}