import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'screens/body_screen.dart';
import 'screens/day_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja_JP');
  await AppStore.instance.load();
  runApp(const TrainingMemoApp());
}

class TrainingMemoApp extends StatelessWidget {
  const TrainingMemoApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFE65100), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'トレーニングメモ',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

/// 画面間で共有する「表示中の日付」
final ValueNotifier<DateTime> selectedDay = ValueNotifier(today());

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      AppStore.instance.saveNow();
    }
    if (state == AppLifecycleState.resumed) {
      // 日付が変わっていたら今日に合わせる
      final t = today();
      if (selectedDay.value.isBefore(t) && _wasToday) selectedDay.value = t;
    }
    _wasToday = selectedDay.value == today();
  }

  bool _wasToday = true;

  void openDay(DateTime d) {
    selectedDay.value = d;
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DayScreen(onOpenDay: openDay),
      HistoryScreen(onOpenDay: openDay),
      const BodyScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _index = i);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.edit_note), label: '記録'),
                NavigationDestination(icon: Icon(Icons.history), label: '履歴'),
                NavigationDestination(icon: Icon(Icons.monitor_weight_outlined), label: '身体'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), label: '設定'),
              ],
            ),
    );
  }
}
