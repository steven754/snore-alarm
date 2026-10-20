import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// 唤醒服务：播放系统提示音 + 震动。
///
/// 注意平台差异：
/// - Android：可自由震动。
/// - iOS：系统不允许 App 后台随意震动，主要靠「系统提示音」；
///   vibration 插件在 iOS 上会退化为单次系统震动（AudioServices），能力有限。
class AlarmService {
  bool _alarming = false;

  /// 触发一次唤醒（约 8 秒，期间重复提示音）。
  Future<void> trigger() async {
    if (_alarming) return;
    _alarming = true;

    // 初始声音 + 震动。
    await SystemSound.play(SystemSoundType.alert);
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: const [0, 400, 300, 400, 300, 400]);
    }

    // 持续提醒，期间每 1.5 秒重复一次提示音，直到满 8 秒。
    final start = DateTime.now();
    while (_alarming && DateTime.now().difference(start).inSeconds < 8) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!_alarming) break;
      await SystemSound.play(SystemSoundType.alert);
    }

    await Vibration.cancel();
    _alarming = false;
  }

  /// 立即停止当前提醒。
  void stop() {
    _alarming = false;
    Vibration.cancel();
  }

  bool get isAlarming => _alarming;
}
