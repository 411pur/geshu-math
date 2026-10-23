/// App-wide constants for 格数至理 (AI 数学答疑与学习分析系统).
class AppConstants {
  AppConstants._();

  static const String appName = '格数至理';
  static const String appVersion = '0.1.0';

  /// Supported grade levels (初一 ~ 高三).
  static const List<String> supportedGrades = [
    '初一',
    '初二',
    '初三',
    '高一',
    '高二',
    '高三',
  ];

  /// 初高中数学模块分类，贯穿全应用的学科标签。
  static const Map<String, String> subjectCategories = {
    'number_algebra': '数与代数',
    'functions': '函数',
    'geometry': '图形与几何',
    'statistics_probability': '统计与概率',
    'derivatives': '导数与微积分',
    'sequences': '数列',
    'vectors': '向量',
    'coordinate_geometry': '解析几何',
    'solid_geometry': '立体几何',
    'inequalities': '不等式',
  };
}
