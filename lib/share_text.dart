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
    b.writeln(r.menu.trim());
    final w = parseWorkout(r.menu);
    if (w.exercises.isNotEmpty) {
      b.writeln();
      b.writeln('▼ 種目別の詳細');
      for (final e in w.exercises) {
        final sets = e.sets.map((s) => s.label).join('、');
        final vol = e.volume > 0 ? '／総挙上量 ${fmtKg(e.volume)}kg' : '';
        final rm = e.best1RM != null ? '／推定1RM ${e.best1RM!.toStringAsFixed(1)}kg' : '';
        b.writeln('・${e.name}：$sets$vol$rm');
        for (final n in e.notes) {
          b.writeln('　メモ：$n');
        }
      }
      b.writeln('合計：${w.totalSets}セット／総挙上量 ${fmtKg(w.totalVolume)}kg');
    }
  }
  b.writeln();

  b.writeln('■ コンディション・栄養メモ');
  b.writeln((r?.condition.trim().isNotEmpty ?? false) ? r!.condition.trim() : '（記入なし）');
  b.writeln();
  b.write('※表記：「重量@回数」（単位kg）、「✕」は失敗レップ、「x3」は同じ内容を3セット。');
  return b.toString();
}
