import 'dart:math' as math;

/// 鼾声检测配置。
///
/// 核心思路：鼾声是 100~400Hz 的准周期信号，能量集中在低频、谐波结构清晰。
/// 用「信噪比 + 低频能量占比 + 谐波清晰度」三重判定单帧，再按「持续时长」聚合，
/// 连续打鼾达到阈值才触发唤醒，避免一声咳嗽/翻身就误报。
class SnoreConfig {
  /// 采样率（Hz）。16k 足够覆盖鼾声基频与谐波，同时省电省算力。
  final int sampleRate = 16000;

  /// FFT 帧长（2 的幂）。2048 点 → 单帧 128ms，频率分辨率 7.8Hz。
  final int fftSize = 2048;

  /// 单帧时长（秒）。
  double get frameSeconds => fftSize / sampleRate;

  /// 鼾声频段上下限（Hz）。
  final double lowFreq = 100.0;
  final double highFreq = 400.0;

  /// 基频搜索范围（Hz）。
  final double f0Min = 70.0;
  final double f0Max = 500.0;

  /// 低频能量占比阈值（0~1）。可在运行时通过 UI 调节。
  double lowBandRatio = 0.55;

  /// 谐波能量占比阈值（0~1），衡量「周期性」。可在运行时调节。
  ///
  /// 取值 0.35：理想合成鼾声实测 0.43~0.61，白噪声仅 0.04、纯正弦 0.00，
  /// 0.35 能在两者之间留出足够余量；再高则真实鼾声（谐波结构弱于合成信号）
  /// 容易漏检。宁可漏一次也别整夜不响 —— 用「连续时长 + 冷却」兜底。
  double harmonicRatio = 0.35;

  /// 相对噪声底的最小信噪比（dB）。越低越灵敏（越容易触发）。
  double minSnrDb = 9.0;

  /// 连续打鼾多久才触发唤醒（秒）。
  double durationSeconds = 2.5;

  /// 触发唤醒后的冷却时间（秒），避免整夜反复震。
  double cooldownSeconds = 30.0;
}

/// 单帧检测结果。
class FrameResult {
  final bool isSnore; // 本帧是否判定为鼾声帧
  final bool alertTriggered; // 是否触发了唤醒
  final double rms;
  final double snrDb;
  final double lowRatio;
  final double harmonicRatio;

  /// 三项判定的逐项结果。
  ///
  /// 单独暴露出来是为了让 UI 能实时显示「当前卡在哪一项」——
  /// 否则用户只看到"没触发"，不知道该调哪个阈值，只能盲试。
  final bool snrOk; // 信噪比是否达标
  final bool lowOk; // 低频能量占比是否达标
  final bool harmonicOk; // 谐波清晰度是否达标

  const FrameResult({
    required this.isSnore,
    required this.alertTriggered,
    required this.rms,
    required this.snrDb,
    required this.lowRatio,
    required this.harmonicRatio,
    this.snrOk = false,
    this.lowOk = false,
    this.harmonicOk = false,
  });
}

/// 鼾声检测器。
///
/// 用法：把 PCM float 样本（-1..1）按 [fftSize] 切帧后逐帧喂给 [processFrame]。
class SnoreDetector {
  SnoreDetector({SnoreConfig? config}) : config = config ?? SnoreConfig();

  final SnoreConfig config;

  int _consecutiveHits = 0;
  int _framesSeen = 0;
  DateTime? _lastAlertAt;
  double _noiseFloor = 1e-6;

  /// 处理一帧（长度必须等于 config.fftSize），返回该帧的判定结果。
  FrameResult processFrame(List<double> samples) {
    assert(samples.length == config.fftSize,
        '帧长度应为 ${config.fftSize}，实际 ${samples.length}');

    // 1. 汉宁窗 + FFT，取幅度谱（前半）。
    final re = List<double>.from(samples);
    final im = List<double>.filled(config.fftSize, 0.0);
    _applyHann(re);
    _fft(re, im);
    final mag = List<double>.generate(config.fftSize ~/ 2, (k) {
      return math.sqrt(re[k] * re[k] + im[k] * im[k]);
    });

    // 2. 总能量（排除 DC 与 Nyquist 附近的高频）。
    final binHz = config.sampleRate / config.fftSize;
    final maxBin = (config.sampleRate / 2 / binHz).floor() - 1; // 略低于 Nyquist
    final lowBinLo = math.max(1, (config.lowFreq / binHz).round());
    final lowBinHi = math.min(maxBin, (config.highFreq / binHz).round());
    final f0BinLo = math.max(1, (config.f0Min / binHz).round());
    final f0BinHi = math.min(maxBin, (config.f0Max / binHz).round());

    double totalEnergy = 0.0;
    double lowEnergy = 0.0;
    for (int k = 1; k <= maxBin; k++) {
      final e = mag[k] * mag[k];
      totalEnergy += e;
      if (k >= lowBinLo && k <= lowBinHi) lowEnergy += e;
    }
    if (totalEnergy <= 0) totalEnergy = 1e-12;

    // 3. RMS 与噪声底。
    final rms = _rmsOf(samples);

    // 噪声底自适应估计：
    // - 校准期（前几帧）：快速逼近当前 RMS，假设开始监测时环境安静；
    // - 之后只在「安静帧」缓慢跟踪，鼾声帧（RMS 明显高于噪声底）不抬升噪声底，
    //   这样即使一次鼾声持续较久，噪声底也不会被污染、SNR 不会失真。
    if (_framesSeen < 4) {
      _noiseFloor = _noiseFloor * 0.5 + rms * 0.5;
    } else if (rms <= _noiseFloor * 3.0) {
      _noiseFloor = _noiseFloor * 0.9 + rms * 0.1;
    }
    _framesSeen++;

    final snrDb = 20 * math.log(rms / _noiseFloor) / math.ln10;

    // 4. 低频能量占比。
    final lowRatio = lowEnergy / totalEnergy;

    // 5. 基频 + 谐波清晰度。
    final f0Bin = _argMax(mag, f0BinLo, f0BinHi);
    final harmonicRatio = _harmonicRatio(mag, f0Bin, maxBin);

    // 6. 单帧判定（三项分别记录，便于 UI 显示卡在哪一项）。
    final snrOk = snrDb >= config.minSnrDb;
    final lowOk = lowRatio >= config.lowBandRatio;
    final harmonicOk = harmonicRatio >= config.harmonicRatio;
    final isSnore = snrOk && lowOk && harmonicOk;

    if (isSnore) {
      _consecutiveHits++;
    } else {
      _consecutiveHits = 0;
    }

    // 7. 时间聚合 + 冷却。
    bool alert = false;
    if (_consecutiveHits * config.frameSeconds >= config.durationSeconds) {
      final now = DateTime.now();
      final sinceLast =
          _lastAlertAt == null ? double.infinity : now.difference(_lastAlertAt!).inMilliseconds / 1000.0;
      if (sinceLast >= config.cooldownSeconds) {
        alert = true;
        _lastAlertAt = now;
      }
      _consecutiveHits = 0;
    }

    return FrameResult(
      isSnore: isSnore,
      alertTriggered: alert,
      rms: rms,
      snrDb: snrDb,
      lowRatio: lowRatio,
      harmonicRatio: harmonicRatio,
      snrOk: snrOk,
      lowOk: lowOk,
      harmonicOk: harmonicOk,
    );
  }

  // ---- 内部实现 ----

  double _rmsOf(List<double> x) {
    double s = 0;
    for (final v in x) {
      s += v * v;
    }
    return math.sqrt(s / x.length);
  }

  int _argMax(List<double> mag, int lo, int hi) {
    int best = lo;
    double bestVal = mag[lo];
    for (int k = lo + 1; k <= hi; k++) {
      if (mag[k] > bestVal) {
        bestVal = mag[k];
        best = k;
      }
    }
    return best;
  }

  /// 谐波清晰度：基频 f0 的 2~8 次谐波峰能量 / f0 之后到末次谐波的频段总能量。
  ///
  /// 对「谐波结构清晰」的周期信号（如鼾声），能量集中在各谐波峰上，比值接近 1；
  /// 对宽带噪声，谐波峰不突出，比值偏低。纯正弦（无谐波）比值趋于 0。
  ///
  /// 注意：分子必须取谐波峰中心 ±1 bin 的能量和，不能只取中心 bin。
  /// 汉宁窗下正弦能量会外泄到相邻 bin（能量比约 1 : 0.25 : 0.06），
  /// 只取中心 bin 时，理想谐波信号的比值也只到 0.37~0.47，
  /// 永远够不到 0.5 的阈值 —— 结果就是「完美鼾声也不触发」。
  double _harmonicRatio(List<double> mag, int f0Bin, int maxBin) {
    if (f0Bin < 2) return 0.0;
    double harmonic = 0.0;
    int lastCenter = f0Bin;
    for (int h = 2; h <= 8; h++) {
      final center = f0Bin * h;
      if (center - 1 > maxBin) break;
      lastCenter = center + 1;
      for (int k = center - 1; k <= center + 1 && k < mag.length; k++) {
        harmonic += mag[k] * mag[k];
      }
    }
    // 分母：基频之后到末次谐波之间的连续频段能量（不含基频本身）。
    double denom = 0.0;
    for (int k = f0Bin + 1; k <= lastCenter && k < mag.length; k++) {
      denom += mag[k] * mag[k];
    }
    if (denom <= 0) return 0.0;
    return harmonic / denom;
  }

  void _applyHann(List<double> x) {
    final n = x.length;
    for (int i = 0; i < n; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      x[i] *= w;
    }
  }

  /// 就地 radix-2 Cooley-Tukey FFT（复数输入，实部 re、虚部 im）。
  void _fft(List<double> re, List<double> im) {
    final n = re.length;
    // 位反转置换。
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    // 蝶形运算。
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wRe = math.cos(ang);
      final wIm = math.sin(ang);
      for (int i = 0; i < n; i += len) {
        double curRe = 1.0, curIm = 0.0;
        for (int k = 0; k < (len >> 1); k++) {
          final uRe = re[i + k];
          final uIm = im[i + k];
          final vRe = re[i + k + (len >> 1)] * curRe - im[i + k + (len >> 1)] * curIm;
          final vIm = re[i + k + (len >> 1)] * curIm + im[i + k + (len >> 1)] * curRe;
          re[i + k] = uRe + vRe;
          im[i + k] = uIm + vIm;
          re[i + k + (len >> 1)] = uRe - vRe;
          im[i + k + (len >> 1)] = uIm - vIm;
          final nRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = nRe;
        }
      }
    }
  }
}
