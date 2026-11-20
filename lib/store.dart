import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'parser.dart';

const int kSchemaVersion = 1;
const String kBackupFormat = 'training_memo_backup';

/// アプリ全体のデータ（端末内のJSONファイルに保存）
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  late File _file;
  Profile profile = Profile(heightCm: 189.3, weightKg: 88.0);
  final Map<String, DayRecord> records = {};
  StepSource stepSource = StepSource.healthConnect;

  /// 未保存の下書き（日付 → 項目）。保存ボタンを押すまで記録には反映しない
  final Map<String, Map<String, String>> drafts = {};

  void setDraft(String date, Map<String, String>? d) {
    if (d == null) {
      if (drafts.remove(date) == null) return;
    } else {
      drafts[date] = d;
    }
    scheduleSave();
  }

  /// 端末センサー計測用の状態
  Map<String, dynamic> sensorState = {};

  Timer? _saveTimer;

  /// 記録画面以外でデータが変更されたときに増える（記録画面の再読み込み用）
  final ValueNotifier<int> externalRev = ValueNotifier(0);
  void bumpExternal() => externalRev.value++;
  bool loaded = false;

  Future<void> load({Directory? directory}) async {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/training_memo_data.json');
    if (await _file.exists()) {
      try {
        final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        _applyJson(j, replace: true);
        // 起動時に前回データの控えを作る（破損時の保険）
        await _file.copy('${dir.path}/training_memo_data.prev.json');
      } catch (_) {
        // 破損している場合は控えから復元を試みる
        final prev = File('${dir.path}/training_memo_data.prev.json');
        if (await prev.exists()) {
          try {
            _applyJson(jsonDecode(await prev.readAsString()) as Map<String, dynamic>,
                replace: true);
          } catch (_) {}
        }
      }
    } else {
      _seedDummy();
      await saveNow();
    }
    loaded = true;
    notifyListeners();
  }

  void _seedDummy() {
    profile = Profile(heightCm: 189.3, weightKg: 88.0);
    final sample = DayRecord(
      date: '2026-11-10',
      title: '試合前A',
      menu: 'RPD 90@4 90@4 RPDW 45@5✕\n'
          'PSQ 175@2  175@2\n'
          'BSQ 130@2 130@2\n'
          'DBBP 34@4 34@4',
      condition: '疲労度：3/5\n睡眠：7時間\nサプリ：プロテイン、クレアチン5g',
      weightKg: 88.0,
      steps: 8200,
      stepsSource: StepSource.manual.name,
    );
    records[sample.date] = sample;
  }

  // ---------- 永続化 ----------

  Map<String, dynamic> toJson() => {
        'format': kBackupFormat,
        'version': kSchemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': profile.toJson(),
        'settings': {'stepSource': stepSource.name},
        'sensorState': sensorState,
        'drafts': drafts,
        'records': records.values.map((r) => r.toJson()).toList()
          ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String)),
      };

  void _applyJson(Map<String, dynamic> j, {required bool replace}) {
    if (replace) {
      records.clear();
      if (j['profile'] is Map) {
        profile = Profile.fromJson(Map<String, dynamic>.from(j['profile']));
      }
      final s = j['settings'];
      if (s is Map) stepSource = stepSourceFrom(s['stepSource'] as String?);
      drafts.clear();
      final dr = j['drafts'];
      if (dr is Map) {
        dr.forEach((k, v) {
          if (v is Map) drafts['$k'] = v.map((a, b) => MapEntry('$a', '$b'));
        });
      }
      if (j['sensorState'] is Map) {
        sensorState = Map<String, dynamic>.from(j['sensorState']);
      }
    }
    final list = j['records'];
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final r = DayRecord.fromJson(Map<String, dynamic>.from(e));
        if (replace) {
          records[r.date] = r;
        } else {
          final cur = records[r.date];
          if (cur == null || cur.isEmpty || r.updatedAt.isAfter(cur.updatedAt)) {
            records[r.date] = r;
          }
        }
      }
    }
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(toJson()),
        flush: true);
    await tmp.rename(_file.path);
  }

  // ---------- バックアップ ----------

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// バックアップJSONを検証して件数を返す。不正なら例外（日本語メッセージ）
  int validateBackup(String text) {
    final dynamic j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('JSONとして読み込めませんでした。ファイルが壊れている可能性があります。');
    }
    if (j is! Map || j['format'] != kBackupFormat) {
      throw const FormatException('このアプリのバックアップファイルではありません。');
    }
    final list = j['records'];
    if (list is! List) throw const FormatException('記録データが見つかりませんでした。');
    return list.length;
  }

  Future<void> importJson(String text, {required bool replace}) async {
    validateBackup(text);
    final j = Map<String, dynamic>.from(jsonDecode(text) as Map);
    _applyJson(j, replace: replace);
    _parseCache.clear();
    await saveNow();
    bumpExternal();
    notifyListeners();
  }

  // ---------- 記録の操作 ----------

  DayRecord? recordFor(DateTime d) => records[dateKey(d)];

  DayRecord ensureRecord(DateTime d) =>
      records.putIfAbsent(dateKey(d), () => DayRecord(date: dateKey(d)));

  void touch(DayRecord r, {bool notify = true}) {
    r.updatedAt = DateTime.now();
    scheduleSave();
    if (notify) notifyListeners();
  }

  void deleteRecord(String date) {
    records.remove(date);
    scheduleSave();
    bumpExternal();
    notifyListeners();
  }

  void restoreRecord(DayRecord r) {
    records[r.date] = r;
    scheduleSave();
    bumpExternal();
    notifyListeners();
  }

  /// 新しい順（中身がある記録のみ）
  List<DayRecord> get sortedRecords {
    final l = records.values.where((r) => !r.isEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return l;
  }

  List<DayRecord> get trainingRecords =>
      sortedRecords.where((r) => r.hasTraining).toList();

  /// その日の体重（記録がなければ、それ以前の直近の体重 → プロフィール）
  double weightOn(DateTime d) {
    final r = recordFor(d);
    if (r?.weightKg != null) return r!.weightKg!;
    final key = dateKey(d);
    final prev = records.values
        .where((x) => x.weightKg != null && x.date.compareTo(key) < 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (prev.isNotEmpty) return prev.first.weightKg!;
    return profile.weightKg;
  }

  void setWeight(DateTime d, double? kg) {
    final r = ensureRecord(d);
    r.weightKg = kg;
    if (kg != null && !d.isBefore(_latestWeightDate())) {
      profile.weightKg = kg;
    }
    touch(r);
  }

  DateTime _latestWeightDate() {
    final l = records.values.where((x) => x.weightKg != null).map((x) => x.date).toList()
      ..sort();
    return l.isEmpty ? DateTime(1970) : parseDateKey(l.last);
  }

  void setProfile({required double heightCm, required double weightKg}) {
    profile.heightCm = heightCm;
    profile.weightKg = weightKg;
    final r = ensureRecord(today());
    r.weightKg = weightKg;
    touch(r);
    bumpExternal();
  }

  void setSteps(DateTime d, int? steps, StepSource source) {
    final r = ensureRecord(d);
    if (r.steps == steps && r.stepsSource == source.name) return;
    r.steps = steps;
    r.stepsSource = source.name;
    touch(r);
  }

  void setStepSource(StepSource s) {
    stepSource = s;
    scheduleSave();
    notifyListeners();
  }

  // ---------- 履歴の活用 ----------

  final Map<String, ({String menu, ParsedWorkout parsed})> _parseCache = {};

  ParsedWorkout parsedOf(DayRecord r) {
    final c = _parseCache[r.date];
    if (c != null && c.menu == r.menu) return c.parsed;
    final p = parseWorkout(r.menu);
    _parseCache[r.date] = (menu: r.menu, parsed: p);
    return p;
  }

  /// 過去記録に登場した種目名（よく使う順）
  List<String> frequentExercises({int limit = 16}) {
    final count = <String, int>{};
    final lastSeen = <String, String>{};
    for (final r in records.values) {
      if (r.menu.trim().isEmpty) continue;
      for (final e in parsedOf(r).exercises) {
        if (e.sets.isEmpty) continue;
        count[e.name] = (count[e.name] ?? 0) + 1;
        if ((lastSeen[e.name] ?? '').compareTo(r.date) < 0) lastSeen[e.name] = r.date;
      }
    }
    final names = count.keys.toList()
      ..sort((a, b) {
        final c = count[b]!.compareTo(count[a]!);
        return c != 0 ? c : lastSeen[b]!.compareTo(lastSeen[a]!);
      });
    return names.take(limit).toList();
  }

  /// 指定日より前で、その種目を行った直近の記録
  ({String date, ExerciseEntry entry})? previousExercise(String name, DateTime before) {
    final key = dateKey(before);
    final list = records.values
        .where((r) => r.date.compareTo(key) < 0 && r.menu.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final r in list) {
      final merged = ExerciseEntry(name);
      for (final e in parsedOf(r).exercises) {
        if (e.name == name) merged.sets.addAll(e.sets);
      }
      if (merged.sets.isNotEmpty) return (date: r.date, entry: merged);
    }
    return null;
  }

  /// 種目ごとの全履歴（新しい順）
  List<({String date, ExerciseEntry entry})> exerciseHistory(String name) {
    final out = <({String date, ExerciseEntry entry})>[];
    for (final r in sortedRecords) {
      if (r.menu.trim().isEmpty) continue;
      final merged = ExerciseEntry(name);
      for (final e in parsedOf(r).exercises) {
        if (e.name == name) merged.sets.addAll(e.sets);
      }
      if (merged.sets.isNotEmpty) out.add((date: r.date, entry: merged));
    }
    return out;
  }
}
