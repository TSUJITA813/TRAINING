import 'models.dart';
import 'parser.dart';
import 'store.dart';

/// AI・トレーナー共有用の日報テキストを生成する
String buildShareText(DateTime day) {
  final store = AppStore.instance;
  final r = store.recordFor(day);
  final p = store.profile;
  final weight = store.weightOn(day);
  final b = StringBuffer();

  b.writeln('【トレーニング日報】${fmtDateJa(day)}');
  b.writeln();
  b.writeln('■ 身体データ');
  b.writeln('身長：${fmtNum(p.heightCm)}cm');
  b.writeln('体重：${weight.toStringAsFixed(1)}kg'
      '${r?.weightKg == null ? '（直近の記録値）' : ''}');
  final bmi = weight / ((p.heightCm / 100) * (p.heightCm / 100));
  b.writeln('BMI：${bmi.toStringAsFixed(1)}');
  if (r?.steps != null) {
    final s = r!.steps!;
    b.writeln('歩数：${fmtKg(s.toDouble())}歩'
        '（約${walkingKm(s, p.heightCm).toStringAsFixed(1)}km、'
        '歩行消費 約${walkingKcal(s, p.heightCm, weight).round()}kcal）');
  } else {
    b.writeln('歩数：未記録');
  }
  b.writeln();

  b.writeln('■ トレーニングメニュー${(r?.title.trim().isNotEmpty ?? false) ? '：${r!.title.trim()}' : ''}');
  if (r == null || r.menu.trim().isEmpty) {
    b.writeln('（記録なし／休養日）');
  } else {
    final w = parseWorkout(r.menu);
    for (final line in exerciseLines(w)) {
      b.writeln(line);
    }
    if (w.totalVolume > 0) {
      b.writeln('合計：${w.totalSets}セット／総挙上量 ${fmtKg(w.totalVolume)}kg');
    }
  }
  b.writeln();

  b.writeln('■ コンディション・栄養メモ');
  b.writeln((r?.condition.trim().isNotEmpty ?? false) ? r!.condition.trim() : '（記入なし）');
  return b.toString().trimRight();
}

/// 連続する同じ内容のセットを「×2セット」のようにまとめた表記
String compactSetLabels(ExerciseEntry e) {
  final parts = <String>[];
  SetEntry? prev;
  var n = 0;
  void flush() {
    if (prev == null) return;
    final p = prev;
    final w = p.weight == null ? '自重' : '${fmtNum(p.weight!)}kg';
    parts.add('$w×${p.reps}回${n > 1 ? '×$nセット' : ''}${p.failed ? '（失敗）' : ''}');
  }

  for (final s in e.sets) {
    if (prev != null && prev.weight == s.weight && prev.reps == s.reps && prev.failed == s.failed) {
      n += s.count;
    } else {
      flush();
      prev = s;
      n = s.count;
    }
  }
  flush();
  return parts.join('、');
}

/// 種目ごとの整形済みの行（「・種目：90kg×4回×2セット」）
List<String> exerciseLines(ParsedWorkout w) => [
      for (final e in w.exercises)
        '・${e.name}：${compactSetLabels(e)}${e.notes.isEmpty ? '' : '（${e.notes.join('、')}）'}',
      for (final n in w.notes) '※$n',
    ];

/// コピー用：【メニュー名】日付 ＋ 整形済みのトレーニング内容のみ
String buildMenuText(DayRecord r) {
  final title = r.title.trim().isNotEmpty ? r.title.trim() : (parseWorkout(r.menu).title ?? '');
  final head = title.isEmpty ? fmtDateJa(r.dateTime) : '【$title】${fmtDateJa(r.dateTime)}';
  final lines = exerciseLines(parseWorkout(r.menu));
  return [head, ...lines].join('\n');
}

/// 複数日分をまとめる（古い順、空行区切り）
String buildMenusText(List<DayRecord> records) {
  final l = [...records]..sort((a, b) => a.date.compareTo(b.date));
  return l.map(buildMenuText).join('\n\n');
}
