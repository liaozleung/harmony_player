import http from '@ohos.net.http';
import { ConfigStore } from './ConfigStore';
import { SystemInfo } from './SystemInfo';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';
import { HeartbeatPayload } from '../types/HeartbeatPayload';

const TAG = 'HeartbeatService';
const HTTP_TIMEOUT = 10_000;

interface PageLoadedMessage {
  event: 'page_loaded';
  url: string;
}

interface DisplayUrlResponse {
  success: boolean;
  displayUrl?: string;
}

/** hzwl-data-channel /device/heartbeat 响应体 */
interface HeartbeatRespEnvelope {
  code: number;
  msg?: string;
  data?: HeartbeatRespData;
}

interface HeartbeatRespData {
  myDeviceId?: string;
  groupId?: number | null;
  currentDisplayUrl?: string | null;
}

/**
 * HTTP 心跳上报 — 对应 Spring Boot /device/heartbeat
 *
 * 特性：
 *   - 单例
 *   - 启动后立即发一次，然后按 heartbeatInterval 周期循环
 *   - 配置变更时自动重启计时
 *   - 上报后解析 groupId / myDeviceId
 */
export class HeartbeatService {
  private static instance: HeartbeatService | null = null;
  private timer: number | null = null;
  private displayUrlBootstrapped = false;

  static getInstance(): HeartbeatService {
    if (!HeartbeatService.instance) HeartbeatService.instance = new HeartbeatService();
    return HeartbeatService.instance;
  }

  start(): void {
    eventBus.on('configChanged', () => this.restart());
    this.restart();
  }

  stop(): void {
    if (this.timer !== null) { clearInterval(this.timer); this.timer = null; }
  }

  private restart(): void {
    this.stop();
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.deviceId || !cfg.dataChannelUrl) {
      Logger.info(TAG, 'deviceId / dataChannelUrl 未配置，跳过启动');
      return;
    }
    const intervalSec = Math.max(cfg.heartbeatInterval, 5);
    Logger.info(TAG, `心跳已启动: ${intervalSec}s, 目标 ${cfg.dataChannelUrl}/device/heartbeat`);
    this.beat();
    this.timer = setInterval(() => this.beat(), intervalSec * 1000);
  }

  /** 单次心跳 */
  private async beat(): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.deviceId || !cfg.dataChannelUrl) return;
    try {
      const sys = await SystemInfo.collect();
      const ip = await SystemInfo.getIpAddress();
      const message = `heartbeat | cpu:${sys.cpu}% mem:${sys.mem}% disk:${sys.disk}%`;
      const payload: HeartbeatPayload = {
        deviceId: cfg.deviceId,
        deviceName: cfg.deviceName || cfg.deviceId,
        status: 'online',
        timestamp: new Date().toISOString(),
        message,
        ipAddress: ip,
        currentUrl: cfg.displayUrl,
        sysInfo: JSON.stringify(sys),
        platform: 'harmonyos'
      };
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request(
        `${cfg.dataChannelUrl}/device/heartbeat`,
        {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify(payload),
          connectTimeout: HTTP_TIMEOUT,
          readTimeout: HTTP_TIMEOUT
        }
      );
      httpRequest.destroy();
      if (resp.responseCode === 200) {
        Logger.info(TAG, '心跳成功');
        // 解析响应里的 currentDisplayUrl，如果跟本地缓存不同则自动切换页面
        // （替代 MQTT displayPage 命令，靠每 15s 心跳的 server→player 回带实现配置同步）
        try {
          const env = JSON.parse(resp.result.toString()) as HeartbeatRespEnvelope;
          const serverUrl = env?.data?.currentDisplayUrl;
          if (typeof serverUrl === 'string' && serverUrl.length > 0 && serverUrl !== cfg.displayUrl) {
            Logger.info(TAG, `心跳响应带来新 displayUrl: ${serverUrl}（旧: ${cfg.displayUrl ?? '空'}）→ 切换`);
            await ConfigStore.getInstance().setDisplayUrl(serverUrl);
          }
        } catch (parseErr) {
          Logger.warn(TAG, '解析心跳响应失败', parseErr);
        }
        // 冷启动后第一次心跳 → 引导 displayUrl（兼容设备首次开机 + server 也没分配 page 的情况）
        if (!this.displayUrlBootstrapped && !cfg.displayUrl) {
          this.displayUrlBootstrapped = true;
          this.bootstrapDisplayUrl();
        }
      } else {
        Logger.warn(TAG, `心跳响应异常: ${resp.responseCode}`);
      }
    } catch (e) {
      Logger.error(TAG, '心跳失败', e);
    }
  }

  /** 冷启动从 Next.js 拉取一次 displayUrl */
  private async bootstrapDisplayUrl(): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.serverUrl || !cfg.deviceId) return;
    try {
      const httpRequest = http.createHttp();
      const url = `${cfg.serverUrl}/api/device-status-logs/display-url?deviceId=${encodeURIComponent(cfg.deviceId)}`;
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: HTTP_TIMEOUT,
        readTimeout: HTTP_TIMEOUT
      });
      httpRequest.destroy();
      if (resp.responseCode === 200) {
        const body = JSON.parse(resp.result.toString()) as DisplayUrlResponse;
        if (body.success && body.displayUrl) {
          await ConfigStore.getInstance().setDisplayUrl(body.displayUrl);
          Logger.info(TAG, '冷启动 displayUrl 引导成功:', body.displayUrl);
        }
      }
    } catch (e) {
      Logger.warn(TAG, 'bootstrapDisplayUrl 失败', e);
    }
  }

  /** 收到 displayPage MQTT 后延迟 3s 上报 page_loaded（与 Electron 端对齐） */
  reportPageLoaded(url: string): void {
    setTimeout(async (): Promise<void> => {
      const cfg = ConfigStore.getInstance().getAll();
      if (!cfg.deviceId || !cfg.dataChannelUrl) return;
      try {
        const sys = await SystemInfo.collect();
        const ip = await SystemInfo.getIpAddress();
        const messageObj: PageLoadedMessage = { event: 'page_loaded', url };
        const payload: HeartbeatPayload = {
          deviceId: cfg.deviceId,
          deviceName: cfg.deviceName || cfg.deviceId,
          status: 'online',
          timestamp: new Date().toISOString(),
          message: JSON.stringify(messageObj),
          ipAddress: ip,
          currentUrl: url,
          sysInfo: JSON.stringify(sys),
          platform: 'harmonyos'
        };
        const httpRequest = http.createHttp();
        await httpRequest.request(
          `${cfg.dataChannelUrl}/device/heartbeat`,
          {
            method: http.RequestMethod.POST,
            header: { 'Content-Type': 'application/json' },
            extraData: JSON.stringify(payload),
            connectTimeout: HTTP_TIMEOUT
          }
        );
        httpRequest.destroy();
      } catch (e) {
        Logger.warn(TAG, 'page_loaded 上报失败', e);
      }
    }, 3000);
  }
}
