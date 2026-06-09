/**
 * 设备配置 — 字段与 fids_player_electron 端 DeviceConfig 完全对齐
 * 原文件位置：fids_player_electron/src/main/config.ts
 *
 * 持久化方式：@ohos.data.preferences（KV 存储），key 名与字段名相同
 */

export interface DeviceConfig {
  /** 设备唯一标识，必须与后台 devices.deviceId 一致 */
  deviceId: string;

  /** 设备显示名 */
  deviceName: string;

  /** 网卡 MAC，自动从系统读取 */
  macAddress: string;

  /** Next.js 后台地址（用于 displayUrl 引导 / 截图上传 / watchdog 上报） */
  serverUrl: string;

  /** Spring Boot 数据通道地址（心跳上报） */
  dataChannelUrl: string;

  /** MQTT broker 地址（不含 schema） */
  mqttBroker: string;

  /** MQTT 端口；走 WebSocket 子协议时应使用 broker 的 ws 端口（典型 8083） */
  mqttPort: number;

  /** MQTT 用户名（broker 启用认证时必填） */
  mqttUsername: string;

  /** MQTT 密码 */
  mqttPassword: string;

  /** 心跳间隔（秒），最小 5 */
  heartbeatInterval: number;

  /** 当前播放页面 URL；持久化以便重启后恢复 */
  displayUrl: string | null;

  /** 是否开机自启（KIOSK 模式需 EDM 配合） */
  autoStart: boolean;

  /** 是否全屏（默认数字标牌都全屏） */
  fullscreen: boolean;
}

export const DEFAULT_CONFIG: DeviceConfig = {
  deviceId: '',
  deviceName: '',
  macAddress: '',
  serverUrl: 'http://192.168.0.200:3000',
  dataChannelUrl: 'http://192.168.0.100:9203',
  mqttBroker: '192.168.0.200',
  mqttPort: 1883,
  mqttUsername: 'admin',
  mqttPassword: 'hzwl@12345',
  heartbeatInterval: 15,
  displayUrl: null,
  autoStart: false,
  fullscreen: true
};
