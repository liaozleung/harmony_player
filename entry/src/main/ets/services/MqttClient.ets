import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import {
  MqttAsync,
  MqttClient as OhMqttClient,
  MqttClientOptions,
  MqttConnectOptions,
  MqttResponse,
  MqttMessage,
  MqttSubscribeOptions
} from '@ohos/mqtt';
import { ConfigStore, ConfigChangePayload } from './ConfigStore';
import { HeartbeatService } from './HeartbeatService';
import { SystemControl } from './SystemControl';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';
import { MqttCommand, RegionChangePayload } from '../types/MqttCommand';

const TAG = 'MqttClient';

/**
 * MQTT 客户端 — 基于 @ohos/mqtt（OpenHarmony SIG 维护，paho.mqtt.c 包装）。
 *
 * 协议约定（与 fids_player_electron / client_player_electron 一致）：
 *   订阅 topic：
 *     device/{deviceId}                          ← 单设备命令
 *     device/{deviceId}/layout/#                 ← 布局相关（保留扩展位）
 *   payload 是 JSON 字符串，结构见 types/MqttCommand.ets
 *
 * 三种状态：
 *   - 未配置（deviceId 或 mqttBroker 为空）→ 跳过
 *   - 连接中 / 已连接 → connected=true
 *   - 已断开（connectLost 回调触发）→ 退避重连
 */
export class MqttClient {
  private static instance: MqttClient | null = null;
  private context: common.Context | null = null;
  private client: OhMqttClient | null = null;
  private connected = false;
  private retryDelay = 1000;
  private retryTimer: number | null = null;

  static getInstance(): MqttClient {
    if (!MqttClient.instance) MqttClient.instance = new MqttClient();
    return MqttClient.instance;
  }

  /** 必须在 EntryAbility.onCreate 内调一次，提供 context 用于 MQTT 文件持久化 */
  attachContext(context: common.Context): void {
    this.context = context;
  }

  start(): void {
    eventBus.on('configChanged', (payload?: Object | null): void => {
      if (payload === null || payload === undefined) {
        this.restart();
        return;
      }
      const change = payload as ConfigChangePayload;
      const key = change.key;
      if (key.startsWith('mqtt') || key === 'deviceId') this.restart();
    });
    this.restart();
  }

  async stop(): Promise<void> {
    if (this.retryTimer !== null) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    if (this.client) {
      try {
        if (this.connected) await this.client.disconnect();
      } catch (e) {
        Logger.warn(TAG, 'disconnect 异常', e);
      }
      try {
        await this.client.destroy();
      } catch (e) {
        Logger.warn(TAG, 'destroy 异常', e);
      }
      this.client = null;
    }
    this.connected = false;
  }

  private restart(): void {
    // restart 是同步触发，但 stop / connect 是 async，串起来
    this.stop().then(async (): Promise<void> => {
      await this.connect();
    }).catch((e: Object): void => {
      Logger.error(TAG, 'restart 异常', e);
    });
  }

  private async connect(): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.deviceId || !cfg.mqttBroker) {
      Logger.info(TAG, '设备未配置，暂不连接 MQTT');
      return;
    }
    const port = cfg.mqttPort || 1883;
    const url = `tcp://${cfg.mqttBroker}:${port}`;
    Logger.info(TAG, `连接 MQTT: ${url} clientId=${cfg.deviceId}`);

    try {
      const opts: MqttClientOptions = {
        url,
        clientId: cfg.deviceId,
        // persistenceType=1 即内存持久化；=0 需配 persistenceContext 文件路径
        persistenceType: 1
      };
      this.client = new OhMqttClient(opts);

      // ⚠️ messageArrived 必须在 subscribe 之前注册，否则消息会丢
      this.client.messageArrived((err: Error, msg: MqttMessage): void => {
        if (err) {
          Logger.warn(TAG, 'messageArrived err', err);
          return;
        }
        void this.onMessage(msg.topic, msg.payload);
      });

      // 断线回调（断网 / broker 关闭等被动断开）
      this.client.connectLost((err: Error, data: MqttResponse): void => {
        this.connected = false;
        eventBus.emit('mqttDisconnected');
        Logger.warn(TAG, '断线', err?.message ?? '', data?.message ?? '');
        this.scheduleReconnect();
      });

      const connectOpts: MqttConnectOptions = {
        userName: cfg.mqttUsername || '',
        password: cfg.mqttPassword || '',
        cleanSession: true,
        keepAliveInterval: 30,
        connectTimeout: 10,
        automaticReconnect: false   // 我们自己控制重连节奏
      };
      const ok = await this.client.connect(connectOpts);
      if (!ok) {
        throw new Error('connect 返回 false');
      }
      this.connected = true;
      this.retryDelay = 1000;
      Logger.info(TAG, 'MQTT 已连接');
      eventBus.emit('mqttConnected');

      // 订阅 device/{deviceId} + device/{deviceId}/layout/#
      const subs: MqttSubscribeOptions[] = [
        { topic: `device/${cfg.deviceId}`, qos: 1 },
        { topic: `device/${cfg.deviceId}/layout/#`, qos: 1 }
      ];
      await this.client.subscribeMany(subs);
      Logger.info(TAG, `已订阅: ${subs.map((s: MqttSubscribeOptions): string => s.topic).join(', ')}`);
    } catch (e) {
      Logger.error(TAG, 'MQTT 连接失败', e);
      this.connected = false;
      this.scheduleReconnect();
    }
  }

  /** 指数退避重连（1s → 2s → 4s → ... 最多 60s） */
  private scheduleReconnect(): void {
    if (this.retryTimer !== null) return;
    const delay = this.retryDelay;
    Logger.info(TAG, `${delay}ms 后重连`);
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = null;
      this.retryDelay = Math.min(this.retryDelay * 2, 60_000);
      this.restart();
    }, delay);
  }

  /** 收到 MQTT 消息后路由到具体处理 */
  private async onMessage(topic: string, payloadStr: string | ArrayBuffer): Promise<void> {
    try {
      let text: string;
      if (typeof payloadStr === 'string') {
        text = payloadStr;
      } else {
        const decoder = util.TextDecoder.create('utf-8');
        text = decoder.decodeToString(new Uint8Array(payloadStr));
      }
      Logger.info(TAG, `MQTT 收到 topic=${topic} payload=${text}`);
      const cmd = JSON.parse(text) as MqttCommand;
      await this.handleCommand(cmd);
    } catch (e) {
      Logger.error(TAG, '处理 MQTT 消息失败', e);
    }
  }

  /** 与 Electron 端 mqtt-client.ts handleCommand 对齐 */
  private async handleCommand(cmd: MqttCommand): Promise<void> {
    switch (cmd.action) {
      case 'displayPage': {
        // overlay 协议（来自多媒体发布 / 自由文本临时推送）：
        //   - overlay:true  + url 非空 → 临时覆盖展示，不写 ConfigStore
        //     （不持久化、不被心跳响应回带的 currentDisplayUrl 覆盖回去）
        //   - overlay:true  + url 空   → 撤回覆盖，恢复基础页面（用 cfg.displayUrl）
        //   - overlay:false（缺省）    → 永久切换基础页面，写 ConfigStore
        const overlay = cmd.overlay === true;
        if (overlay) {
          if (cmd.url && cmd.url.length > 0) {
            // 临时覆盖：直接 emit 切 Web，绕过 ConfigStore（避免被心跳同步逻辑覆盖）
            eventBus.emit('displayUrlChanged', cmd.url as Object);
            HeartbeatService.getInstance().reportPageLoaded(cmd.url);
          } else {
            // 撤回：切回 ConfigStore.cache 里的基础 displayUrl
            const cfg = ConfigStore.getInstance().getAll();
            const base = cfg.displayUrl ?? 'about:blank';
            Logger.info(TAG, `displayPage overlay 撤回 → 恢复基础页 ${base}`);
            eventBus.emit('displayUrlChanged', base as Object);
          }
        } else {
          // 永久切换：写 ConfigStore（持久化 + emit）
          if (cmd.url && cmd.url.length > 0) {
            await ConfigStore.getInstance().setDisplayUrl(cmd.url);
            HeartbeatService.getInstance().reportPageLoaded(cmd.url);
          }
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
      case 'displayRegion': {
        // 区域公告：url 非空 → 主 Web 缩到 1-fraction，右/下侧 fraction 显示公告；空 → 撤销
        const url = cmd.url ?? '';
        const position = (cmd.regionPosition === 'bottom') ? 'bottom' : 'right';
        let fraction = cmd.regionFraction ?? 0.3;
        if (fraction < 0.1) fraction = 0.3;   // url 为空时 fraction=0，撤销路径忽略
        if (fraction > 0.5) fraction = 0.5;
        const payload: RegionChangePayload = { url, position, fraction };
        eventBus.emit('regionChanged', payload as Object);
        break;
      }
      case 'displayMarquee':
        // V1 简化：仅 log；marquee 渲染未实装（Index 没专门的字幕条组件）
        Logger.info(TAG, `displayMarquee text=${cmd.text ?? ''} mode=${cmd.marqueeMode ?? '(default)'}`);
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
