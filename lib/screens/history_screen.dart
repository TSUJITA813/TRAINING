import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../parser.dart';
import '../share_text.dart';
import '../store.dart';
import '../widgets.dart';

class HistoryScreen extends StatefulWidget {
  final void Function(DateTime) onOpenDay;
  const HistoryScreen({super.key, required this.onOpenDay});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _q = '';
  bool _byExercise = false;

  /// 複数選択中の日付（空なら通常モード）
  final Set<String> _selected = {};
  List<DayRecord> _visible = [];
  bool get _selecting => _selected.isNotEmpty;

  Future<void> _copyText(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, msg);
  }

  void _copyOne(DayRecord r) =>
      _copyText(buildMenuText(r), '${fmtDateShort(r.dateTime)}のメニューをコピーしました');

  void _copySelected() {
    final recs = AppStore.instance.records.values
        .where((r) => _selected.contains(r.date) && r.menu.trim().isNotEmpty)
        .toList();
    if (recs.isEmpty) {
      showToast(context, 'コピーできるメニューがありません');
      return;
    }
    _copyText(buildMenusText(recs), '${recs.length}日分のメニューをコピーしました');
    setState(_selected.clear);
  }

  void _toggle(DayRecord r) {
    if (r.menu.trim().isEmpty) {
      showToast(context, 'この日はトレーニングの記録がありません');
      return;
    }
    setState(() => _selected.contains(r.date) ? _selected.remove(r.date) : _selected.add(r.date));
  }

  @override
  Widget build(BuildContext context) {
    if (_selecting) {
      final selectable = _visible.where((r) => r.menu.trim().isNotEmpty).map((r) => r.date).toSet();
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => setState(_selected.clear),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '選択をやめる',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
            title: Text('${_selected.length}日を選択中'),
            actions: [
              TextButton(
                onPressed: () => setState(() => _selected.length == selectable.length
                    ? _selected.clear()
                    : _selected.addAll(selectable)),
                child: Text(_selected.length == selectable.length ? '選択解除' : 'すべて選択'),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _copySelected,
            icon: const Icon(Icons.content_copy),
            label: Text('${_selected.length}日分をコピー'),
          ),
          body: ListenableBuilder(listenable: AppStore.instance, builder: (context, _) => _dayList()),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('履歴'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('日付')),
                ButtonSegment(value: true, label: Text('種目')),
              ],
              selected: {_byExercise},
              onSelectionChanged: (s) => setState(() => _byExercise = s.first),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppStore.instance,
        builder: (context, _) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _byExercise ? '種目名で絞り込み' : 'メニュー名・種目・メモで検索',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(child: _byExercise ? _exerciseList() : _dayList()),
        ]),
      ),
    );
  }

  Widget _dayList() {
    final store = AppStore.instance;
    final q = _q.toLowerCase();
    final list = store.sortedRecords
        .where((r) =>
            q.isEmpty ||
            r.title.toLowerCase().contains(q) ||
            r.menu.toLowerCase().contains(q) ||
            r.condition.toLowerCase().contains(q))
        .toList();
    _visible = list;
    if (list.isEmpty) {
      return Center(child: Text(q.isEmpty ? 'まだ記録がありません。' : '該当する記録がありません。'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final r = list[i];
        final theme = Theme.of(context);
        final w = store.parsedOf(r);
        final info = <String>[
          if (r.weightKg != null) '${fmtNum(r.weightKg!)}kg',
          if (r.steps != null) '${fmtKg(r.steps!.toDouble())}歩',
          if (w.totalVolume > 0) '総挙上量 ${fmtKg(w.totalVolume)}kg',
        ];
        final selected = _selected.contains(r.date);
        return Card(
          color: selected ? theme.colorScheme.primaryContainer : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selecting ? _toggle(r) : widget.onOpenDay(r.dateTime),
            onLongPress: () => _toggle(r),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (_selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
                      ),
                    ),
                  Text(fmtDateJa(r.dateTime), style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  if (r.title.isNotEmpty)
                    Expanded(
                      child: Text('【${r.title}】',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    )
                  else
                    const Spacer(),
                  if (!_selecting) ...[
                    if (r.menu.trim().isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'メニューをコピー',
                        icon: const Icon(Icons.content_copy, size: 20),
                        onPressed: () => _copyOne(r),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'その他の操作',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _recordMenu(r),
                    ),
                  ],
                ]),
                if (info.isNotEmpty) Text(info.join('／'), style: theme.textTheme.bodySmall),
                if (w.exercises.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final line in exerciseLines(w).take(8))
                    Text(line, style: theme.textTheme.bodyMedium),
                  if (exerciseLines(w).length > 8)
                    Text('ほか${exerciseLines(w).length - 8}行', style: theme.textTheme.bodySmall),
                ],
                if (r.condition.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.condition.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _recordMenu(DayRecord r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('この日を開く'),
            onTap: () => Navigator.pop(c, 'open'),
          ),
          if (r.menu.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('メニューをクリップボードにコピー'),
              subtitle: const Text('【メニュー名】日付と整形したトレーニング内容のみ'),
              onTap: () => Navigator.pop(c, 'clip'),
            ),
          if (r.menu.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('複数の日を選んでコピー'),
              onTap: () => Navigator.pop(c, 'select'),
            ),
          if (r.menu.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.content_paste_go),
              title: const Text('このメニューを今日にコピー'),
              onTap: () => Navigator.pop(c, 'copy'),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
            title: Text('この日の記録を削除', style: TextStyle(color: Theme.of(c).colorScheme.error)),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final store = AppStore.instance;
    switch (action) {
      case 'open':
        widget.onOpenDay(r.dateTime);
      case 'clip':
        _copyOne(r);
      case 'select':
        _toggle(r);
      case 'copy':
        final t = store.ensureRecord(today());
        if (t.menu.trim().isNotEmpty) {
          final ok = await confirmDialog(context,
              title: '今日のメニューを置き換えますか？',
              message: '今日はすでにメニューが入力されています。コピーすると置き換わります。',
              ok: '置き換える');
          if (!ok || !mounted) return;
        }
        final oldTitle = t.title, oldMenu = t.menu;
        t.menu = r.menu.trim().split('\n').map((l) {
          final m = headerRe.firstMatch(normalizeText(l));
          if (m != null && m.group(2) != null) {
            return '【${m.group(1)}】${dateKey(today()).replaceAll('-', '/')}';
          }
          return l;
        }).join('\n');
        t.title = r.title;
        store.touch(t);
        store.bumpExternal();
        if (!mounted) return;
        showToast(context, '今日のメニューにコピーしました',
            action: SnackBarAction(
              label: '元に戻す',
              onPressed: () {
                t.title = oldTitle;
                t.menu = oldMenu;
                store.touch(t);
                store.bumpExternal();
              },
            ));
      case 'delete':
        final ok = await confirmDialog(context,
            title: '記録を削除しますか？',
            message: '${fmtDateJa(r.dateTime)}の記録を削除します。',
            ok: '削除する',
            danger: true);
        if (!ok || !mounted) return;
        store.deleteRecord(r.date);
        showToast(context, '削除しました',
            action: SnackBarAction(label: '元に戻す', onPressed: () => store.restoreRecord(r)));
    }
  }

  Widget _exerciseList() {
    final store = AppStore.instance;
    final names = store.frequentExercises(limit: 1000)
        .where((n) => _q.isEmpty || n.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    if (names.isEmpty) return const Center(child: Text('種目の記録がありません。'));
    return ListView.separated(
      itemCount: names.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = names[i];
        final h = store.exerciseHistory(n);
        double? best;
        for (final x in h) {
          final m = x.entry.maxWeight;
          if (m != null && (best == null || m > best)) best = m;
        }
        return ListTile(
          title: Text(n, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
              '${h.length}回／最終 ${h.isEmpty ? '－' : fmtDateShort(parseDateKey(h.first.date))}：${h.isEmpty ? '' : h.first.entry.compactSets}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: Text(best == null ? '' : '最高 ${fmtNum(best)}kg'),
          onTap: () => showExerciseHistory(context, n),
        );
      },
    );
  }
}
