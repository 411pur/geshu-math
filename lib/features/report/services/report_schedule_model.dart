/// 学习报告定时模型与纯判定逻辑（无 dart:html 依赖，可在 VM 中单测）。
library;

/// 学习报告定时模型。
class ReportSchedule {
  final bool enabled;
  final String frequency; // daily / weekly / interval
  final int weekday; // 1=周一..7=周日（frequency=weekly 时使用）
  final int intervalDays; // 每N天（frequency=interval 时使用）
  final int hour;
  final int minute;

  const ReportSchedule({
    this.enabled = false,
    this.frequency = 'daily',
    this.weekday = 1,
    this.intervalDays = 3,
    this.hour = 20,
    this.minute = 0,
  });

  factory ReportSchedule.fromJson(Map<String, dynamic> j) => ReportSchedule(
    enabled: j['enabled'] as bool? ?? false,
    frequency: (j['frequency'] as String?) ?? 'daily',
    weekday: (j['weekday'] as num?)?.toInt() ?? 1,
    intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 3,
    hour: (j['hour'] as num?)?.toInt() ?? 20,
    minute: (j['minute'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled, 'frequency': frequency, 'weekday': weekday,
    'intervalDays': intervalDays, 'hour': hour, 'minute': minute,
  };

  /// 下次触发时间描述
  String describe() {
    final hm = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    switch (frequency) {
      case 'daily': return '每天 $hm';
      case 'weekly': return '每周${weekdayCn(weekday)} $hm';
      case 'interval': return '每$intervalDays天 $hm';
      default: return hm;
    }
  }

  static String weekdayCn(int w) => const ['一','二','三','四','五','六','日'][w - 1];
}

/// 定时触发的纯判定逻辑（与存储解耦，便于测试）。
class ReportScheduleLogic {
  ReportScheduleLogic._();

  /// 到点触发（页面运行中的定时器用）：当前时刻命中目标分钟窗口 ±1，
  /// 且本周期尚未发送。
  static bool isDueNow(ReportSchedule s, DateTime now, DateTime? lastSent) {
    if (!s.enabled) return false;
    final nowMinutes = now.hour * 60 + now.minute;
    final targetMinutes = s.hour * 60 + s.minute;
    if (nowMinutes < targetMinutes || nowMinutes > targetMinutes + 1) return false;

    final today = DateTime(now.year, now.month, now.day);
    if (lastSent != null && today.isAtSameMomentAs(DateTime(lastSent.year, lastSent.month, lastSent.day))) {
      return false;
    }

    switch (s.frequency) {
      case 'daily': return true;
      case 'weekly': return now.weekday == s.weekday;
      case 'interval':
        if (lastSent == null) return true;
        return today.difference(DateTime(lastSent.year, lastSent.month, lastSent.day)).inHours >=
            s.intervalDays * 24;
      default: return false;
    }
  }

  /// 登录/打开页面时的补发：定时已开启 + 本周期目标时刻已过 + 本周期未发送
  /// → 应补发（错过定时器窗口也能在下次进入时补上）。
  static bool shouldTriggerMissed(
      ReportSchedule s, DateTime now, DateTime? lastSent) {
    if (!s.enabled) return false;
    final target = DateTime(now.year, now.month, now.day, s.hour, s.minute);
    if (now.isBefore(target)) return false; // 还没到点，等定时器到点触发
    final today = DateTime(now.year, now.month, now.day);
    switch (s.frequency) {
      case 'daily':
        if (lastSent == null) return true;
        return !today.isAtSameMomentAs(DateTime(lastSent.year, lastSent.month, lastSent.day));
      case 'weekly':
        if (now.weekday != s.weekday) return false;
        if (lastSent == null) return true;
        // 本周一（含）之后发过则跳过
        final weekStart = today.subtract(Duration(days: now.weekday - 1));
        return lastSent.isBefore(weekStart);
      case 'interval':
        if (lastSent == null) return true;
        return today.difference(DateTime(lastSent.year, lastSent.month, lastSent.day)).inDays >=
            s.intervalDays;
      default: return false;
    }
  }
}