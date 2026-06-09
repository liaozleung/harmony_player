# harmony_player

FIDS 航显播放器 — OpenHarmony 5.0 商业数字标牌端。

> 详细的设计与决策见：[`docs/harmony_player-规划方案.md`](../docs/harmony_player-规划方案.md)

---

## 一句话说明

**原生壳 + ArkWeb WebView 加载 fids_webpage**——渲染层与 macOS / Windows / Linux 端 100% 相同（同一份 fids_webpage 代码）；本工程只实现"原生壳"职责：MQTT、心跳、配置、看门狗、截图、系统控制。

---

## 快速开始

### 环境
- DevEco Studio 5.0+（[下载](https://developer.huawei.com/consumer/cn/deveco-studio/)）
- OpenHarmony SDK API 12+
- 真机调试：商业数字标牌或开发板（推荐 RK3568 / RK3588）

### 打开项目
1. DevEco Studio → File → Open → 选 `harmony_player/`
2. 等待 hvigor 自动同步依赖
3. File → Project Structure → Signing Configs → 自动生成调试证书

### 配置设备信息
首次运行后，**长按屏幕 5 秒**进入配置页，填写：
- `deviceId`（必填，与后台 devices.deviceId 一致）
- 服务器地址、数据通道地址、MQTT broker 等

### 真机运行
```
DevEco Studio → Run → 选目标设备 → Run 'entry'
```

---

## 项目结构

```
harmony_player/
├── AppScope/                   应用级配置（bundleName / version 等）
├── entry/                      主模块
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/   UIAbility 入口
│       │   ├── pages/          ArkUI 页面
│       │   │   ├── Index.ets       全屏 Web 组件，长按 5s 进 ConfigPage
│       │   │   └── ConfigPage.ets  设备配置表单
│       │   ├── services/       核心业务逻辑
│       │   │   ├── ConfigStore.ets       Preferences 持久化
│       │   │   ├── HeartbeatService.ets  HTTP 心跳上报
│       │   │   ├── MqttClient.ets        MQTT 订阅 + 指令路由（占位）
│       │   │   ├── Watchdog.ets          页面冻结检测
│       │   │   ├── SystemControl.ets     EDM / 普通签名 二态封装
│       │   │   ├── SystemInfo.ets        CPU/内存/磁盘/IP 采集
│       │   │   └── ScreenshotService.ets 截图上传（占位）
│       │   ├── types/          类型定义（与 Electron 端对齐）
│       │   │   ├── DeviceConfig.ets
│       │   │   ├── MqttCommand.ets
│       │   │   └── HeartbeatPayload.ets
│       │   └── utils/
│       │       ├── logger.ets
│       │       └── eventBus.ets
│       ├── resources/          国际化字符串、图标
│       └── module.json5        权限申请、Ability 配置
├── build-profile.json5
├── hvigorfile.ts
├── oh-package.json5
└── README.md（本文件）
```

---

## 当前状态

| 模块 | 状态 |
|------|------|
| 项目骨架 + Stage Model 配置 | ✅ 完成 |
| ConfigStore + 配置 UI | ✅ 完成 |
| HeartbeatService（HTTP 心跳） | ✅ 完成 |
| Watchdog（页面冻结检测） | ✅ 完成 |
| SystemInfo（CPU/内存/磁盘/IP） | ✅ 完成 |
| SystemControl（亮度/常亮） | ✅ 完成 |
| SystemControl（reboot/poweroff） | 🕐 Stub，等 EDM 证书 |
| MqttClient | 🕐 占位，等 mqtt.js 移植 |
| ScreenshotService | 🕐 骨架 |
| KIOSK 自启动 | 🕐 等 EDM + 厂商配合 |

---

## 待办（优先级排序）

### 🔴 P0：开发期就要做
1. **MQTT 客户端实现**：移植 mqtt.js 到 ArkTS（走 WebSocket 子协议），替换 `MqttClient.connect()` 内的 TODO 块。第一周完成可行性验证。
2. **真机 ArkWeb 兼容性验证**：在目标设备打开 fids_webpage 实际 URL，确认 framer-motion 翻页动画 / Canvas 看门狗 / 走马灯都正常。
3. **ScreenshotService 完整实现**：调 webview API 截屏 + image packer 编码 JPEG + multipart 上传。

### 🟡 P1：等 EDM 证书后启用
1. **SystemControl.reboot / poweroff**：替换 Stub 为 `@ohos.enterprise.deviceControl` 调用。
2. **module.json5 EDM 权限放开**：当前已注释，证书就绪后取消注释。
3. **KIOSK 自启动**：配合厂商 ROM 配置开机直起 + 锁定前台。

### 🟢 P2：完善
1. 配置 UI 优化（与 Electron 端体验对齐）
2. 日志结构化上报到驾驶舱
3. 文件同步 OTA 占位实现

---

## 协议约定（必须与 Electron 端保持一致）

### 心跳 HTTP
- POST `{dataChannelUrl}/device/heartbeat`
- payload 结构见 `types/HeartbeatPayload.ets`
- 鸿蒙端附加字段：`platform: "harmonyos"`

### MQTT 主题
- 订阅 `device/{deviceId}` + `device/{deviceId}/layout/#`
- 指令格式见 `types/MqttCommand.ets`

### 显示 URL
- 加载 fids_webpage URL（管理后台分配）
- URL 参数协议详见 `docs/fids_webpage-功能说明.md`

### 截图上传
- POST multipart/form-data 到 `{serverUrl}/api/fids-devices/screenshot`
- 字段：`deviceId` + `file`

---

## 调试 Tips

### 看实时日志
```
hdc shell "hilog | grep FidsPlayer"
```
（Logger 用 domain 0xFA00，可用此 ID 过滤）

### 查看 Preferences 配置
```
hdc shell "ls /data/app/el2/100/database/com.hzwl.fids.player/"
```

### 强制清理配置（重置到默认）
配置页"重置"按钮（待实现）；或：
```
hdc shell "rm -rf /data/app/el2/100/database/com.hzwl.fids.player/*"
```

### 跳过登录直接验证 Web
临时把 `Index.ets` 的 `currentUrl` 改成 `'http://192.168.0.100:3001/?page=universal&theme=ocean&dataChannelId=42'`，观察 ArkWeb 渲染情况。

---

## 与同级项目的关系

```
fids/                       Next.js + Payload 管理后台
fids_webpage/               React 列表页面（本项目用 ArkWeb 加载）
fids_player_electron/       桌面端（macOS / Windows / Linux）
hzwl-data-channel/          Spring Boot 数据通道
harmony_player/             【本项目】鸿蒙端
```

四个播放端共用同一套 fids_webpage 与同一套后端协议——**改 fids_webpage 自动惠及所有平台**。
