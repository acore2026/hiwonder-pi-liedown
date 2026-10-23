#!/bin/bash
# dev_watchdog.sh — 永久优先连接 dev 热点
# 每 60 秒检查：当前不在 dev 且扫描可见 dev 时，切换过去
# （NetworkManager 优先级只在选网时生效，本脚本补上"连着别的网也会跳槽"的行为）
while true; do
    CURRENT=$(nmcli -t -f NAME con show --active 2>/dev/null | grep -v -e '^lo$' | head -1)
    if [ "$CURRENT" != "dev" ]; then
        if nmcli -f SSID dev wifi 2>/dev/null | grep -q '^dev'; then
            logger -t dev-watchdog "switching to dev (was: ${CURRENT:-none})"
            nmcli con up dev >/dev/null 2>&1
        fi
    fi
    sleep 60
done
