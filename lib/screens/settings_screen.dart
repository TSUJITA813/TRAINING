import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../parser.dart';
import '../steps_service.dart';
import '../store.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final store = AppStore.instance;

  String get _backupFileName =>
      'トレーニングメモ_バックアップ_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';

  Future<void> _exportToFile() async {
    try {
      await store.saveNow();
      final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
      final uri = await FilePicker.saveFile(
        dialogTitle: 'バックアップの保存先を選択',
        fileName: _backupFileName,
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (!mounted) return;
      if (uri == null) {
        showToast(context, '保存を取り消しました');
      } else {
        showToast(context, 'バックアップを保存しました');
      }
    } catch (e) {
      if (mounted) showToast(context, 'バックアップの保存に失敗しました');
    }
  }

  Future<void> _exportByShare() async {
    try {
      await store.saveNow();
      final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/json', name: _backupFileName)],
        fileNameOverrides: [_backupFileName],
        subject: 'トレーニングメモのバックアップ',
      ));
    } catch (e) {
      if (mounted) showToast(context, '共有に失敗しました');
    }
  }

  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(dialogTitle: 'バックアップファイルを選択');
      if (files.isEmpty || !mounted) return;
      final text = utf8.decode(await files.first.xFile.readAsBytes(), allowMalformed: true);
      final int count;
      try {
        count = store.validateBackup(text);
      } on FormatException catch (e) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('読み込めませんでした'),
              content: Text(e.message),
              actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('閉じる'))],
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('バックアップを復元'),
          content: Text('$count日分の記録が見つかりました。\n\n'
              '「統合する」：今のデータを残し、新しい方の記録を採用します。\n'
              '「すべて置き換える」：今のデータを消して、バックアップの内容に戻します。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('やめる')),
            TextButton(onPressed: () => Navigator.pop(c, 'replace'), child: const Text('すべて置き換える')),
            FilledButton(onPressed: () => Navigator.pop(c, 'merge'), child: const Text('統合する')),
          ],
        ),
      );
      if (mode == null) return;
      await store.importJson(text, replace: mode == 'replace');
      if (mounted) showToast(context, '復元が完了しました');
    } catch (e) {
      if (mounted) showToast(context, 'ファイルの読み込みに失敗しました');
    }
  }

  Future<void> _bulkImportMemo() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メモ帳から一括取り込み'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('これまでのメモをまとめて貼り付けてください。「【メニュー名】2026/11/10」のような日付付きの見出し行ごとに、各日の記録として取り込みます。',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) c.text = d!.text!;
                },
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('クリップボードから貼り付け'),
              ),
            ]),
            Flexible(
              child: TextField(
                controller: c,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                    hintText: '【試合前A】2026/11/10\nRPD 90@4 90@4\nPSQ 175@2 175@2\n\n【試合前B】2026/11/12\n…'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('取り込む')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final days = splitMemoPad(text);
    if (days.isEmpty) {
      showToast(context, '日付付きの見出し行が見つかりませんでした');
      return;
    }
    final conflicts = days.where((d) => store.recordFor(d.date)?.menu.trim().isNotEmpty ?? false).length;
    final ok = await confirmDialog(
      context,
      title: '${days.length}日分を取り込みます',
      message: conflicts > 0
          ? 'そのうち$conflicts日分はすでにメニューがあるため、末尾に追記します。よろしいですか？'
          : 'よろしいですか？',
      ok: '取り込む',
    );
    if (!ok) return;
    for (final d in days) {
      final r = store.ensureRecord(d.date);
      if (r.menu.trim().isEmpty) {
        r.menu = d.menu;
      } else {
        r.menu = '${r.menu.trimRight()}\n${d.menu}';
      }
      if (r.title.isEmpty) r.title = d.title;
      r.updatedAt = DateTime.now();
    }
    await store.saveNow();
    store.bumpExternal();
    store.touch(store.ensureRecord(days.first.date));
    if (mounted) showToast(context, '${days.length}日分を取り込みました');
  }

  Future<void> _healthConnectSetup() async {
    final st = await StepsService.instance.healthConnectStatus();
    if (!mounted) return;
    if (st == null || st.name != 'sdkAvailable') {
      final ok = await confirmDialog(context,
          title: 'ヘルスコネクトが見つかりません',
          message: 'ヘルスコネクトのインストールまたは更新が必要です。ストアを開きますか？',
          ok: 'ストアを開く');
      if (ok) await StepsService.instance.installHealthConnect();
      return;
    }
    final granted = await StepsService.instance.requestHealthConnectPermission();
    if (!mounted) return;
    showToast(context, granted ? '歩数の読み取りが許可されました' : '許可されませんでした。ヘルスコネクトの設定から許可してください。');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final total = store.sortedRecords.length;
          final training = store.trainingRecords.length;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _header(theme, '歩数の取得方法'),
              RadioGroup<StepSource>(
                groupValue: store.stepSource,
                onChanged: (v) {
                  if (v == null) return;
                  store.setStepSource(v);
                  if (v == StepSource.sensor) {
                    StepsService.instance.startSensor();
                  } else {
                    StepsService.instance.stopSensor();
                  }
                  if (v == StepSource.healthConnect) _healthConnectSetup();
                },
                child: Column(children: [
                  for (final s in StepSource.values)
                    RadioListTile<StepSource>(
                      value: s,
                      title: Text(s.label),
                      subtitle: Text(switch (s) {
                        StepSource.healthConnect =>
                          'Google Fit や Mi Fitness などがヘルスコネクトに記録した歩数を自動で読み込みます。アプリを閉じていても歩数が欠けません。',
                        StepSource.sensor =>
                          '端末の歩数センサーを直接使います。アプリを開いた時点までの増分で計算するため、日をまたいで開かないと誤差が出ることがあります。',
                        StepSource.manual => '歩数は記録画面でタップして手入力します。',
                      }),
                    ),
                ]),
              ),
              if (store.stepSource == StepSource.healthConnect)
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('ヘルスコネクトの権限を設定'),
                  subtitle: const Text('歩数の読み取りを許可します'),
                  onTap: _healthConnectSetup,
                ),
              const Divider(),
              _header(theme, 'バックアップ・復元'),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('バックアップをファイルに保存'),
                subtitle: const Text('端末内（ダウンロードフォルダ等）やGoogleドライブにJSON形式で保存'),
                onTap: _exportToFile,
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('バックアップを他のアプリで送る'),
                subtitle: const Text('メール・LINE・ドライブなどに送信'),
                onTap: _exportByShare,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('バックアップから復元'),
                subtitle: const Text('保存したJSONファイルを読み込みます'),
                onTap: _import,
              ),
              const Divider(),
              _header(theme, 'データ移行'),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('メモ帳から一括取り込み'),
                subtitle: const Text('これまでのメモ帳の記録を貼り付けてまとめて登録'),
                onTap: _bulkImportMemo,
              ),
              const Divider(),
              _header(theme, '入力のヒント'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '・「種目 重量@回数」で入力（例：BSQ 130@2 130@2）\n'
                  '・1行に複数の種目を書けます（例：RPD 90@4 RPDW 45@5）\n'
                  '・「✕」を付けると失敗レップ（例：45@5✕）\n'
                  '・「x3」で同じ内容を3セット（例：130@2x3）\n'
                  '・重量を省略すると自重（例：懸垂 @10）\n'
                  '・#、※、// で始まる行はメモとして扱います\n'
                  '・キーボード上の「同じセット」で直前のセットを複製、「前回の内容」でその種目の前回のセットを挿入できます',
                  style: TextStyle(height: 1.6),
                ),
              ),
              const Divider(),
              _header(theme, 'データ'),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text('記録：$total日分（うちトレーニング$training日）'),
                subtitle: const Text('データは端末内に自動保存されます。機種変更や万一に備えて定期的にバックアップしてください。'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(ThemeData theme, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      );
}

