import '../../database/data_store.dart';
import '../../../domain/entities/exam_entity.dart';

class ExamDataSource {
  final DataStore _store;
  ExamDataSource(this._store);
  List<ExamRecord> getAllHistory({int limit = 20, int offset = 0}) => _store.getExamRecords(limit: limit, offset: offset);
  ExamRecord? getRecordById(int id) => _store.getExamRecordById(id);
  int insertRecord(ExamRecord record) => _store.insertExamRecord(record);
  List<ExamQuestionDetail> getDetailsForRecord(int recordId) => _store.getExamDetailsByRecordId(recordId);
  void insertDetails(List<ExamQuestionDetail> details) => _store.insertExamDetails(details);
}