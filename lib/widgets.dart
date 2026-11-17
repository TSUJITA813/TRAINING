import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'parser.dart';
import 'store.dart';

void showToast(BuildContext context, String msg, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    action: action,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: action == null ? 2 : 5),
  ));
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String ok = 'はい', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// セット1つ分のチップ
class SetChip extends StatelessWidget {
  final SetEntry set;
  const SetChip(this.set, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = set.failed;
    final w = set.weight == null ? '自重' : fmtNum(set.weight!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: failed ? cs.errorContainer : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: w, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: set.weight == null ? '' : 'kg'),
          TextSpan(text: ' × ${set.reps}回'),
          if (set.count > 1)
            TextSpan(text: ' ×${set.count}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (failed) const TextSpan(text: ' ✕'),
        ]),
        style: TextStyle(
          fontSize: 13,
          color: failed ? cs.onErrorContainer : cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// パース結果の整形表示
class WorkoutPreview extends StatelessWidget {
  final ParsedWorkout workout;
  final DateTime? day; // 指定時は「前回」との比較を表示
  final bool compact;
  const WorkoutPreview({super.key, required this.workout, this.day, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (workout.exercises.isEmpty && workout.notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('「種目 重量@回数」の形式で入力すると、ここに整形して表示されます。',
            style: theme.textTheme.bodySmall),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in workout.exercises)
          InkWell(
            onTap: () => showExerciseHistory(context, e.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(e.name,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    if (e.volume > 0)
                      Text('${fmtKg(e.volume)}kg', style: theme.textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: [for (final s in e.sets) SetChip(s)]),
                  for (final n in e.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('メモ：$n', style: theme.textTheme.bodySmall),
                    ),
                  if (day != null && !compact) _PrevLine(name: e.name, day: day!, current: e),
                ],
              ),
            ),
          ),
        for (final n in workout.notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('📝 $n', style: theme.textTheme.bodyMedium),
          ),
        if (workout.exercises.isNotEmpty && !compact) ...[
          const Divider(),
          Text(
            '合計 ${workout.exercises.length}種目・${workout.totalSets}セット・総挙上量 ${fmtKg(workout.totalVolume)}kg',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }
}

class _PrevLine extends StatelessWidget {
  final String name;
  final DateTime day;
  final ExerciseEntry current;
  const _PrevLine({required this.name, required this.day, required this.current});

  @override
  Widget build(BuildContext context) {
    final prev = AppStore.instance.previousExercise(name, day);
    if (prev == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cur = current.maxWeight, old = prev.entry.maxWeight;
    String? diff;
    if (cur != null && old != null && cur != old) {
      diff = cur > old ? '（最高重量 +${fmtNum(cur - old)}kg）' : '（最高重量 ${fmtNum(cur - old)}kg）';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '前回 ${fmtDateShort(parseDateKey(prev.date))}：${prev.entry.compactSets}${diff ?? ''}',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}

/// 種目の履歴（推移）を表示するシート
void showExerciseHistory(BuildContext context, String name) {
  final hist = AppStore.instance.exerciseHistory(name);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final theme = Theme.of(c);
      double? best;
      for (final h in hist) {
        final m = h.entry.maxWeight;
        if (m != null && (best == null || m > best)) best = m;
      }
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (c, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('$name の履歴', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              hist.isEmpty
                  ? 'まだ記録がありません。'
                  : '${hist.length}回の記録／最高重量 ${best == null ? '－' : '${fmtNum(best)}kg'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final h in hist)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(fmtDateJa(parseDateKey(h.date))),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                      spacing: 4, runSpacing: 4, children: [for (final s in h.entry.sets) SetChip(s)]),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (h.entry.volume > 0) Text('${fmtKg(h.entry.volume)}kg'),
                    if (h.entry.best1RM != null)
                      Text('推定1RM ${h.entry.best1RM!.toStringAsFixed(1)}',
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
