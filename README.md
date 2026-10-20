# 鼾声唤醒（Snore Alarm）

一款用手机麦克风**实时检测打鼾、检测到持续打鼾后播放提示音/震动提醒你翻身**的 Flutter App。

> ⚠️ 仅供睡眠健康自测参考，不能替代医疗诊断。长期严重打鼾请去医院做睡眠监测（排查睡眠呼吸暂停 OSAS）。

## 功能

- 实时麦克风采集（16 kHz 单声道 PCM），后台音频模式保活（锁屏继续录音）
- 纯 DSP 鼾声识别（**无需训练模型、无需联网**）：
  - 短时傅里叶变换（FFT）频谱分析
  - 低频能量占比 + 基频谐波清晰度 + 相对噪声底信噪比，三重判定
  - 连续打鼾达到设定时长才触发，避免一声响误报
- 触发后播放系统提示音 + 震动（iOS 震动受限，主要靠声音）
- 冷却机制，避免整夜反复震
- 4 个可调参数：灵敏度（信噪比阈值）、持续打鼾时长、低频占比阈值、谐波占比阈值

## 目录结构

```
lib/
  main.dart              # 入口
  home_page.dart         # UI（状态、实时指标、参数调节、开始/停止）
  audio_service.dart     # 麦克风 PCM 流采集 + 分帧 + 检测循环
  snore_detector.dart    # 核心：FFT + 鼾声特征判定（含可调阈值）
  alarm_service.dart     # 唤醒：系统提示音 + 震动
ios/                     # iOS 平台工程（已入库，含权限配置）
android/                 # Android 平台工程（已入库）
test/
  snore_detector_test.dart  # 算法单元测试（合成信号验证识别/误报抑制）
.github/workflows/
  build-ios.yml          # 云端构建 IPA（无需本机装 Xcode）
build_ios.sh             # 本机打包脚本（检查环境 + 准备 + 引导签名）
```

## 环境要求

- **iOS 15.0 或更高**（Flutter 3.47 的最低部署目标）
- macOS + Xcode（编译 iOS 必须，Apple 硬性要求）—— 或直接用云端构建，见下文
- Flutter SDK ≥ 3.3（[安装](https://docs.flutter.dev/get-started/install/macos)）
- 一台 iPhone + Apple ID（安装到真机需要签名）

## 快速开始（Mac）

> 💡 最省事的两条路：
> - **本机打包**：`bash build_ios.sh`，自动完成环境检查 → 拉依赖 → 跑测试 → 校验权限配置 → pod install，最后引导你在 Xcode 里签名安装。
> - **不用装 Xcode**：推送到 GitHub，Actions 自动出 IPA（见「云端出包」章节）。

```bash
cd snore-alarm

# 1) 拉依赖
flutter pub get

# 2) 跑一遍算法单元测试，确认 FFT/检测逻辑正确
flutter test

# 3) 运行（连上 iPhone，或先用模拟器/Android 试）
flutter run
```

> `ios/` 和 `android/` 平台工程已随仓库入库，**不需要**再执行 `flutter create`（那会覆盖你写好的 `lib/`）。

## iOS 权限配置（已配好，改造时注意）

### 1) 麦克风权限描述 —— `ios/Runner/Info.plist`

已包含：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要使用麦克风检测睡眠时的鼾声，以便提醒你翻身</string>

<!-- 锁屏后继续后台录音 + 播放提示音（关键，缺了锁屏就停） -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### 2) permission_handler 权限宏 —— `ios/Podfile`

`permission_handler` 默认不启用任何权限。**缺了下面的宏，iOS 上 `Permission.microphone.request()` 是空操作，App 不会弹「允许使用麦克风」授权框，`record` 拿不到授权 → 永远录不到音。**

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

### 3) SPM 必须关闭 —— `pubspec.yaml`

Flutter 3.27+ 默认用 Swift Package Manager 集成插件，**拿不到上面那个宏**。所以本项目按项目关闭了 SPM：

```yaml
flutter:
  config:
    enable-swift-package-manager: false
```

### 4) xcconfig 必须 include Pods 配置 —— `ios/Flutter/Debug.xcconfig` / `Release.xcconfig`

自己带 Podfile 时，Flutter 工具**不会**自动注入这一行，缺了会导致插件符号链接失败：

```
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"
#include "Generated.xcconfig"
```

`build_ios.sh` 第 5 步会自动校验以上 4 项，缺哪项会直接报 ✗。

## 安装到自己的 iPhone

### 方式 A：Xcode 签名安装（免费 Apple ID 即可）

| 方式 | 说明 |
|---|---|
| 免费个人签名 | Xcode 里用你自己的 Apple ID 登录，签名后安装，**7 天后过期需重签** |
| 付费开发者账号 | 99 美元/年，可走 TestFlight、无需频繁重签 |
| 模拟器 / Android | 直接 `flutter run`，无签名问题 |

签名后打开 Xcode（`open ios/Runner.xcworkspace`）→ 选你的设备 → 在 Signing 里勾选团队 → Run。

### 方式 B：云端出 IPA（推荐给不想装 Xcode 的人）

`.github/workflows/build-ios.yml` 会在 GitHub 的 macOS runner（自带 Xcode）上出包：

```bash
git push origin main
gh run list        # 看进度
gh run download    # 下载 snore-alarm-ipa 构件
```

产物是 **未签名** 的 `snore-alarm-unsigned.ipa`（没有开发者证书，任何人都能重新签名）：

- **免费 Apple ID**：用 [Sideloadly](https://sideloadly.io)（macOS/Windows）拖入 IPA + 输入自己的 Apple ID 即可装到手机，**7 天有效期**。AltStore 同样可行。
- **付费开发者账号**：用你的证书签一遍，或走 TestFlight 分发。

> 未签名 IPA 不能直接点开安装，必须由上述工具用你的 Apple ID 重签——这也是为什么本机没有任何证书也能把 App 装进 iPhone。

## 参数说明

| 参数 | 默认 | 说明 |
|---|---|---|
| 灵敏度（信噪比阈值） | 9 dB | 越低越灵敏、越容易触发。环境吵可调高 |
| 持续打鼾时长 | 2.5 s | 连续打鼾超过该时长才提醒 |
| 低频占比阈值 | 55% | 鼾声能量集中在 100–400 Hz 的程度 |
| 谐波占比阈值 | 35% | 鼾声的周期性（谐波结构清晰度） |
| 冷却时间 | 30 s | 提醒后隔多久才能再次提醒（代码内 `cooldownSeconds`） |

### 怎么调参（重要）

阈值是**按你的卧室环境**定的，App 里实时显示三个指标，照着调：

1. 先在安静环境点「开始监听」，看 **信噪比 SNR** 稳定在多少 → 把它设成「最低触发值 + 2~3 dB」
2. 实际打鼾时看 **谐波占比** 峰值到多少 → 阈值设成峰值的 80%
3. 环境有风扇/空调等低频噪声时，看 **低频占比** 会不会被顶高 → 必要时把低频阈值调高
4. 误报多 → 调高「持续打鼾多久触发」；漏报多 → 调低到 1.5 s

## 算法原理（简述）

鼾声是 **100–300 Hz 的低频准周期信号**（上气道狭窄振动产生，谐波丰富）。检测流程：

1. 16 kHz 采样，每 2048 样本（128 ms）一帧，加汉宁窗
2. 2048 点 FFT → 幅度谱
3. 计算：帧能量 RMS、低频段(100–400 Hz)能量占比、基频 f0（70–500 Hz 内最大峰）及 2~8 次谐波清晰度、相对噪声底的信噪比（噪声底只在安静帧自适应跟踪，鼾声帧不抬升）
4. 单帧命中 = 信噪比达标 且 低频占比达标 且 谐波清晰度达标
5. 连续命中时长 ≥ 设定时长 → 触发唤醒，进入冷却期

> **谐波清晰度的坑（已修）**：分子不能只取谐波峰的**中心 bin**——汉宁窗下正弦能量会外泄到相邻 bin（能量比约 1 : 0.25 : 0.06），只取中心 bin 会让理想谐波信号的比值也只到 0.37，永远够不到 0.5 的阈值，**结果就是「完美鼾声也不触发」**。改成取中心 ±1 bin 的能量和后，实测：理想鼾声 0.43~0.61、白噪声 0.04、纯正弦 0.00，判别力正常。

## 已知限制（诚实说明）

- **准确率非 100%**：环境噪音、同床者打鼾、风扇/空调低频噪声可能误报。请用 UI 里的实时指标观察，再微调阈值。
- **耗电**：整晚录音，请插电并放枕边、麦克风朝上。
- **iOS 震动受限**：系统不允许 App 后台随意震动，iPhone 上主要靠**提示音**叫醒；Android 可自由持续震动。
- **iOS 静音键**：系统提示音在静音模式下可能不响，睡前把静音键拨到响铃位置。
- **免费签名 7 天过期**：需要重签一次；付费账号或 TestFlight 可长期使用。
- **App Store 上架**：后台录音属敏感权限，审核需合理解释用途；自用的话个人签名即可，无需上架。

## 免责声明

本 App 仅作睡眠自测与提醒，检测结果不构成医疗建议。若打鼾伴随呼吸暂停、白天嗜睡等症状，请及时就医。
