/// メモ帳形式のトレーニング記録をパースする。
///
/// 対応フォーマット例:
///   【試合前A】2026/11/10
///   RPD 90@4 90@4 RPDW 45@5✕
///   PSQ 175@2  175@2
///   BSQ 130@2x3        ← 「x3」で同じセットを3セット
///   懸垂 @10 @8         ← 自重（重量省略）
///   # メモ行            ← #, ※, // で始まる行はメモ扱い
library;

class SetEntry {
  final double? weight; // kg（自重の場合は null）
  final int reps;
  final int count; // 同じセットの本数（x3 → 3）
  final bool failed; // ✕ 付き = 失敗
  final String raw;

  const SetEntry({
    required this.weight,
    required this.reps,
    this.count = 1,
    this.failed = false,
    required this.raw,
  });

  double get volume => failed ? 0 : (weight ?? 0) * reps * count;

  /// Epley式の推定1RM
  double? get estimated1RM {
    if (failed || weight == null || reps <= 0) return null;
    if (reps == 1) return weight;
    return weight! * (1 + reps / 30.0);
  }

  String get label {
    final w = weight == null ? '自重' : '${fmtNum(weight!)}kg';
    final c = count > 1 ? ' ×$countセット' : '';
    return '$w×$reps回$c${failed ? '（失敗）' : ''}';
  }

  String get compact {
    final w = weight == null ? '' : fmtNum(weight!);
    final c = count > 1 ? 'x$count' : '';
    return '$w@$reps$c${failed ? '✕' : ''}';
  }
}

class ExerciseEntry {
  String name;
  final List<SetEntry> sets = [];
  final List<String> notes = [];

  ExerciseEntry(this.name);

  double get volume => sets.fold(0.0, (a, s) => a + s.volume);
  int get setCount => sets.fold(0, (a, s) => a + s.count);

  double? get best1RM {
    double? best;
    for (final s in sets) {
      final e = s.estimated1RM;
      if (e != null && (best == null || e > best)) best = e;
    }
    return best;
  }

  double? get maxWeight {
    double? m;
    for (final s in sets) {
      if (s.failed || s.weight == null) continue;
      if (m == null || s.weight! > m) m = s.weight;
    }
    return m;
  }

  String get compactSets => sets.map((s) => s.compact).join(' ');
}

class ParsedWorkout {
  String? title;
  DateTime? date;
  final List<ExerciseEntry> exercises = [];
  final List<String> notes = [];

  double get totalVolume => exercises.fold(0.0, (a, e) => a + e.volume);
  int get totalSets => exercises.fold(0, (a, e) => a + e.setCount);
  bool get isEmpty => exercises.isEmpty && notes.isEmpty;
}

final RegExp headerRe = RegExp(
    r'^\s*[【\[［](.*?)[】\]］]\s*(?:(\d{4})[/\-.年](\d{1,2})[/\-.月](\d{1,2})日?)?\s*$');
final RegExp _dateOnlyRe =
    RegExp(r'^\s*(\d{4})[/\-.年](\d{1,2})[/\-.月](\d{1,2})日?\s*$');
final RegExp _setRe = RegExp(
    r'^(\d+(?:\.\d+)?)?(?:kg|KG|Kg)?@(\d+)(?:[xX×*](\d+))?([✕✖✗×xX])?$');

String normalizeText(String s) {
  const fw = '０１２３４５６７８９';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = fw.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '＠') {
      b.write('@');
    } else if (ch == '．') {
      b.write('.');
    } else if (ch == '　') {
      b.write(' ');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

SetEntry? parseSetToken(String token) {
  final m = _setRe.firstMatch(token);
  if (m == null) return null;
  final reps = int.tryParse(m.group(2)!);
  if (reps == null) return null;
  return SetEntry(
    weight: m.group(1) == null ? null : double.tryParse(m.group(1)!),
    reps: reps,
    count: m.group(3) == null ? 1 : (int.tryParse(m.group(3)!) ?? 1),
    failed: m.group(4) != null,
    raw: token,
  );
}

bool _isNoteLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('#') ||
      t.startsWith('＃') ||
      t.startsWith('※') ||
      t.startsWith('//') ||
      t.startsWith('・');
}

ParsedWorkout parseWorkout(String text) {
  final result = ParsedWorkout();
  final lines = normalizeText(text).split('\n');
  ExerciseEntry? last;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final h = headerRe.firstMatch(line);
    if (h != null) {
      final t = h.group(1)?.trim();
      if (t != null && t.isNotEmpty) result.title ??= t;
      if (h.group(2) != null) {
        result.date ??= _safeDate(h.group(2)!, h.group(3)!, h.group(4)!);
      }
      continue;
    }
    final d = _dateOnlyRe.firstMatch(line);
    if (d != null) {
      result.date ??= _safeDate(d.group(1)!, d.group(2)!, d.group(3)!);
      continue;
    }
    if (_isNoteLine(line)) {
      result.notes.add(line.trimLeft().replaceFirst(RegExp(r'^(#|＃|※|//|・)\s*'), ''));
      continue;
    }

    final tokens =
        line.split(RegExp(r'[\s,、，]+')).where((t) => t.isNotEmpty).toList();
    ExerciseEntry? current;
    bool prevWasSet = false;
    final lineExercises = <ExerciseEntry>[];

    for (final tok in tokens) {
      final set = parseSetToken(tok);
      if (set != null) {
        if (current == null) {
          // 種目名なしで始まる行 → 直前の種目の続き
          current = last ?? ExerciseEntry('（種目名なし）');
          if (last == null) {
            result.exercises.add(current);
            last = current;
          }
        }
        current.sets.add(set);
        prevWasSet = true;
      } else {
        if (current == null || prevWasSet) {
          current = ExerciseEntry(tok);
          lineExercises.add(current);
          result.exercises.add(current);
          last = current;
        } else {
          current.name = '${current.name} $tok';
        }
        prevWasSet = false;
      }
    }

    // 行末のセットを持たない「種目」は、直前の種目へのメモとして扱う
    if (lineExercises.length >= 2) {
      final tail = lineExercises.last;
      if (tail.sets.isEmpty) {
        result.exercises.remove(tail);
        final prev = lineExercises[lineExercises.length - 2];
        prev.notes.add(tail.name);
        last = prev;
      }
    }
  }
  return result;
}

DateTime? _safeDate(String y, String m, String d) {
  final yy = int.tryParse(y), mm = int.tryParse(m), dd = int.tryParse(d);
  if (yy == null || mm == null || dd == null) return null;
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  return DateTime(yy, mm, dd);
}

String fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String fmtKg(double v) {
  final s = v.round().toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

/// メモ帳からの一括取り込み用：見出し行（【タイトル】日付）ごとに分割する
class ImportedDay {
  final DateTime date;
  final String title;
  final String menu;
  ImportedDay(this.date, this.title, this.menu);
}

List<ImportedDay> splitMemoPad(String text) {
  final lines = text.split('\n');
  final out = <ImportedDay>[];
  DateTime? curDate;
  String curTitle = '';
  final buf = <String>[];

  void flush() {
    if (curDate != null) {
      final body = buf.join('\n').trim();
      out.add(ImportedDay(curDate, curTitle, body));
    }
    buf.clear();
  }

  for (final raw in lines) {
    final n = normalizeText(raw);
    final h = headerRe.firstMatch(n);
    final d = _dateOnlyRe.firstMatch(n);
    DateTime? date;
    String? title;
    if (h != null && h.group(2) != null) {
      date = _safeDate(h.group(2)!, h.group(3)!, h.group(4)!);
      title = h.group(1)?.trim() ?? '';
    } else if (d != null) {
      date = _safeDate(d.group(1)!, d.group(2)!, d.group(3)!);
      title = '';
    }
    if (date != null) {
      flush();
      curDate = date;
      curTitle = title ?? '';
    } else {
      buf.add(raw);
    }
  }
  flush();
  return out;
}
