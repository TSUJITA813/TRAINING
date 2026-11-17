import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart' show selectedDay;
import '../models.dart';
import '../parser.dart';
import '../share_text.dart';
import '../steps_service.dart';
import '../store.dart';
import '../widgets.dart';

class DayScreen extends StatelessWidget {
  final void Function(DateTime) onOpenDay;
  const DayScreen({super.key, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([selectedDay, AppStore.instance.externalRev]),
      builder: (context, _) {
        final day = selectedDay.value;
        return _DayPage(
          key: ValueKey('${dateKey(day)}#${AppStore.instance.externalRev.value}'),
          day: day,
        );
      },
    );
  }
}

class _DayPage extends StatefulWidget {
  final DateTime day;
  const _DayPage({super.key, required this.day});

  @override
  State<_DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<_DayPage> {
  final store = AppStore.instance;
  late final TextEditingController _title;
  late final TextEditingController _menu;
  late final TextEditingController _cond;
  late final TextEditingController _weight;
  final _menuFocus = FocusNode();
  final _condFocus = FocusNode();
  bool _showPreview = true;

  // 歩数
  bool _stepsLoading = false;
  StepsResult? _stepsError;
  StreamSubscription<int>? _sensorSub;

  DateTime get day => widget.day;
  bool get isToday => day == today();
  DayRecord? get record => store.recordFor(day);

  @override
  void initState() {
    super.initState();
    final r = record;
    _title = TextEditingController(text: r?.title ?? '');
    _menu = TextEditingController(text: r?.menu ?? '');
    _cond = TextEditingController(text: r?.condition ?? '');
    _weight = TextEditingController(
        text: r?.weightKg != null ? fmtNum(r!.weightKg!) : '');
    _title.addListener(() => _save((r) => r.title = _title.text));
    _menu.addListener(() {
      _save((r) => r.menu = _menu.text);
      setState(() {});
    });
    _cond.addListener(() => _save((r) => r.condition = _cond.text));
    _menuFocus.addListener(() => setState(() {}));
    _condFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSteps(auto: true));
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    store.saveNow();
    _title.dispose();
    _menu.dispose();
    _cond.dispose();
    _weight.dispose();
    _menuFocus.dispose();
    _condFocus.dispose();
    super.dispose();
  }

  void _save(void Function(DayRecord) apply) {
    final r = store.recordFor(day);
    // 何も入力していない日は空レコードを作らない
    if (r == null &&
        _title.text.isEmpty &&
        _menu.text.isEmpty &&
        _cond.text.isEmpty) {
      return;
    }
    final rec = r ?? store.ensureRecord(day);
    apply(rec);
    store.touch(rec, notify: false);
  }

  // ---------------- 歩数 ----------------

  Future<void> _refreshSteps({bool auto = false}) async {
    final src = store.stepSource;
    if (src == StepSource.manual) return;
    if (src == StepSource.sensor) {
      if (!isToday) return;
      final ok = await StepsService.instance.startSensor();
      if (!mounted) return;
      if (!ok) {
        setState(() => _stepsError = const StepsResult(
            error: '「身体活動」の権限が許可されていないため、歩数を計測できません。', needsPermission: true));
        return;
      }
      _sensorSub ??= StepsService.instance.sensorTodaySteps.listen((_) {
        if (mounted) setState(() {});
      });
      setState(() => _stepsError = null);
      return;
    }
    // ヘルスコネクト：今日、または未取得の過去30日以内の日を取得
    final daysAgo = today().difference(day).inDays;
    if (auto && !(isToday || (record?.steps == null && daysAgo <= 30))) return;
    if (auto && record?.stepsSource == StepSource.manual.name) return;
    setState(() => _stepsLoading = true);
    final res = await StepsService.instance.fetchFromHealthConnect(day);
    if (!mounted) return;
    setState(() {
      _stepsLoading = false;
      _stepsError = res.error == null ? null : res;
    });
    if (res.steps != null) {
      if (res.steps! > 0 || record?.steps == null || isToday) {
        store.setSteps(day, res.steps, StepSource.healthConnect);
      }
      if (!auto && mounted) showToast(context, '歩数を更新しました');
      setState(() {});
    }
  }

  Future<void> _fixStepsProblem() async {
    final e = _stepsError;
    if (e == null) return;
    if (e.needsInstall) {
      await StepsService.instance.installHealthConnect();
      return;
    }
    if (store.stepSource == StepSource.healthConnect) {
      final ok = await StepsService.instance.requestHealthConnectPermission();
      if (!mounted) return;
      if (!ok) {
        showToast(context, '許可されませんでした。ヘルスコネクトのアプリ権限から「歩数」を許可してください。');
      }
    }
    await _refreshSteps();
  }

  Future<void> _editStepsManually() async {
    final c = TextEditingController(text: record?.steps?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('歩数を手入力'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: '歩', hintText: '例：8000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('消去')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('保存')),
        ],
      ),
    );
    if (v == null) return;
    store.setSteps(day, v.isEmpty ? null : int.tryParse(v), StepSource.manual);
    setState(() {});
  }

  // ---------------- 入力補助 ----------------

  void _insert(String text) {
    final v = _menu.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final newText = v.text.replaceRange(sel.start, sel.end, text);
    _menu.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  String _currentLineBeforeCursor() {
    final v = _menu.value;
    final pos = v.selection.isValid ? v.selection.start : v.text.length;
    final before = v.text.substring(0, pos);
    final i = before.lastIndexOf('\n');
    return before.substring(i + 1);
  }

  bool get _needsSpace {
    final line = _currentLineBeforeCursor();
    return line.isNotEmpty && !line.endsWith(' ') && !line.endsWith('　');
  }

  void _insertExercise(String name) {
    final line = _currentLineBeforeCursor();
    final prefix = line.trim().isEmpty ? '' : '\n';
    _insert('$prefix$name ');
    if (!_menuFocus.hasFocus) _menuFocus.requestFocus();
  }

  /// 直前のセットと同じ内容を追加
  void _repeatLastSet() {
    final v = _menu.value;
    final pos = v.selection.isValid ? v.selection.start : v.text.length;
    final before = normalizeText(v.text.substring(0, pos));
    final tokens = before.split(RegExp(r'[\s,、]+')).reversed;
    for (final t in tokens) {
      final s = parseSetToken(t);
      if (s != null) {
        final w = s.weight == null ? '' : fmtNum(s.weight!);
        _insert('${_needsSpace ? ' ' : ''}$w@${s.reps} ');
        return;
      }
    }
    showToast(context, '繰り返すセットが見つかりません');
  }

  /// 現在行の種目の「前回の内容」を挿入
  void _insertPrevious() {
    final line = normalizeText(_currentLineBeforeCursor()).trim();
    final tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final nameTokens = <String>[];
    for (final t in tokens.reversed) {
      if (parseSetToken(t) != null) break;
      nameTokens.insert(0, t);
    }
    final name = nameTokens.join(' ');
    if (name.isEmpty) {
      showToast(context, '先に種目名を入力してください');
      return;
    }
    final prev = store.previousExercise(name, day);
    if (prev == null) {
      showToast(context, '「$name」の過去の記録がありません');
      return;
    }
    _insert('${_needsSpace ? ' ' : ''}${prev.entry.compactSets.replaceAll('✕', '')} ');
  }

  void _insertCond(String text) {
    final v = _cond.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final needNl = sel.start > 0 && !v.text.substring(0, sel.start).endsWith('\n');
    final t = '${needNl ? '\n' : ''}$text';
    _cond.value = TextEditingValue(
      text: v.text.replaceRange(sel.start, sel.end, t),
      selection: TextSelection.collapsed(offset: sel.start + t.length),
    );
    _condFocus.requestFocus();
  }

  // ---------------- 過去メニューのコピー ----------------

  Future<void> _copyFromPast() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<DayRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _PastMenuPicker(excludeDate: dateKey(day)),
    );
    if (picked == null || !mounted) return;

    var menu = picked.menu.trim();
    // 見出し行の日付を今日の日付に置き換える
    menu = menu.split('\n').map((l) {
      final m = headerRe.firstMatch(normalizeText(l));
      if (m != null && m.group(2) != null) {
        return '【${m.group(1)}】${dateKey(day).replaceAll('-', '/')}';
      }
      return l;
    }).join('\n');

    var replace = true;
    if (_menu.text.trim().isNotEmpty) {
      final r = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('すでにメニューが入力されています'),
          content: const Text('コピーしたメニューをどのように反映しますか？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('やめる')),
            TextButton(onPressed: () => Navigator.pop(c, 'append'), child: const Text('末尾に追加')),
            FilledButton(onPressed: () => Navigator.pop(c, 'replace'), child: const Text('置き換える')),
          ],
        ),
      );
      if (r == null || !mounted) return;
      replace = r == 'replace';
    }
    final oldTitle = _title.text, oldMenu = _menu.text;
    if (replace) {
      _menu.text = menu;
      if (picked.title.isNotEmpty) _title.text = picked.title;
    } else {
      _menu.text = '${_menu.text.trimRight()}\n$menu';
      if (_title.text.isEmpty) _title.text = picked.title;
    }
    showToast(
      context,
      '${fmtDateShort(picked.dateTime)}のメニューをコピーしました',
      action: SnackBarAction(
        label: '元に戻す',
        onPressed: () {
          _title.text = oldTitle;
          _menu.text = oldMenu;
        },
      ),
    );
  }

  // ---------------- 共有 ----------------

  Future<void> _copyReport() async {
    await store.saveNow();
    final text = buildShareText(day);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast(
      context,
      '日報をクリップボードにコピーしました',
      action: SnackBarAction(
        label: '他のアプリで送る',
        onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '日付を選択',
      cancelText: 'やめる',
      confirmText: '決定',
    );
    if (d != null) selectedDay.value = DateTime(d.year, d.month, d.day);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          tooltip: '前の日',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => selectedDay.value = day.subtract(const Duration(days: 1)),
        ),
        title: InkWell(
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(fmtDateJa(day), style: theme.textTheme.titleMedium),
                ),
              ),
              if (isToday)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(6)),
                  child: Text('今日',
                      style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12)),
                ),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
        ),
        actions: [
          if (!isToday)
            TextButton(onPressed: () => selectedDay.value = today(), child: const Text('今日へ')),
          IconButton(
            tooltip: '次の日',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => selectedDay.value = day.add(const Duration(days: 1)),
          ),
        ],
      ),
      floatingActionButton: keyboardOpen
          ? null
          : FloatingActionButton.extended(
              onPressed: _copyReport,
              icon: const Icon(Icons.content_copy),
              label: const Text('日報をコピー'),
            ),
      bottomNavigationBar: _menuFocus.hasFocus && keyboardOpen
          ? _QuickBar(
              exercises: store.frequentExercises(),
              onInsert: _insert,
              onExercise: _insertExercise,
              onRepeat: _repeatLastSet,
              onPrevious: _insertPrevious,
              onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        children: [
          _bodyCard(theme),
          _trainingCard(theme),
          _conditionCard(theme),
        ],
      ),
    );
  }

  Widget _bodyCard(ThemeData theme) {
    final r = record;
    final p = store.profile;
    final weight = store.weightOn(day);
    final steps = r?.steps;
    final kcal = steps == null ? null : walkingKcal(steps, p.heightCm, weight);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 体重
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('体重', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      hintText: fmtNum(weight),
                      suffixText: 'kg',
                    ),
                    style: theme.textTheme.titleLarge,
                    onChanged: (v) {
                      store.setWeight(day, double.tryParse(v));
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '身長 ${fmtNum(p.heightCm)}cm／BMI ${(weight / ((p.heightCm / 100) * (p.heightCm / 100))).toStringAsFixed(1)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              // 歩数
              Expanded(
                child: InkWell(
                  onTap: _editStepsManually,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('歩数', style: theme.textTheme.labelMedium),
                      const Spacer(),
                      if (store.stepSource != StepSource.manual)
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: _stepsLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  tooltip: '歩数を更新',
                                  onPressed: () => _refreshSteps(),
                                  icon: const Icon(Icons.refresh),
                                ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      steps == null ? '－' : '${fmtKg(steps.toDouble())}歩',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (kcal != null)
                      Text(
                        '約${walkingKm(steps!, p.heightCm).toStringAsFixed(1)}km／約${kcal.round()}kcal',
                        style: theme.textTheme.bodySmall,
                      ),
                    Text(
                      r?.stepsSource != null
                          ? '取得元：${stepSourceFrom(r!.stepsSource).shortLabel}（タップで手入力）'
                          : 'タップで手入力',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ]),
                ),
              ),
            ]),
            if (_stepsError != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(_stepsError!.error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _fixStepsProblem,
                    child: Text(_stepsError!.needsInstall ? 'インストール' : '許可する'),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trainingCard(ThemeData theme) {
    final parsed = parseWorkout(_menu.text);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.fitness_center, size: 20),
              const SizedBox(width: 6),
              Text('トレーニングメニュー', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyFromPast,
                icon: const Icon(Icons.copy_all, size: 18),
                label: const Text('過去からコピー'),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _menuFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'メニュー名',
                hintText: '例：試合前A',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _menu,
              focusNode: _menuFocus,
              minLines: 5,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 17, height: 1.4, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'RPD 90@4 90@4\nPSQ 175@2 175@2\nBSQ 130@2x3\nDBBP 34@4 34@4✕',
                helperText: '「種目 重量@回数」で入力／✕＝失敗、x3＝3セット、#＝メモ行',
                helperMaxLines: 2,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('整形表示', style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              if (parsed.exercises.isNotEmpty)
                Text('（種目名をタップで履歴）', style: theme.textTheme.bodySmall),
              const Spacer(),
              IconButton(
                tooltip: _showPreview ? '整形表示を閉じる' : '整形表示を開く',
                onPressed: () => setState(() => _showPreview = !_showPreview),
                icon: Icon(_showPreview ? Icons.expand_less : Icons.expand_more),
              ),
            ]),
            if (_showPreview) WorkoutPreview(workout: parsed, day: day),
          ],
        ),
      ),
    );
  }

  Widget _conditionCard(ThemeData theme) {
    const templates = ['疲労度（1〜5）：', '睡眠：', 'サプリ：', '食事：', '痛み・違和感：', '気分：'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.favorite_outline, size: 20),
              const SizedBox(width: 6),
              Text('コンディション・栄養メモ', style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 0, children: [
              for (final t in templates)
                ActionChip(
                  label: Text(t.replaceAll('：', '')),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _insertCond(t),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _cond,
              focusNode: _condFocus,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '疲労度、睡眠、サプリメントの摂取状況などを自由に記入',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// キーボードのすぐ上に表示する入力補助バー
class _QuickBar extends StatelessWidget {
  final List<String> exercises;
  final void Function(String) onInsert;
  final void Function(String) onExercise;
  final VoidCallback onRepeat;
  final VoidCallback onPrevious;
  final VoidCallback onDone;

  const _QuickBar({
    required this.exercises,
    required this.onInsert,
    required this.onExercise,
    required this.onRepeat,
    required this.onPrevious,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, VoidCallback onTap, {bool primary = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: primary ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                height: 40,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primary ? cs.onPrimaryContainer : cs.onSurface)),
              ),
            ),
          ),
        );

    return Material(
      elevation: 8,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (exercises.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                children: [
                  for (final e in exercises)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ActionChip(
                        label: Text(e),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => onExercise(e),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              children: [
                key('@', () => onInsert('@'), primary: true),
                key('同じセット', onRepeat, primary: true),
                key('前回の内容', onPrevious),
                key('✕', () => onInsert('✕')),
                key('x', () => onInsert('x')),
                key('空白', () => onInsert(' ')),
                key('改行', () => onInsert('\n')),
                key('完了', onDone),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// 過去メニューの選択シート
class _PastMenuPicker extends StatefulWidget {
  final String excludeDate;
  const _PastMenuPicker({required this.excludeDate});

  @override
  State<_PastMenuPicker> createState() => _PastMenuPickerState();
}

class _PastMenuPickerState extends State<_PastMenuPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = AppStore.instance.trainingRecords
        .where((r) => r.date != widget.excludeDate && r.menu.trim().isNotEmpty)
        .where((r) => _q.isEmpty || r.title.contains(_q) || r.menu.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (c, ctrl) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('コピーするメニューを選択', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'メニュー名や種目名で検索',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ]),
        ),
        Expanded(
          child: all.isEmpty
              ? Center(child: Text(_q.isEmpty ? 'コピーできる過去のメニューがありません。' : '該当するメニューがありません。'))
              : ListView.separated(
                  controller: ctrl,
                  itemCount: all.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = all[i];
                    final ex = AppStore.instance.parsedOf(r).exercises;
                    return ListTile(
                      onTap: () => Navigator.pop(context, r),
                      title: Text(
                          '${fmtDateJa(r.dateTime)}${r.title.isNotEmpty ? '　${r.title}' : ''}'),
                      subtitle: Text(
                        ex.isNotEmpty
                            ? ex.map((e) => '${e.name} ${e.compactSets}').join('\n')
                            : r.menu.trim(),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.content_paste_go),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
