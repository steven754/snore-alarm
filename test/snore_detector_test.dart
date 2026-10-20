import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snore_alarm/snore_detector.dart';

void main() {
  const fs = 16000;
  const fftSize = 2048;

  // 合成「鼾声样」信号：基频 + 多个谐波（谐波结构清晰、能量集中在低频）。
  List<double> snoreLike(int offset, double f0) {
    return List<double>.generate(fftSize, (i) {
      final t = (offset + i) / fs;
      double v = 0;
      for (int h = 1; h <= 8; h++) {
        v += math.sin(2 * math.pi * f0 * h * t) / h;
      }
      return v * 0.5;
    });
  }

  // 静音帧（模拟环境底噪）。
  List<double> silence(math.Random rng) {
    return List<double>.generate(
        fftSize, (_) => (rng.nextDouble() * 2 - 1) * 0.001);
  }

  test('持续鼾声样信号应触发唤醒', () {
    final d = SnoreDetector();
    final rng = math.Random(7);

    // 先喂静音帧，校准噪声底。
    for (int f = 0; f < 6; f++) {
      d.processFrame(silence(rng));
    }

    // 连续鼾声（持续 > durationSeconds=2.5s，约需 >20 帧）。
    var triggered = false;
    for (int f = 0; f < 30 && !triggered; f++) {
      final r = d.processFrame(snoreLike(f * fftSize, 150));
      if (r.alertTriggered) triggered = true;
    }
    expect(triggered, isTrue, reason: '持续鼾声应触发唤醒');
  });

  test('纯白噪声不应被识别为鼾声', () {
    final d = SnoreDetector();
    final rng = math.Random(42);
    for (int frame = 0; frame < 20; frame++) {
      final samples = List<double>.generate(
          fftSize, (_) => (rng.nextDouble() * 2 - 1) * 0.05);
      final r = d.processFrame(samples);
      expect(r.isSnore, isFalse, reason: '白噪声第 $frame 帧不应误判');
      expect(r.alertTriggered, isFalse);
    }
  });

  test('纯正弦（无谐波）不应被识别为鼾声', () {
    final d = SnoreDetector();
    final rng = math.Random(1);
    for (int f = 0; f < 6; f++) {
      d.processFrame(silence(rng));
    }
    for (int frame = 0; frame < 8; frame++) {
      final offset = frame * fftSize;
      final samples = List<double>.generate(fftSize, (i) {
        final t = (offset + i) / fs;
        return math.sin(2 * math.pi * 150 * t) * 0.5;
      });
      final r = d.processFrame(samples);
      expect(r.isSnore, isFalse, reason: '纯正弦第 $frame 帧不应误判（无谐波结构）');
    }
  });

  test('FFT 能正确定位基频（通过低频占比/谐波占比间接验证）', () {
    final d = SnoreDetector();
    final rng = math.Random(3);
    for (int f = 0; f < 6; f++) {
      d.processFrame(silence(rng));
    }
    // 基频 200Hz，谐波丰富：低频占比与谐波占比都应较高。
    final r = d.processFrame(snoreLike(0, 200));
    expect(r.lowRatio, greaterThan(0.5));
    expect(r.harmonicRatio, greaterThan(0.5));
  });
}
