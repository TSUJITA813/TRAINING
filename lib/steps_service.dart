import 'dart:async';

import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'store.dart';

class StepsResult {
  final int? steps;
  final String? error; // 日本語のエラーメッセージ
  final bool needsPermission;
  final bool needsInstall;
  const StepsResult({this.steps, this.error, this.needsPermission = false, this.needsInstall = false});
}

/// 歩数の取得（ヘルスコネクト / 端末センサー）
class StepsService {
  StepsService._();
  static final StepsService instance = StepsService._();

  final Health _health = Health();
  bool _configured = false;
  StreamSubscription<StepCount>? _sensorSub;
  final _sensorController = StreamController<int>.broadcast();

  /// センサーで計測した「今日の歩数」の更新通知
  Stream<int> get sensorTodaySteps => _sensorController.stream;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // ---------------- ヘルスコネクト ----------------

  Future<HealthConnectSdkStatus?> healthConnectStatus() async {
    try {
      await _configure();
      return await _health.getHealthConnectSdkStatus();
    } catch (_) {
      return null;
    }
  }

  Future<void> installHealthConnect() async {
    try {
      await _configure();
      await _health.installHealthConnect();
    } catch (_) {}
  }

  /// 権限をリクエストする。許可されたら true
  Future<bool> requestHealthConnectPermission() async {
    try {
      await _configure();
      await Permission.activityRecognition.request();
      return await _health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
    } catch (_) {
      return false;
    }
  }

  Future<StepsResult> fetchFromHealthConnect(DateTime day) async {
    try {
      await _configure();
      final status = await _health.getHealthConnectSdkStatus();
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        return const StepsResult(
          error: 'ヘルスコネクトが利用できません。インストールまたは更新が必要です。',
          needsInstall: true,
        );
      }
      final has = await _health.hasPermissions(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (has != true) {
        return const StepsResult(
          error: 'ヘルスコネクトの歩数の読み取りが許可されていません。',
          needsPermission: true,
        );
      }
      final start = DateTime(day.year, day.month, day.day);
      var end = start.add(const Duration(days: 1));
      final now = DateTime.now();
      if (end.isAfter(now)) end = now;
      final steps = await _health.getTotalStepsInInterval(start, end);
      return StepsResult(steps: steps ?? 0);
    } catch (e) {
      return const StepsResult(error: 'ヘルスコネクトから歩数を取得できませんでした。');
    }
  }

  // ---------------- 端末センサー ----------------
  //
  // Android の歩数センサー（TYPE_STEP_COUNTER）は「端末起動からの累計歩数」を返す。
  // アプリを開いたときの累計値との差分で今日の歩数を算出する。
  // 再起動で累計値がリセットされた場合は、それまでの歩数を繰り越す。

  Future<bool> startSensor() async {
    final st = await Permission.activityRecognition.request();
    if (!st.isGranted) return false;
    _sensorSub ??= Pedometer.stepCountStream.listen(
      _onSensor,
      onError: (_) {},
      cancelOnError: false,
    );
    return true;
  }

  void stopSensor() {
    _sensorSub?.cancel();
    _sensorSub = null;
  }

  void _onSensor(StepCount c) {
    final store = AppStore.instance;
    final s = store.sensorState;
    final todayKey = dateKey(today());
    final counter = c.steps;

    final lastCounter = (s['lastCounter'] as num?)?.toInt();
    final lastDate = s['lastDate'] as String?;

    if (lastDate != todayKey) {
      // 日付が変わって最初の計測。前回値からの増分は今日の歩数とみなす（概算）
      s['date'] = todayKey;
      s['carry'] = 0;
      final yesterdayKey = dateKey(today().subtract(const Duration(days: 1)));
      s['base'] = (lastDate == yesterdayKey && lastCounter != null && counter >= lastCounter)
          ? lastCounter
          : counter;
    } else if (lastCounter != null && counter < lastCounter) {
      // 再起動などでカウンターがリセットされた
      final base = (s['base'] as num?)?.toInt() ?? 0;
      s['carry'] = ((s['carry'] as num?)?.toInt() ?? 0) + (lastCounter - base);
      s['base'] = 0;
    }
    s['lastCounter'] = counter;
    s['lastDate'] = todayKey;

    final base = (s['base'] as num?)?.toInt() ?? counter;
    final carry = (s['carry'] as num?)?.toInt() ?? 0;
    final steps = (counter - base) + carry;
    _sensorController.add(steps);
    store.setSteps(today(), steps, StepSource.sensor);
  }
}
