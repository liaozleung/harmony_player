/**
 * 心跳上报负载 — 对齐 fids_player_electron HeartbeatService 与 Spring Boot
 * 服务端：hzwl-data-channel/src/main/java/.../controller/DeviceHeartbeatController.java
 * Endpoint: POST {dataChannelUrl}/device/heartbeat
 */

export interface HeartbeatPayload {
  deviceId: string;
  deviceName: string;
  status: 'online' | 'offline' | 'maintenance';
  timestamp: string;        // ISO 8601
  message: string;          // 摘要：cpu/mem/disk
  ipAddress: string;
  currentUrl: string | null;
  sysInfo: string;          // JSON 字符串：{ cpu, mem, disk }
  /** 鸿蒙端独有，便于驾驶舱区分设备类型 */
  platform: 'harmonyos';
}

export interface HeartbeatResponseData {
  /** 设备所属分组 ID（用于组合屏分页）*/
  groupId?: number;
  /** 透传 deviceId 用作分页识别 */
  myDeviceId?: string;
}
