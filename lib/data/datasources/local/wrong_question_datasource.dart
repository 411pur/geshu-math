import '../../database/data_store.dart';
import '../../../domain/entities/wrong_question_entity.dart';

class WrongQuestionDataSource {
  final DataStore _store;
  WrongQuestionDataSource(this._store);
  List<WrongQuestion> getAllPaginated({int limit = 20, int offset = 0, String? subject, String? topic, int? difficultyLevel, bool? favoritedOnly}) =>
      _store.getWrongQuestions(limit: limit, offset: offset, subject: subject, topic: topic, difficultyLevel: difficultyLevel, favoritedOnly: favoritedOnly);
  WrongQuestion? getById(int id) => _store.getWrongQuestionById(id);
  int insert(WrongQuestion wq) => _store.insertWrongQuestion(wq);
  void delete(int id) => _store.deleteWrongQuestion(id);
  void updateMastery(int id, int mastery) => _store.updateWrongQuestionMastery(id, mastery);
  void toggleFavorite(int id) => _store.toggleFavorite(id);
  void updateTags(int id, List<String> tags) => _store.updateWrongQuestionTags(id, tags);
  void markPrinted(int id) => _store.markWrongQuestionPrinted(id);
  int count() => _store.wrongQuestionCount;
  int get favoritedCount => _store.favoritedCount;
}