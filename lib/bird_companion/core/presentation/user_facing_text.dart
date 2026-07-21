/// Converts values used by the box and recognition service into language that
/// a photographer can understand without knowing algorithm terminology.
abstract final class UserFacingText {
  static String recognitionCertainty(double value) {
    if (value >= .85) return '很有把握';
    if (value >= .65) return '比较有把握';
    if (value >= .45) return '不太确定';
    return '仅供参考';
  }

  static String recognitionCertaintyWithPercent(double value) =>
      '${recognitionCertainty(value)}（${(value * 100).round()}%）';

  static String analysisState(String? value) => switch (value) {
    'completed' => '识别完成',
    'processing' => '正在识别',
    'low_confidence' => '识别结果不确定',
    'failed' => '未能完成识别',
    _ => value ?? '',
  };
}
