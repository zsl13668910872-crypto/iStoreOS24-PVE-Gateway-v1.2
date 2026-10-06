#!/bin/sh
# 安装插件包；任何一个缺失都直接失败（不允许静默跳过）
set -e

./scripts/feeds install luci-app-openclash
./scripts/feeds list | grep -q "^luci-app-openclash" || { echo "FATAL: feed 中不存在 luci-app-openclash"; exit 1; }
echo "OK: luci-app-openclash"
