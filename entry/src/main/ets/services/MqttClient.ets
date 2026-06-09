import { util } from '@kit.ArkTS';
import { ConfigStore, ConfigChangePayload } from './ConfigStore';
import { HeartbeatService } from './HeartbeatService';
import { SystemControl } from './SystemControl';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';
import { MqttCommand } from '../types/MqttCommand';

const TAG = 'MqttClient';

/**
 * MQTT 客户端 — 占位实现
 *
 * ⚠️ 当前是占位骨架。真正的 MQTT 实现需要：
 *   1. 第一周技术验证：移植 mqtt.js 到 ArkTS（推荐），或选社区 oh-package
 *   2. 走 WebSocket 子协议（broker 一般同时开 1883 + 8083）
 *   3. 集成到这个文件，替换下方 connect() 内的 TODO 部分
 *
 * 协议约定（与 Electron 端一致，不可改）：
 *   订阅 topic：
 *     device/{deviceId}
 *     device/{deviceId}/layout/#
 *   payload 是 JSON 字符串，参考 types/MqttCommand.ets
 */
export class MqttClient {
  private static instance: MqttClient | null = null;
  private connected = false;
  private retryDelay = 1000;
  private retryTimer: number | null = null;

  static getInstance(): MqttClient {
    if (!MqttClient.instance) MqttClient.instance = new MqttClient();
    return MqttClient.instance;
  }

  start(): void {
    eventBus.on('configChanged', (payload?: Object | null): void => {
      // 批量更新时 payload 为 null，保守起见也重连
      if (payload === null || payload === undefined) {
        this.restart();
        return;
      }
      const change = payload as ConfigChangePayload;
      const key = change.key;
      // mqtt 配置项变化才重连
      if (key.startsWith('mqtt') || key === 'deviceId') this.restart();
    });
    this.restart();
  }

  stop(): void {
    if (this.retryTimer !== null) { clearTimeout(this.retryTimer); this.retryTimer = null; }
    if (this.connected) {
      // TODO: client.end()
      this.connected = false;
    }
  }

  private restart(): void {
    this.stop();
    this.connect();
  }

  private async connect(): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.deviceId || !cfg.mqttBroker) {
      Logger.info(TAG, '设备未配置，暂不连接 MQTT');
      return;
    }

    Logger.info(TAG, `连接 MQTT: ${cfg.mqttBroker}:${cfg.mqttPort} deviceId=${cfg.deviceId}`);

    // ╔══════════════════════════════════════════════════════════╗
    // ║  TODO: 替换为真实 MQTT 连接                                 ║
    // ║                                                            ║
    // ║  推荐方案：移植 mqtt.js（纯 JS，走 @ohos.net.webSocket）    ║
    // ║                                                            ║
    // ║  伪代码：                                                   ║
    // ║    const url = `ws://${cfg.mqttBroker}:8083/mqtt`;         ║
    // ║    this.client = mqtt.connect(url, {                       ║
    // ║      clientId: cfg.deviceId,                               ║
    // ║      username: cfg.mqttUsername,                           ║
    // ║      password: cfg.mqttPassword,                           ║
    // ║      reconnectPeriod: 5000,                                ║
    // ║      keepalive: 60                                         ║
    // ║    });                                                     ║
    // ║    this.client.on('connect', () => this.onConnect());      ║
    // ║    this.client.on('message', (t, p) => this.onMessage(t,p));║
    // ║    this.client.on('error', (e) => this.onError(e));        ║
    // ║    this.client.on('close', () => this.onClose());          ║
    // ╚══════════════════════════════════════════════════════════╝

    Logger.warn(TAG, 'MQTT 客户端未实现，请先完成 mqtt.js 移植');
  }

  private onConnect(deviceId: string): void {
    this.connected = true;
    this.retryDelay = 1000;
    Logger.info(TAG, '连接成功，订阅 topic');
    eventBus.emit('mqttConnected');

    // TODO: 真实订阅
    // this.client.subscribe([
    //   `device/${deviceId}`,
    //   `device/${deviceId}/layout/#`,
    // ], { qos: 1 });
  }

  /** 收到 MQTT 消息后路由到具体处理 */
  private async onMessage(topic: string, payloadBytes: Uint8Array): Promise<void> {
    try {
      // ArkTS 没有全局 TextDecoder，用 @kit.ArkTS util.TextDecoder
      const decoder = util.TextDecoder.create('utf-8');
      const payloadStr = decoder.decodeToString(payloadBytes);
      Logger.info(TAG, `MQTT 收到 topic=${topic} payload=${payloadStr}`);
      const cmd = JSON.parse(payloadStr) as MqttCommand;
      await this.handleCommand(cmd);
    } catch (e) {
      Logger.error(TAG, '处理 MQTT 消息失败', e);
    }
  }

  /** 与 Electron 端 mqtt-client.ts handleCommand 对齐 */
  private async handleCommand(cmd: MqttCommand): Promise<void> {
    switch (cmd.action) {
      case 'displayPage': {
        if (cmd.url) {
          await ConfigStore.getInstance().setDisplayUrl(cmd.url);
          // 延迟 3s 上报 page_loaded，与 Electron 端协议对齐
          HeartbeatService.getInstance().reportPageLoaded(cmd.url);
        }
        break;
      }
      case 'refreshPage':
        eventBus.emit('refreshPage');
        break;
      case 'restart':
        await SystemControl.reboot();
        break;
      case 'shutdown':
        await SystemControl.poweroff();
        break;
      case 'monitorOff':
        await SystemControl.screenOff();
        break;
      case 'monitorOn':
        await SystemControl.screenOn();
        break;
      case 'setBrightness':
        if (cmd.value !== undefined) await SystemControl.setBrightness(cmd.value);
        break;
      case 'screenshot':
        eventBus.emit('captureScreenshot');
        break;
      case 'startVnc':
      case 'stopVnc':
        Logger.info(TAG, `${cmd.action} — V1 不支持，忽略`);
        break;
      default:
        Logger.warn(TAG, '未知指令', cmd);
    }
  }
}
