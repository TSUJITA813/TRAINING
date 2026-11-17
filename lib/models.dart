import 'package:intl/intl.dart';

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDateKey(String k) => DateFormat('yyyy-MM-dd').parse(k);
DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];
String weekdayJa(DateTime d) => _weekdays[d.weekday - 1];
String fmtDateJa(DateTime d) =>
    '${DateFormat('yyyy/MM/dd').format(d)}（${weekdayJa(d)}）';
String fmtDateShort(DateTime d) =>
    '${DateFormat('M/d').format(d)}（${weekdayJa(d)}）';

class DayRecord {
  final String date; // yyyy-MM-dd
  String title;
  String menu;
  String condition;
  double? weightKg;
  int? steps;
  String? stepsSource; // healthConnect / sensor / manual
  DateTime updatedAt;

  DayRecord({
    required this.date,
    this.title = '',
    this.menu = '',
    this.condition = '',
    this.weightKg,
    this.steps,
    this.stepsSource,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  DateTime get dateTime => parseDateKey(date);

  bool get hasTraining => menu.trim().isNotEmpty || title.trim().isNotEmpty;
  bool get isEmpty =>
      menu.trim().isEmpty &&
      title.trim().isEmpty &&
      condition.trim().isEmpty &&
      weightKg == null &&
      steps == null;

  Map<String, dynamic> toJson() => {
        'date': date,
        'title': title,
        'menu': menu,
        'condition': condition,
        'weightKg': weightKg,
        'steps': steps,
        'stepsSource': stepsSource,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DayRecord.fromJson(Map<String, dynamic> j) => DayRecord(
        date: j['date'] as String,
        title: (j['title'] ?? '') as String,
        menu: (j['menu'] ?? '') as String,
        condition: (j['condition'] ?? '') as String,
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        steps: (j['steps'] as num?)?.toInt(),
        stepsSource: j['stepsSource'] as String?,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String),
      );
}

class Profile {
  double heightCm;
  double weightKg;
  Profile({required this.heightCm, required this.weightKg});

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  Map<String, dynamic> toJson() => {'heightCm': heightCm, 'weightKg': weightKg};
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        heightCm: (j['heightCm'] as num?)?.toDouble() ?? 189.3,
        weightKg: (j['weightKg'] as num?)?.toDouble() ?? 88.0,
      );
}

enum StepSource { healthConnect, sensor, manual }

extension StepSourceLabel on StepSource {
  String get label => switch (this) {
        StepSource.healthConnect => 'ヘルスコネクト連携（推奨）',
        StepSource.sensor => '端末の歩数センサー（アプリ単体）',
        StepSource.manual => '手入力のみ',
      };
  String get shortLabel => switch (this) {
        StepSource.healthConnect => 'ヘルスコネクト',
        StepSource.sensor => '端末センサー',
        StepSource.manual => '手入力',
      };
}

StepSource stepSourceFrom(String? s) => StepSource.values
    .firstWhere((e) => e.name == s, orElse: () => StepSource.healthConnect);

/// 歩行による消費カロリーの概算（kcal）
/// 歩幅 = 身長 × 0.45、消費 ≒ 体重(kg) × 距離(km) × 0.5
double walkingKcal(int steps, double heightCm, double weightKg) {
  final km = steps * heightCm * 0.45 / 100 / 1000;
  return weightKg * km * 0.5;
}

double walkingKm(int steps, double heightCm) =>
    steps * heightCm * 0.45 / 100 / 1000;
