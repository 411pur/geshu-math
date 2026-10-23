import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_provider.dart';
import '../../../data/database/db_provider.dart';
import '../../../data/datasources/local/exam_datasource.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../domain/entities/exam_entity.dart';

final examDataSourceProvider = Provider<ExamDataSource>((ref) {
  final store = ref.watch(dataStoreProvider);
  return ExamDataSource(store);
});

final examRepositoryProvider = Provider<ExamRepository>((ref) {
  final ds = ref.watch(examDataSourceProvider);
  final ai = ref.watch(aiApiClientProvider);
  return ExamRepository(ds, ai);
});

final examHistoryProvider = FutureProvider<List<ExamRecord>>((ref) async {
  final repo = ref.watch(examRepositoryProvider);
  return repo.getHistory();
});

final examDetailProvider = FutureProvider.family<ExamRecord?, int>((ref, id) async {
  final repo = ref.watch(examRepositoryProvider);
  return repo.getRecordById(id);
});

final examQuestionDetailsProvider = FutureProvider.family<List<ExamQuestionDetail>, int>((ref, recordId) async {
  final repo = ref.watch(examRepositoryProvider);
  return repo.getDetailsForRecord(recordId);
});