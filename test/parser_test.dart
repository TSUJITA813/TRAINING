import 'package:flutter_test/flutter_test.dart';
import 'package:training_memo/parser.dart';

void main() {
  test('ユーザーのメモ帳形式をパースできる', () {
    const memo = '【試合前A】2026/11/10\n'
        'RPD 90@4 90@4 RPDW 45@5✕\n'
        'PSQ 175@2  175@2 \n'
        'BSQ 130@2 130@2\n'
        'DBBP 34@4 34@4';
    final w = parseWorkout(memo);
    expect(w.title, '試合前A');
    expect(w.date, DateTime(2026, 11, 10));
    expect(w.exercises.map((e) => e.name).toList(), ['RPD', 'RPDW', 'PSQ', 'BSQ', 'DBBP']);
    expect(w.exercises[0].sets.length, 2);
    expect(w.exercises[1].sets.single.failed, isTrue);
    expect(w.exercises[1].volume, 0);
    expect(w.exercises[2].volume, 700);
    expect(w.totalSets, 9);
  });

  test('セット数・自重・全角・メモ', () {
    final w = parseWorkout('ベンチ プレス 100@5x3\n懸垂 @10 @8\nSQ １４０＠３ きつい\n# 腰に張り');
    expect(w.exercises[0].name, 'ベンチ プレス');
    expect(w.exercises[0].setCount, 3);
    expect(w.exercises[0].volume, 1500);
    expect(w.exercises[1].sets.first.weight, isNull);
    expect(w.exercises[2].sets.single.weight, 140);
    expect(w.exercises[2].notes, ['きつい']);
    expect(w.notes, ['腰に張り']);
  });

  test('種目名のない行は前の種目の続き', () {
    final w = parseWorkout('BSQ 130@2\n130@2 130@1✕');
    expect(w.exercises.length, 1);
    expect(w.exercises.first.sets.length, 3);
  });

  test('メモ帳の一括分割', () {
    final days = splitMemoPad('【A】2026/11/10\nRPD 90@4\n\n【B】2026/11/12\nBSQ 130@2\n');
    expect(days.length, 2);
    expect(days[1].title, 'B');
    expect(days[1].date, DateTime(2026, 11, 12));
    expect(days[0].menu, 'RPD 90@4');
  });
}
