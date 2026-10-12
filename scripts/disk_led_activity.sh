#!/bin/bash

LOCK_FILE="/var/run/disk_led_activity.pid"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0
echo $$ > "$LOCK_FILE"

CLI="/usr/local/bin/ugreen_leds_cli"

# 初始化：硬碟微光維持 20，LAN 燈點亮
$CLI disk1 disk2 disk3 disk4 disk5 disk6 -brightness 20 >/dev/null 2>&1
$CLI netdev -color 255 255 255 -brightness 255 -on >/dev/null 2>&1

declare -A LAST_IO
declare -A IS_ACTIVE
declare -A LAST_SET_BRIGHT
declare -A DISK_RESTORE_TIME

LAST_NET_BYTES=0
NET_RESTORE_TIME=0
NET_IS_OFF=0

TICK=0

while true; do
    TICK=$((TICK + 1))
    CHECK_INDEX=$((TICK % 12))
    current_idx=0
    now=$(date +%s%3N)

    # --- 1. LAN 燈流量監控 ---
    net_traffic=$(awk '/eth0|eth1|bond0|br0/ {rx+=$2; tx+=$10} END {print rx+tx}' /proc/net/dev 2>/dev/null)
    net_traffic=${net_traffic:-0}

    if [ "$LAST_NET_BYTES" -ne 0 ] && [ "$net_traffic" -gt "$LAST_NET_BYTES" ]; then
        diff=$(( net_traffic - LAST_NET_BYTES ))
        if [ "$diff" -gt 8192 ] && [ "$NET_IS_OFF" -eq 0 ]; then
            $CLI netdev -off >/dev/null 2>&1
            NET_IS_OFF=1
            NET_RESTORE_TIME=$((now + 60))
        fi
    fi
    LAST_NET_BYTES=$net_traffic

    if [ "$NET_IS_OFF" -eq 1 ] && [ "$now" -ge "$NET_RESTORE_TIME" ]; then
        $CLI netdev -color 255 255 255 -brightness 255 -on >/dev/null 2>&1
        NET_IS_OFF=0
    fi

    # --- 2. 硬碟 I/O 與狀態監控 ---
    for devpath in /sys/block/sd[a-z]; do
        [ -e "$devpath" ] || continue
        dev=${devpath##*/}
        realpath=$(readlink -f "$devpath")

        if [[ "$realpath" =~ ata([0-9]+) ]]; then
            atanum="${BASH_REMATCH[1]}"

            case "$atanum" in
                2) slot=1 ;;
                3) slot=2 ;;
                4) slot=3 ;;
                5) slot=4 ;;
                1) slot=5 ;;
                6) slot=6 ;;
                *) slot="" ;;
            esac

            [ -n "$slot" ] || continue
            target_led="disk${slot}"

            # 輪流檢查休眠狀態
            if [ "$CHECK_INDEX" -eq "$current_idx" ] || [ -z "${IS_ACTIVE[$dev]}" ]; then
                st=$(timeout 0.2 hdparm -C "/dev/$dev" 2>/dev/null)
                if echo "$st" | grep -iqE "standby|sleeping"; then
                    IS_ACTIVE[$dev]=0
                elif echo "$st" | grep -iqE "active|idle"; then
                    IS_ACTIVE[$dev]=1
                fi
            fi
            current_idx=$((current_idx + 1))

            # 讀取 I/O
            if [ -r "/sys/block/${dev}/stat" ]; then
                read -r _ _ r_sec _ _ _ w_sec _ < "/sys/block/${dev}/stat" 2>/dev/null
                current_io=$(( ${r_sec:-0} + ${w_sec:-0} ))
            else
                current_io=0
            fi

            prev_io=${LAST_IO[$dev]:-0}
            restore_time=${DISK_RESTORE_TIME[$dev]:-0}

            # 偵測到讀寫時，立刻喚醒並觸發眨眼
            if [ "$prev_io" -ne 0 ] && [ "$current_io" -gt "$prev_io" ]; then
                IS_ACTIVE[$dev]=1
                if [ "$now" -ge "$restore_time" ]; then
                    $CLI "$target_led" -brightness 0 >/dev/null 2>&1
                    LAST_SET_BRIGHT[$dev]=0
                    DISK_RESTORE_TIME[$dev]=$((now + 60))
                fi
            fi

            # 決定基準亮度
            if [ "${IS_ACTIVE[$dev]}" -eq 1 ]; then
                base_bright=255
            else
                base_bright=20
            fi

            # 恢復常亮
            if [ "$now" -ge "${DISK_RESTORE_TIME[$dev]:-0}" ]; then
                if [ "${LAST_SET_BRIGHT[$dev]}" != "$base_bright" ]; then
                    $CLI "$target_led" -color 255 255 255 -brightness "$base_bright" >/dev/null 2>&1
                    LAST_SET_BRIGHT[$dev]=$base_bright
                fi
            fi

            LAST_IO[$dev]=$current_io
        fi
    done

    sleep 0.05
done
