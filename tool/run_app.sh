#!/usr/bin/env bash
# 一键启动模拟器并运行拍鸟伴侣（Git Bash / Claude Code 环境）
# 用法:
#   bash tool/run_app.sh          # 默认 bird flavor
#   bash tool/run_app.sh birdV1   # V1 flavor
#
# 依次处理: JDK 17+ 检查 → 启动模拟器并等待就绪 → pub get → flutter run
set -euo pipefail

FLUTTER="${FLUTTER:-/d/code/flutterSetting/bin/flutter}"
ADB="${ADB:-/d/code/Android/Sdk/platform-tools/adb}"
EMULATOR_ID="${EMULATOR_ID:-Medium_Phone_API_36.1}"
FLAVOR="${1:-bird}"

# 缓存目录重定向到 E 盘，避免写满 C 盘（2026-09-05 已清理过一次 C 盘 .gradle）
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-E:\\dev-cache\\gradle}"
export PUB_CACHE="${PUB_CACHE:-E:\\dev-cache\\pub}"

# 1. Gradle/AGP 需要 JDK 17+。本机 JAVA_HOME 指向 JDK 8，自动切换到 Android Studio 自带 JBR (JDK 21)。
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/java}"
JAVA_BIN="${JAVA_BIN:-java}"
JAVA_VERSION_LINE="$("$JAVA_BIN" -version 2>&1 | head -1)"
JAVA_VER="$(printf '%s' "$JAVA_VERSION_LINE" | sed -E 's/.*version "?([0-9]+).*/\1/')"
if [ -n "$JAVA_VER" ] && [ "$JAVA_VER" -lt 17 ] 2>/dev/null; then
  echo "==> JAVA_HOME 版本过低（$JAVA_VERSION_LINE），改用 Android Studio JBR (JDK 21)"
  export JAVA_HOME="/d/code/Android_Studio/jbr"
fi

# 2. 确保有已启动的 Android 设备，否则启动模拟器并等待 boot 完成
if ! "$ADB" devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  echo "==> 启动模拟器 $EMULATOR_ID ..."
  "$FLUTTER" emulators --launch "$EMULATOR_ID"
  "$ADB" wait-for-device
  for _ in $(seq 1 40); do
    [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 3
  done
  if [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; then
    echo "!! 模拟器启动超时，请手动检查 emulator 窗口" >&2
    exit 1
  fi
  echo "==> 模拟器已就绪"
fi
DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
[ -n "$DEVICE" ] || { echo "!! 没有可用的 Android 设备" >&2; exit 1; }
echo "==> 设备 $DEVICE 在线，flavor=$FLAVOR"

# 3. 依赖 + 运行（必须带 --flavor，项目有 bird / birdV1 两个 flavor）
"$FLUTTER" pub get
exec "$FLUTTER" run --flavor "$FLAVOR" -d "$DEVICE"
