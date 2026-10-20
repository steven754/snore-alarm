# 鼾声唤醒（Snore Alarm）

一款用手机麦克风**实时检测打鼾、检测到持续打鼾后播放提示音/震动提醒你翻身**的 Flutter App。

> ⚠️ 仅供睡眠健康自测参考，不能替代医疗诊断。长期严重打鼾请去医院做睡眠监测（排查睡眠呼吸暂停 OSAS）。

## 功能

- 实时麦克风采集（16 kHz 单声道 PCM），前台服务保活
- 纯 DSP 鼾声识别（**无需训练模型、无需联网**）：
  - 短时傅里叶变换（FFT）频谱分析
  - 低频能量占比 + 基频谐波清晰度 + 相对噪声底信噪比，三重判定
  - 连续打鼾达到设定时长才触发，避免一声响误报
- 触发后播放系统提示音 + 震动（iOS 震动受限，主要靠声音）
- 冷却机制，避免整夜反复震
- 可调参数：灵敏度（信噪比阈值）、持续打鼾时长

## 目录结构

```
lib/
  main.dart              # 入口
  home_page.dart         # UI（状态、实时指标、参数调节、开始/停止）
  audio_service.dart     # 麦克风 PCM 流采集 + 分帧 + 检测循环
  snore_detector.dart    # 核心：FFT + 鼾声特征判定（含可调阈值）
  alarm_service.dart     # 唤醒：系统提示音 + 震动
test/
  snore_detector_test.dart  # 算法单元测试（合成信号验证识别/误报抑制）
```

## 环境要求

- macOS + Xcode（编译 iOS 必须，Apple 硬性要求）
- Flutter SDK ≥ 3.3（[安装](https://docs.flutter.dev/get-started/install/macos)）
- 一台 iPhone + Apple ID（安装到真机需要签名）

## 快速开始（Mac）

> 💡 更省事：直接运行 `bash build_ios.sh`，会自动完成下面「补目录→配权限→跑测试→pod install」全部步骤，最后引导你在 Xcode 里签名安装/导出 IPA。下面的手动步骤等价于脚本做的事。

```bash
cd snore-alarm

# 1) 补全 iOS/Android 平台目录（会生成 ios/、android/，保留你已写好的 lib/）
flutter create --org com.example --platforms=ios,android .

# 2) 拉依赖
flutter pub get

# 3) 跑一遍算法单元测试，确认 FFT/检测逻辑正确
flutter test

# 4) 运行（连上 iPhone，或先用模拟器/Android 试）
flutter run
```

## iOS 必须配置（否则没权限、锁屏即停）

### 1) 麦克风权限描述 —— `ios/Runner/Info.plist`

在 `<dict>` 内加入：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要使用麦克风来检测睡眠时的鼾声，以便提醒你翻身</string>

<!-- 锁屏后继续后台录音 + 播放提示音（关键，缺了锁屏就停） -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### 2) permission_handler 权限宏 —— `ios/Podfile`

`permission_handler` 默认不启用任何权限，必须在 Podfile 的 `post_install` 里声明麦克风：

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

改完 `Podfile` 后重新 `cd ios && pod install && cd ..`。

## 安装到自己的 iPhone（签名）

| 方式 | 说明 |
|---|---|
| 免费个人签名 | 在 Xcode 用你自己的 Apple ID 登录，签名后安装，**7 天后过期需重签** |
| 付费开发者账号 | 99 美元/年，可走 TestFlight、无需频繁重签 |
| 模拟器 / Android | 直接 `flutter run`，无签名问题 |

签名后打开 Xcode（`open ios/Runner.xcworkspace`）→ 选你的设备 → 在 Signing 里勾选团队 → Run。

## 参数说明

| 参数 | 默认 | 说明 |
|---|---|---|
| 灵敏度（信噪比阈值） | 9 dB | 越低越灵敏、越容易触发。环境吵可调高 |
| 持续打鼾时长 | 2.5 s | 连续打鼾超过该时长才提醒 |
| 冷却时间 | 30 s | 提醒后隔多久才能再次提醒（代码内 `cooldownSeconds`） |
| 低频占比阈值 | 0.55 | 鼾声能量集中在 100–400 Hz 的程度 |
| 谐波占比阈值 | 0.5 | 谐波结构清晰度（周期性） |

## 算法原理（简述）

鼾声是 **100–300 Hz 的低频准周期信号**（上气道狭窄振动产生，谐波丰富）。检测流程：

1. 16 kHz 采样，每 2048 样本（128 ms）一帧，加汉宁窗
2. 2048 点 FFT → 幅度谱
3. 计算：帧能量 RMS、低频段(100–400 Hz)能量占比、基频 f0（70–500 Hz 内最大峰）及 2~8 次谐波清晰度、相对噪声底的信噪比（噪声底只在安静帧自适应跟踪，鼾声帧不抬升）
4. 单帧命中 = 信噪比达标 且 低频占比达标 且 谐波清晰度达标
5. 连续命中时长 ≥ 设定时长 → 触发唤醒，进入冷却期

## 已知限制（诚实说明）

- **准确率非 100%**：环境噪音、同床者打鼾、风扇/空调低频噪声可能误报。请用 UI 里的实时指标（信噪比/低频占比/谐波占比）观察，再微调阈值。
- **耗电**：整晚录音，请插电并放枕边、麦克风朝上。
- **iOS 震动受限**：系统不允许 App 后台随意震动，iPhone 上主要靠**提示音**叫醒；Android 可自由持续震动。
- **App Store 上架**：后台录音属敏感权限，审核需合理解释用途；自用的话个人签名即可，无需上架。

## 免责声明

本 App 仅作睡眠自测与提醒，检测结果不构成医疗建议。若打鼾伴随呼吸暂停、白天嗜睡等症状，请及时就医。
