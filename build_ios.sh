#!/usr/bin/env bash
# ============================================================
#  鼾声唤醒 iOS 打包脚本 —— 在 macOS 上运行
#
#  用法：
#    cd snore-alarm
#    bash build_ios.sh
#
#  说明：
#    ios/ 平台工程已随仓库入库，本脚本只做「检查 + 准备 + 验证」，
#    不会执行 flutter create，因此不会覆盖你已经写好的 lib/ 和 pubspec.yaml。
#    最后一步签名必须在 Xcode 图形界面完成（Apple 要求）。
# ============================================================

set -uo pipefail
cd "$(dirname "$0")"

echo "=============================================="
echo " 鼾声唤醒 iOS 打包脚本"
echo "=============================================="

# [1/6] 检查 Xcode
echo ""
echo "[1/6] 检查 Xcode..."
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "  ✗ 未检测到完整 Xcode（只有 Command Line Tools 无法编译 iOS App）。请先："
  echo "    1) 在 App Store 安装 Xcode"
  echo "    2) 打开一次 Xcode 接受许可"
  echo "    3) 执行: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo ""
  echo "  💡 或者不装 Xcode：推送到 GitHub 触发 .github/workflows/build-ios.yml，"
  echo "     由 GitHub 的 macOS runner（自带 Xcode）云端出 IPA。"
  exit 1
fi
xcodebuild -version | sed 's/^/  /'

# [2/6] 检查/安装 Flutter
echo ""
echo "[2/6] 检查 Flutter..."
if ! command -v flutter >/dev/null 2>&1; then
  if [ -x "$HOME/development/flutter/bin/flutter" ]; then
    export PATH="$PATH:$HOME/development/flutter/bin"
  else
    echo "  未找到 Flutter，正在克隆 stable 分支（约 1GB，视网络而定）..."
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/development/flutter"
    export PATH="$PATH:$HOME/development/flutter/bin"
  fi
fi
flutter --version 2>&1 | sed 's/^/  /'

# [3/6] 拉依赖
echo ""
echo "[3/6] flutter pub get..."
flutter pub get

# [4/6] 跑算法单元测试
echo ""
echo "[4/6] 运行算法单元测试..."
flutter test

# [5/6] 幂等校验关键配置
echo ""
echo "[5/6] 校验 iOS 关键配置..."
python3 - <<'PY'
import plistlib, pathlib, re, sys

ok = True
plist_path = pathlib.Path('ios/Runner/Info.plist')
if plist_path.exists():
    with plist_path.open('rb') as f:
        plist = plistlib.load(f)
    if plist.get('NSMicrophoneUsageDescription'):
        print('  ✓ NSMicrophoneUsageDescription 已配置')
    else:
        print('  ✗ 缺 NSMicrophoneUsageDescription（iOS 会直接拒绝启动）'); ok = False
    if 'audio' in (plist.get('UIBackgroundModes') or []):
        print('  ✓ UIBackgroundModes 含 audio（锁屏后可继续录音）')
    else:
        print('  ✗ 缺 UIBackgroundModes: audio（锁屏即停）'); ok = False
else:
    print('  ✗ 找不到 ios/Runner/Info.plist'); ok = False

podfile = pathlib.Path('ios/Podfile')
if podfile.exists() and 'PERMISSION_MICROPHONE=1' in podfile.read_text(encoding='utf-8'):
    print('  ✓ Podfile 含 PERMISSION_MICROPHONE=1 宏')
else:
    print('  ✗ Podfile 缺 PERMISSION_MICROPHONE=1（不会弹麦克风授权框）'); ok = False

for name in ('Debug', 'Release'):
    p = pathlib.Path(f'ios/Flutter/{name}.xcconfig')
    if p.exists() and 'Pods/Target Support Files/Pods-Runner' in p.read_text(encoding='utf-8'):
        print(f'  ✓ Flutter/{name}.xcconfig 已 include Pods 配置')
    else:
        print(f'  ✗ Flutter/{name}.xcconfig 缺 Pods include（会链接失败）'); ok = False

sys.exit(0 if ok else 1)
PY
if [ $? -ne 0 ]; then
  echo "  ⚠️ 关键配置有缺失，请按上面的 ✗ 逐项修复后重跑。"
  exit 1
fi

# [6/6] CocoaPods
echo ""
echo "[6/6] CocoaPods 安装依赖..."
if ! command -v pod >/dev/null 2>&1; then
  echo "  ⚠ 未检测到 CocoaPods。请先安装：brew install cocoapods"
  echo "    装好后重新执行: cd ios && pod install"
else
  (cd ios && pod install)
fi

echo ""
echo "=============================================="
echo " ✅ 准备完成！"
echo "=============================================="
echo ""
echo "接下来是「签名 + 安装/打包」，必须在 Xcode 图形界面完成："
echo ""
echo "  A. 直接装到自己 iPhone（免费 Apple ID 即可，7 天后需重签一次）："
echo "     1) open ios/Runner.xcworkspace"
echo "     2) 数据线连接 iPhone 并「信任此电脑」"
echo "     3) Xcode 顶部设备栏选你的 iPhone"
echo "     4) 左侧选 Runner → TARGETS Runner → Signing & Capabilities"
echo "        → 勾选 Automatically manage signing"
echo "     5) Team 选你的 Apple ID（没有则：Xcode 菜单 Settings → Accounts → + 登录）"
echo "     6) Bundle Identifier 改成唯一的，例如 com.steven.snorealarm"
echo "     7) 点 ▶ Run，App 就会装到手机上"
echo ""
echo "  B. 导出 IPA 文件（付费开发者账号，或免费账号仅能装自己设备）："
echo "     1) Xcode 顶部设备选 Any iOS Device (arm64)"
echo "     2) 菜单 Product → Archive"
echo "     3) 弹窗 Organizer → Distribute App → 选导出方式"
echo "     4) 或命令行：flutter build ipa"
echo ""
echo "  C. 不装 Xcode，用云端出包（见 .github/workflows/build-ios.yml）："
echo "     git push  → GitHub Actions 自动产出未签名 IPA 构件"
echo ""
echo "提示：免费 Apple ID 签名 7 天后失效，需重新插线 Run 一次即可续期。"
