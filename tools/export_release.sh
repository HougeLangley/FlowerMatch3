#!/usr/bin/env bash
# 本地 release 打包：临时注入本机签名配置 → 导出 → 还原预设文件
# 签名文件约定位置（不入库）：
#   ~/.local/share/godot/keystores/release.keystore
#   ~/.local/share/godot/keystores/RELEASE_PASSWORD.txt
set -euo pipefail

KS_DIR="$HOME/.local/share/godot/keystores"
KS_FILE="$KS_DIR/release.keystore"
KS_PASS_FILE="$KS_DIR/RELEASE_PASSWORD.txt"
OUT="${1:-build/flowermatch3-release.apk}"
PRESET="export_presets.cfg"

if [[ ! -f "$KS_FILE" || ! -f "$KS_PASS_FILE" ]]; then
	echo "未找到本机 release 签名文件，请先生成（见 README「本地构建 → 发布签名」）" >&2
	exit 1
fi

KS_PASS=$(cat "$KS_PASS_FILE")
cp "$PRESET" "$PRESET.bak"
trap 'mv "$PRESET.bak" "$PRESET"' EXIT

sed -i "s|keystore/release=\"\"|keystore/release=\"$KS_FILE\"|" "$PRESET"
sed -i "s|keystore/release_user=\"\"|keystore/release_user=\"flowermatch3\"|" "$PRESET"
sed -i "s|keystore/release_password=\"\"|keystore/release_password=\"$KS_PASS\"|" "$PRESET"

godot --headless --export-release "Android" "$OUT"
echo "✅ release 包: $OUT"
