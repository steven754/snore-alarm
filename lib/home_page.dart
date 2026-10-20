import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'alarm_service.dart';
import 'audio_service.dart';
import 'snore_detector.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioService _audio = AudioService();
  final AlarmService _alarm = AlarmService();

  bool _permissionGranted = false;
  int _alertCount = 0;
  DateTime? _lastAlertAt;

  @override
  void initState() {
    super.initState();
    _audio.onAlert = _onAlert;
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  void _onAlert() {
    _alarm.trigger();
    if (mounted) {
      setState(() {
        _alertCount++;
        _lastAlertAt = DateTime.now();
      });
    }
  }

  Future<void> _toggle() async {
    if (_audio.state.value == ListenState.listening) {
      await _audio.stop();
    } else {
      final ok = await _audio.start();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有麦克风权限，请到系统设置开启')),
        );
      }
    }
  }

  @override
  void dispose() {
    _audio.stop();
    _alarm.stop();
    super.dispose();
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('鼾声唤醒')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildLiveMetrics(),
          const SizedBox(height: 16),
          _buildSettings(),
          const SizedBox(height: 24),
          _buildStartButton(),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '手机插电放枕边，麦克风朝上\n检测到持续打鼾会播放提示音提醒你翻身',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<ListenState>(
          valueListenable: _audio.state,
          builder: (context, st, _) {
            final listening = st == ListenState.listening;
            return Row(
              children: [
                Icon(
                  listening ? Icons.graphic_eq : Icons.bedtime,
                  color: listening ? Colors.greenAccent : Colors.grey,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listening ? '监听中…' : '未开始',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _permissionGranted ? '麦克风已授权' : '麦克风未授权',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('已唤醒 $_alertCount 次',
                        style: const TextStyle(color: Colors.amber)),
                    const SizedBox(height: 4),
                    Text('最近 ${_fmtTime(_lastAlertAt)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveMetrics() {
    return ValueListenableBuilder<FrameResult?>(
      valueListenable: _audio.lastFrame,
      builder: (context, frame, _) {
        final rms = frame?.rms ?? 0.0;
        final level = (rms / 0.3).clamp(0.0, 1.0);
        final isSnore = frame?.isSnore ?? false;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('实时音量',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (isSnore)
                      const Text('🔊 检测到鼾声',
                          style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 12,
                    backgroundColor: Colors.white12,
                    color: isSnore ? Colors.redAccent : Colors.greenAccent,
                  ),
                ),
                const SizedBox(height: 12),
                _metric('信噪比 SNR', '${(frame?.snrDb ?? 0).toStringAsFixed(1)} dB'),
                _metric('低频占比', '${((frame?.lowRatio ?? 0) * 100).toStringAsFixed(0)}%'),
                _metric('谐波占比', '${((frame?.harmonicRatio ?? 0) * 100).toStringAsFixed(0)}%'),
                _buildCriteria(frame),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// 三项判定的实时状态。
  ///
  /// 单独显示是为了回答「为什么没触发」——只看到"没响"是无从下手，
  /// 看到哪一项是 ✗ 就知道该调哪个滑块，不用盲试。
  Widget _buildCriteria(FrameResult? frame) {
    if (frame == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          '开始监听后这里会实时显示三项判定状态',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _criterionChip('信噪比', frame.snrOk),
              const SizedBox(width: 6),
              _criterionChip('低频', frame.lowOk),
              const SizedBox(width: 6),
              _criterionChip('谐波', frame.harmonicOk),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '三项同时为 ✓ 才会触发提醒；哪项是 ✗ 就调对应的阈值',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _criterionChip(String label, bool ok) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: ok
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: ok
                ? Colors.greenAccent.withValues(alpha: 0.5)
                : Colors.redAccent.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          '${ok ? '✓' : '✗'} $label',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ok ? Colors.greenAccent : Colors.redAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    final cfg = _audio.detector.config;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('检测设置', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _slider(
              label: '灵敏度（信噪比阈值）',
              hint: '数值越低越灵敏、越容易触发',
              value: cfg.minSnrDb,
              min: 5,
              max: 18,
              divisions: 13,
              display: '${cfg.minSnrDb.toStringAsFixed(0)} dB',
              onChanged: (v) => setState(() => cfg.minSnrDb = v),
            ),
            _slider(
              label: '持续打鼾多久触发',
              hint: '达到该时长才提醒，避免误报',
              value: cfg.durationSeconds,
              min: 1,
              max: 5,
              divisions: 8,
              display: '${cfg.durationSeconds.toStringAsFixed(1)} 秒',
              onChanged: (v) => setState(() => cfg.durationSeconds = v),
            ),
            _slider(
              label: '低频能量占比阈值',
              hint: '鼾声能量集中在 100–400 Hz 的程度，要求越高越严格',
              value: cfg.lowBandRatio,
              min: 0.3,
              max: 0.9,
              divisions: 12,
              display: '${(cfg.lowBandRatio * 100).toStringAsFixed(0)}%',
              onChanged: (v) => setState(() => cfg.lowBandRatio = v),
            ),
            _slider(
              label: '谐波占比阈值',
              hint: '鼾声的周期性（谐波结构清晰度），环境吵时可适当调高',
              value: cfg.harmonicRatio,
              min: 0.1,
              max: 0.8,
              divisions: 14,
              display: '${(cfg.harmonicRatio * 100).toStringAsFixed(0)}%',
              onChanged: (v) => setState(() => cfg.harmonicRatio = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required String hint,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(display, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        Text(hint, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return ValueListenableBuilder<ListenState>(
      valueListenable: _audio.state,
      builder: (context, st, _) {
        final listening = st == ListenState.listening;
        return FilledButton.icon(
          onPressed: _toggle,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: listening ? Colors.redAccent : Colors.green,
          ),
          icon: Icon(listening ? Icons.stop : Icons.play_arrow),
          label: Text(
            listening ? '停止监听' : '开始监听',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}
