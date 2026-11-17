import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../parser.dart';
import '../store.dart';
import '../widgets.dart';

class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  final store = AppStore.instance;
  late final TextEditingController _h;
  late final TextEditingController _w;
  final _formKey = GlobalKey<FormState>();
  final _hFocus = FocusNode();
  final _wFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _h = TextEditingController(text: fmtNum(store.profile.heightCm));
    _w = TextEditingController(text: fmtNum(store.profile.weightKg));
    store.externalRev.addListener(_reload);
    store.addListener(_reload);
  }

  void _reload() {
    if (!mounted || _hFocus.hasFocus || _wFocus.hasFocus) return;
    _h.text = fmtNum(store.profile.heightCm);
    _w.text = fmtNum(store.profile.weightKg);
  }

  @override
  void dispose() {
    store.externalRev.removeListener(_reload);
    store.removeListener(_reload);
    _hFocus.dispose();
    _wFocus.dispose();
    _h.dispose();
    _w.dispose();
    super.dispose();
  }

  String? _validate(String? v, {required double min, required double max, required String label}) {
    final d = double.tryParse(v ?? '');
    if (d == null) return '$labelを数値で入力してください';
    if (d < min || d > max) return '$labelは${fmtNum(min)}〜${fmtNum(max)}の範囲で入力してください';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    store.setProfile(heightCm: double.parse(_h.text), weightKg: double.parse(_w.text));
    showToast(context, '身体情報を保存しました（今日の体重にも反映）');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('身体情報')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final p = store.profile;
          final weights = store.records.values.where((r) => r.weightKg != null).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _h,
                            focusNode: _hFocus,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            decoration: const InputDecoration(labelText: '身長', suffixText: 'cm'),
                            validator: (v) => _validate(v, min: 50, max: 260, label: '身長'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _w,
                            focusNode: _wFocus,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            decoration: const InputDecoration(labelText: '体重', suffixText: 'kg'),
                            validator: (v) => _validate(v, min: 20, max: 300, label: '体重'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存する'),
                      ),
                    ]),
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _stat(theme, '身長', '${fmtNum(p.heightCm)}cm'),
                    _stat(theme, '体重', '${fmtNum(p.weightKg)}kg'),
                    _stat(theme, 'BMI', p.bmi.toStringAsFixed(1)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('体重の推移', style: theme.textTheme.titleMedium),
              ),
              if (weights.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('体重の記録はまだありません。記録画面で毎日の体重を入力できます。'),
                ),
              if (weights.length >= 2)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      height: 140,
                      child: CustomPaint(
                        painter: _WeightChartPainter(
                          weights.take(60).toList().reversed.map((r) => r.weightKg!).toList(),
                          theme.colorScheme.primary,
                          theme.colorScheme.outline,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < weights.length && i < 60; i++)
                ListTile(
                  dense: true,
                  title: Text(fmtDateJa(weights[i].dateTime)),
                  trailing: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${weights[i].weightKg!.toStringAsFixed(1)}kg',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (i + 1 < weights.length)
                      TextSpan(
                        text: '  ${_diff(weights[i].weightKg! - weights[i + 1].weightKg!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ])),
                ),
            ],
          );
        },
      ),
    );
  }

  String _diff(double d) {
    if (d.abs() < 0.05) return '±0.0';
    return d > 0 ? '+${d.toStringAsFixed(1)}' : d.toStringAsFixed(1);
  }

  Widget _stat(ThemeData theme, String label, String value) => Column(children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ]);
}

class _WeightChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color grid;
  _WeightChartPainter(this.values, this.color, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 1) {
      minV -= 0.5;
      maxV += 0.5;
    }
    const pad = 16.0;
    final h = size.height - pad * 2;
    final w = size.width - 40;
    Offset pt(int i) => Offset(
          40 + w * i / (values.length - 1),
          pad + h * (1 - (values[i] - minV) / (maxV - minV)),
        );
    final gp = Paint()
      ..color = grid.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (final v in [minV, (minV + maxV) / 2, maxV]) {
      final y = pad + h * (1 - (v - minV) / (maxV - minV));
      canvas.drawLine(Offset(40, y), Offset(size.width, y), gp);
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(1), style: TextStyle(color: grid, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    final dp = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(pt(i), 3, dp);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter old) => old.values != values;
}
