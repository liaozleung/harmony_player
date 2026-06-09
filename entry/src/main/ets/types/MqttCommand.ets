/**
 * MQTT 指令负载格式 — 与 fids_player_electron / Next.js 后端协议对齐
 *
 * Topic 约定：
 *   device/{deviceId}            ← 单设备指令
 *   device/{deviceId}/layout/#   ← 布局相关（保留扩展位）
 *
 * Payload 是 JSON 字符串，至少含 action 字段。
 */

export type MqttAction =
  | 'displayPage'    // 切换显示 URL
  | 'refreshPage'    // 刷新当前页面
  | 'restart'        // 整机重启（需 EDM）
  | 'shutdown'       // 整机关机（需 EDM）
  | 'monitorOn'      // 开屏（普通签名，亮度/唤醒）
  | 'monitorOff'     // 关屏（普通签名时用 brightness=0；EDM 时用 lockScreen）
  | 'setBrightness'  // 设置亮度
  | 'screenshot'     // 主动截图上传
  | 'startVnc'       // 启动 VNC（V1 不支持，记日志）
  | 'stopVnc';       // 停止 VNC（V1 不支持，记日志）

/** OTA 用，下载列表的单项 */
export interface MqttFileItem {
  url: string;
  path: string;
  md5: string;
}

export interface MqttCommand {
  action: MqttAction;
  /** displayPage 用 */
  url?: string;
  /** setBrightness 用，0..1 */
  value?: number;
  /** OTA 占位 */
  version?: string;
  fileList?: MqttFileItem[];
}
