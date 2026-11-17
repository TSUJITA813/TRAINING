import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:training_memo/main.dart';
import 'package:training_memo/models.dart';
import 'package:training_memo/store.dart';

void main() {
  testWidgets('全タブを表示しても例外が出ない', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    // プラグインのチャネルは応答なしにしておく
    for (final ch in ['dev.fluttercommunity.plus/share', 'flutter_health']) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
    await tester.runAsync(() async {
      await initializeDateFormatting('ja_JP');
      final dir = await Directory.systemTemp.createTemp('tm');
      await AppStore.instance.load(directory: dir);
      AppStore.instance.stepSource = StepSource.manual;
    });
    expect(AppStore.instance.profile.heightCm, 189.3);
    selectedDay.value = DateTime(2026, 11, 10);
    await tester.pumpWidget(const TrainingMemoApp());
    await tester.pumpAndSettle();
    expect(find.text('トレーニングメニュー'), findsOneWidget);
    expect(find.text('RPDW'), findsOneWidget);
    expect(find.text('日報をコピー'), findsOneWidget);

    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    expect(find.text('【試合前A】'), findsOneWidget);
    await tester.tap(find.text('種目'));
    await tester.pumpAndSettle();
    expect(find.text('PSQ'), findsOneWidget);

    await tester.tap(find.text('身体'));
    await tester.pumpAndSettle();
    expect(find.text('保存する'), findsOneWidget);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('バックアップから復元'), findsOneWidget);

    await tester.tap(find.text('記録'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('過去からコピー'));
    await tester.pumpAndSettle();
    expect(find.text('コピーするメニューを選択'), findsOneWidget);
  });
}
