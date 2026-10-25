import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/data/datasources/remote/dify_response_models.dart';

Map<String, dynamic> _payload() => {
  'analysis_result': {
    'overall_assessment': '基础稳定，导数需要加强。',
    'strength_areas': [
      {'topic': '函数', 'score_rate': 0.82, 'comment': '计算准确'},
    ],
    'weakness_areas': [
      {'topic': '导数', 'score_rate': 0.55, 'comment': '单调性判断不熟练'},
    ],
    'improvement_suggestions': ['每天完成一道导数单调性题'],
    'next_exam_prediction': '目标得分 120',
  },
  'processed_exam_record': {
    'exam_name': '十月月考',
    'exam_date': '2026-10-25',
    'subjects': ['数学'],
    'total_score': 150,
    'student_score': 108,
    'question_details': [
      {
        'question_number': 1,
        'topic': '函数',
        'sub_topic': '单调性',
        'max_score': 5,
        'student_score': 3,
        'is_wrong': false,
        'error_type': '步骤不完整',
        'knowledge_node_ids': ['function-monotonicity'],
      },
    ],
  },
};

void main() {
  test('考试分析 JSON 可以完整解析并再次序列化', () {
    final response = ExamAnalysisResponse.fromJson(_payload());
    expect(response.analysisResult.overallAssessment, contains('导数'));
    expect(response.analysisResult.strengthAreas.single.scoreRate, 0.82);
    expect(response.processedExamRecord.examName, '十月月考');
    expect(response.processedExamRecord.studentScore, 108);
    expect(
      response.processedExamRecord.questionDetails.single.questionNumber,
      1,
    );
    final roundTrip = ExamAnalysisResponse.fromJson(response.toJson());
    expect(
      roundTrip.processedExamRecord.questionDetails.single.errorType,
      '步骤不完整',
    );
  });
}
