#!/usr/bin/env bash
# ============================================================
#  鼾声唤醒 iOS 打包脚本 —— 在 macOS 上运行
#  用法：
#    1) 把整个 snore-alarm 目录拷贝到 Mac
#    2) 终端进入该目录
#    3) bash build_ios.sh
#  脚本会自动：装 Flutter → 补 iOS 工程 → 配权限 → 跑测试 → pod install
#  最后引导你在 Xcode 里签名并装到 iPhone / 导出 IPA。
# ============================================================

set -uo pipefail
cd "$(dirname "$0")"

echo "=============================================="
echo " 鼾声唤醒 iOS 打包脚本"
echo "=============================================="

# [1/8] 检查 Xcode
echo ""
echo "[1/8] 检查 Xcode..."
if ! xcode-select -p >/dev/null 2>&1; then
  echo "  ✗ 未检测到 Xcode 命令行工具，请先："
  echo "    1) 在 App Store 安装 Xcode"
  echo "    2) 打开一次 Xcode 接受许可"
  echo "    3) 执行: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
echo "  ✓ Xcode: $(xcode-select -p)"

# [2/8] 检查/安装 Flutter
echo ""
echo "[2/8] 检查 Flutter..."
if ! command -v flutter >/dev/null 2>&1; then
  echo "  未找到 Flutter，正在克隆 stable 分支（约 1GB，视网络而定）..."
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/development/flutter"
  export PATH="$PATH:$HOME/development/flutter/bin"
fi
flutter --version
echo "  ✓ Flutter 就绪"

# [3/8] 补全 iOS 平台目录（保留已写好的 lib/ 与 pubspec.yaml）
echo ""
echo "[3/8] 补全 iOS 平台目录..."
flutter create --org com.example --platforms=ios .
echo "  ✓ 已生成 ios/ 目录"

# [4/8] 配置 Info.plist（麦克风权限 + 后台音频）
echo ""
echo "[4/8] 配置 Info.plist（麦克风权限 + 后台音频）..."
PLIST="ios/Runner/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 需要使用麦克风检测睡眠鼾声，以便提醒你翻身" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription 需要使用麦克风检测睡眠鼾声，以便提醒你翻身" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string audio" "$PLIST" 2>/dev/null || true
echo "  ✓ Info.plist 已配置"

# [5/8] 配置 Podfile（permission_handler 麦克风权限宏）
echo ""
echo "[5/8] 配置 Podfile（麦克风权限宏）..."
python3 - <<'PY'
p = 'ios/Podfile'
s = open(p, encoding='utf-8').read()
if 'PERMISSION_MICROPHONE' not in s:
    old = "flutter_additional_ios_build_settings(target)"
    new = ("flutter_additional_ios_build_settings(target)\n"
           "    target.build_configurations.each do |config|\n"
           "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [\n"
           "        '$(inherited)',\n"
           "        'PERMISSION_MICROPHONE=1',\n"
           "      ]\n"
           "    end")
    assert old in s, 'Podfile 结构异常，请手动参考 README 添加权限宏'
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('  ✓ Podfile 已添加麦克风权限宏')
else:
    print('  ✓ Podfile 已含权限宏，跳过')
PY

# [6/8] 拉依赖
echo ""
echo "[6/8] flutter pub get..."
flutter pub get

# [7/8] 跑算法单元测试（验证 FFT/检测逻辑）
echo ""
echo "[7/8] 运行算法单元测试..."
flutter test

# [8/8] CocoaPods 安装
echo ""
echo "[8/8] CocoaPods 安装依赖..."
if ! command -v pod >/dev/null 2>&1; then
  echo "  ⚠ 未检测到 CocoaPods。请先安装："
  echo "    brew install cocoapods"
  echo "    （没有 Homebrew 先装：/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"）"
  echo "    装好后重新执行: cd ios && pod install"
else
  (cd ios && pod install)
fi

echo ""
echo "=============================================="
echo " ✅ 自动配置全部完成！"
echo "=============================================="
echo ""
echo "接下来是「签名 + 安装/打包」两步，必须在 Xcode 图形界面完成："
echo ""
echo "  A. 直接装到自己 iPhone（免费 Apple ID 即可，推荐；7 天后需重签一次）："
echo "     1) open ios/Runner.xcworkspace"
echo "     2) 数据线连接 iPhone 并「信任此电脑」"
echo "     3) Xcode 顶部设备栏选你的 iPhone"
echo "     4) 左侧选 Runner → TARGETS Runner → Signing & Capabilities"
echo "        → 勾选 Automatically manage signing"
echo "     5) Team 选你的 Apple ID（没有则：Xcode 菜单 Settings → Accounts → + 登录）"
echo "     6) Bundle Identifier 改成唯一的，例如 com.example.snorealarm2"
echo "     7) 点 ▶ Run，App 就会装到手机上"
echo ""
echo "  B. 导出 IPA 文件（付费开发者账号，或免费账号仅能装自己设备）："
echo "     1) Xcode 顶部设备选 Any iOS Device (arm64)"
echo "     2) 菜单 Product → Archive"
echo "     3) 弹窗 Organizer → Distribute App → 选导出方式"
echo "     4) 或命令行：flutter build ipa"
echo ""
echo "提示：免费 Apple ID 签名 7 天后失效，需重新插线 Run 一次即可续期。"
