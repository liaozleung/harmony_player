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
  | 'displayRegion'  // 区域公告（主 Web 缩到 1-fraction，右/下侧 fraction 区域显示公告 HTML）
  | 'displayMarquee' // 屏底滚动字幕（V1 简化：在自由文本撤回前显示一行文字）
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
  /**
   * displayPage 覆盖层标志：
   * - true  + url 非空 → 临时覆盖（多媒体发布 / 自由文本短期推送），不持久化
   * - true  + url 空   → 撤回覆盖，恢复基础页面
   * - 缺省 / false     → 永久切换基础页面（写入 ConfigStore.displayUrl）
   */
  overlay?: boolean;
  /** setBrightness 用，0..1 或 0..100 */
  value?: number;
  /**
   * displayRegion 用：公告区域位置（默认 right）。
   * url 非空 = 设置区域公告；url 为空 = 清除区域公告，恢复主区域全屏
   */
  regionPosition?: 'bottom' | 'right';
  /** displayRegion 用：区域占比 0.1 ~ 0.5 */
  regionFraction?: number;
  /** displayMarquee 用：滚动文字内容（空字符串或缺省表示清除） */
  text?: string;
  /** displayMarquee 用：嵌入 fids_webpage 页脚 / 还是 player 原生底部条 */
  marqueeMode?: 'embedded' | 'overlay';
  /** OTA 占位 */
  version?: string;
  fileList?: MqttFileItem[];
}

/** eventBus 'regionChanged' 事件 payload */
export interface RegionChangePayload {
  url: string;                              // 空字符串表示清除
  position: 'bottom' | 'right';
  fraction: number;                         // 0.1 ~ 0.5
}
