# UGREEN DXP6800 Pro LED Standalone Controller for unRAID

針對 UGREEN NAS（DXP6800 Pro 6-Bay 等機型）在 unRAID 7.x 上的獨立 LED 控制解決方案。

## 架構特點
- **核心升級免疫**：使用 Linux 原生 `i2c-dev` 搭配獨立二進位檔 `ugreen_leds_cli`，完全脫離編譯版 `.ko` 核心驅動與第三方插件。
- **低延遲硬碟 I/O 閃爍**：磁碟存取瞬間即時喚醒並反饋，解決硬碟 4～6 槽在傳統輪詢下的亮燈延遲問題。
- **LAN 指示燈整合**：解決 Aquantia 10GbE 網卡驅動不支援 `ethtool -p` 的限制，以 `/proc/net/dev` 流量差值觸發 `netdev` 前面板指示燈即時閃爍。
- **休眠節能**：硬碟 Standby/Sleep 時微光（亮度 20），Active 時全亮（亮度 255）。

## 開機自啟動設定 (`/boot/config/go`)
```bash
# 載入 Linux 原生 I2C 介面
modprobe i2c-dev

# 部署獨立 LED 工具與活動監控腳本
mkdir -p /usr/local/bin
cp /boot/config/led/bin/ugreen_leds_cli /usr/local/bin/ugreen_leds_cli
cp /boot/config/led/disk_led_activity.sh /usr/local/bin/disk_led_activity.sh
chmod +x /usr/local/bin/ugreen_leds_cli /usr/local/bin/disk_led_activity.sh

# 啟動 LED 背景監控
killall -9 disk_led_activity.sh 2>/dev/null
nohup /usr/local/bin/disk_led_activity.sh >/dev/null 2>&1 &
