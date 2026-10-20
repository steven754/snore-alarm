import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'snore_detector.dart';

enum ListenState { idle, listening }

/// 录音采集 + 检测循环。
///
/// 用 record 插件拿到 16bit PCM 流，转成 float 样本后按 FFT 帧长切帧，
/// 逐帧喂给 [SnoreDetector]，触发唤醒时回调 [onAlert]。
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final SnoreDetector detector = SnoreDetector();

  StreamSubscription<Uint8List>? _sub;
  final List<double> _buffer = [];

  /// 当前监听状态。
  final ValueNotifier<ListenState> state = ValueNotifier(ListenState.idle);

  /// 最近一帧的检测结果（供 UI 实时展示能量条/是否打鼾）。
  final ValueNotifier<FrameResult?> lastFrame = ValueNotifier(null);

  /// 检测到持续打鼾时的回调（连接唤醒服务）。
  void Function()? onAlert;

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) {
      return false;
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _buffer.clear();
    _sub = stream.listen(
      _onData,
      onError: (Object e) {
        debugPrint('录音流错误: $e');
      },
    );
    state.value = ListenState.listening;
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 已停止时可能抛错，忽略。
    }
    _buffer.clear();
    state.value = ListenState.idle;
  }

  void _onData(Uint8List bytes) {
    if (bytes.length < 2) return;
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    for (int i = 0; i < n; i++) {
      _buffer.add(bd.getInt16(i * 2, Endian.little) / 32768.0);
    }

    final fftSize = detector.config.fftSize;
    while (_buffer.length >= fftSize) {
      final frame = _buffer.sublist(0, fftSize);
      _buffer.removeRange(0, fftSize);
      final result = detector.processFrame(frame);
      lastFrame.value = result;
      if (result.alertTriggered) {
        onAlert?.call();
      }
    }
  }
}
