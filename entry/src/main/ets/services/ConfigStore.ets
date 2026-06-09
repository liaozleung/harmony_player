import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { DEFAULT_CONFIG, DeviceConfig } from '../types/DeviceConfig';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';

const TAG = 'ConfigStore';
const PREF_NAME = 'fids_player_config';

/**
 * configChanged 事件 payload
 */
export interface ConfigChangePayload {
  key: string;
  value: preferences.ValueType | null;
}

/**
 * 设备配置单例
 *
 * 用法：
 *   await ConfigStore.getInstance().init(this.context);
 *   const cfg = ConfigStore.getInstance().getAll();
 *   await ConfigStore.getInstance().setDisplayUrl(newUrl);
 *
 * 注：ArkTS 严格模式不允许 spread / 索引访问 / "in"，所以下面所有字段读写都用 switch 显式枚举。
 */
export class ConfigStore {
  private static instance: ConfigStore | null = null;
  private prefs: preferences.Preferences | null = null;
  private cache: DeviceConfig = ConfigStore.cloneConfig(DEFAULT_CONFIG);
  private initialized = false;

  static getInstance(): ConfigStore {
    if (!ConfigStore.instance) ConfigStore.instance = new ConfigStore();
    return ConfigStore.instance;
  }

  /** 浅拷贝 DEFAULT_CONFIG（ArkTS 严格模式不支持对象 spread） */
  private static cloneConfig(src: DeviceConfig): DeviceConfig {
    return {
      deviceId: src.deviceId,
      deviceName: src.deviceName,
      macAddress: src.macAddress,
      serverUrl: src.serverUrl,
      dataChannelUrl: src.dataChannelUrl,
      mqttBroker: src.mqttBroker,
      mqttPort: src.mqttPort,
      mqttUsername: src.mqttUsername,
      mqttPassword: src.mqttPassword,
      heartbeatInterval: src.heartbeatInterval,
      displayUrl: src.displayUrl,
      autoStart: src.autoStart,
      fullscreen: src.fullscreen
    };
  }

  /** 必须在 EntryAbility.onCreate 中调用一次 */
  async init(context: common.Context): Promise<void> {
    if (this.initialized) return;
    this.prefs = await preferences.getPreferences(context, PREF_NAME);

    // 显式逐字段读取（避免 keyof 索引访问被 ArkTS 限制）
    this.cache.deviceId = await this.readString('deviceId', DEFAULT_CONFIG.deviceId);
    this.cache.deviceName = await this.readString('deviceName', DEFAULT_CONFIG.deviceName);
    this.cache.macAddress = await this.readString('macAddress', DEFAULT_CONFIG.macAddress);
    this.cache.serverUrl = await this.readString('serverUrl', DEFAULT_CONFIG.serverUrl);
    this.cache.dataChannelUrl = await this.readString('dataChannelUrl', DEFAULT_CONFIG.dataChannelUrl);
    this.cache.mqttBroker = await this.readString('mqttBroker', DEFAULT_CONFIG.mqttBroker);
    this.cache.mqttPort = await this.readNumber('mqttPort', DEFAULT_CONFIG.mqttPort);
    this.cache.mqttUsername = await this.readString('mqttUsername', DEFAULT_CONFIG.mqttUsername);
    this.cache.mqttPassword = await this.readString('mqttPassword', DEFAULT_CONFIG.mqttPassword);
    this.cache.heartbeatInterval = await this.readNumber('heartbeatInterval', DEFAULT_CONFIG.heartbeatInterval);
    this.cache.displayUrl = await this.readNullableString('displayUrl', DEFAULT_CONFIG.displayUrl);
    this.cache.autoStart = await this.readBoolean('autoStart', DEFAULT_CONFIG.autoStart);
    this.cache.fullscreen = await this.readBoolean('fullscreen', DEFAULT_CONFIG.fullscreen);

    this.initialized = true;
    Logger.info(TAG, 'init done', JSON.stringify(this.cache));
  }

  private async readString(key: string, dflt: string): Promise<string> {
    const v = await this.prefs!.get(key, dflt);
    // 历史空串也按"未设置"处理，回落到默认值（让默认 mqtt 账号等更新对老设备生效）
    if (typeof v === 'string' && v.length > 0) return v;
    return dflt;
  }
  private async readNullableString(key: string, dflt: string | null): Promise<string | null> {
    const v = await this.prefs!.get(key, dflt === null ? '' : dflt);
    if (typeof v === 'string' && v.length > 0) return v;
    return null;
  }
  private async readNumber(key: string, dflt: number): Promise<number> {
    const v = await this.prefs!.get(key, dflt);
    return typeof v === 'number' ? v : dflt;
  }
  private async readBoolean(key: string, dflt: boolean): Promise<boolean> {
    const v = await this.prefs!.get(key, dflt);
    return typeof v === 'boolean' ? v : dflt;
  }

  getAll(): DeviceConfig {
    return ConfigStore.cloneConfig(this.cache);
  }

  /**
   * 单独写入 displayUrl（MQTT displayPage + HTTP bootstrap 用）
   * 不做成泛型 set<K>(key, value) 是因为 ArkTS 严格模式禁止 keyof + 索引访问。
   * 其他字段如果以后需要单写，再追加同名 setter。
   */
  async setDisplayUrl(url: string | null): Promise<void> {
    if (!this.prefs) {
      Logger.warn(TAG, 'setDisplayUrl before init');
      return;
    }
    this.cache.displayUrl = url;
    await this.prefs.put('displayUrl', url === null ? '' : url);
    await this.prefs.flush();
    const payload: ConfigChangePayload = { key: 'displayUrl', value: url === null ? '' : url };
    eventBus.emit('configChanged', payload);
    eventBus.emit('displayUrlChanged', url === null ? null : (url as Object));
  }

  /** 批量更新（配置页保存时使用） */
  async update(partial: Partial<DeviceConfig>): Promise<void> {
    if (!this.prefs) return;
    let displayUrlChanged = false;
    let newDisplayUrl: string | null = null;

    if (partial.deviceId !== undefined) { this.cache.deviceId = partial.deviceId; await this.prefs.put('deviceId', partial.deviceId); }
    if (partial.deviceName !== undefined) { this.cache.deviceName = partial.deviceName; await this.prefs.put('deviceName', partial.deviceName); }
    if (partial.macAddress !== undefined) { this.cache.macAddress = partial.macAddress; await this.prefs.put('macAddress', partial.macAddress); }
    if (partial.serverUrl !== undefined) { this.cache.serverUrl = partial.serverUrl; await this.prefs.put('serverUrl', partial.serverUrl); }
    if (partial.dataChannelUrl !== undefined) { this.cache.dataChannelUrl = partial.dataChannelUrl; await this.prefs.put('dataChannelUrl', partial.dataChannelUrl); }
    if (partial.mqttBroker !== undefined) { this.cache.mqttBroker = partial.mqttBroker; await this.prefs.put('mqttBroker', partial.mqttBroker); }
    if (partial.mqttPort !== undefined) { this.cache.mqttPort = partial.mqttPort; await this.prefs.put('mqttPort', partial.mqttPort); }
    if (partial.mqttUsername !== undefined) { this.cache.mqttUsername = partial.mqttUsername; await this.prefs.put('mqttUsername', partial.mqttUsername); }
    if (partial.mqttPassword !== undefined) { this.cache.mqttPassword = partial.mqttPassword; await this.prefs.put('mqttPassword', partial.mqttPassword); }
    if (partial.heartbeatInterval !== undefined) { this.cache.heartbeatInterval = partial.heartbeatInterval; await this.prefs.put('heartbeatInterval', partial.heartbeatInterval); }
    if (partial.displayUrl !== undefined) {
      this.cache.displayUrl = partial.displayUrl;
      await this.prefs.put('displayUrl', partial.displayUrl === null ? '' : partial.displayUrl);
      displayUrlChanged = true;
      newDisplayUrl = partial.displayUrl;
    }
    if (partial.autoStart !== undefined) { this.cache.autoStart = partial.autoStart; await this.prefs.put('autoStart', partial.autoStart); }
    if (partial.fullscreen !== undefined) { this.cache.fullscreen = partial.fullscreen; await this.prefs.put('fullscreen', partial.fullscreen); }

    await this.prefs.flush();
    eventBus.emit('configChanged', null);  // 批量更新事件 payload 为 null（订阅者自行重读）
    if (displayUrlChanged) eventBus.emit('displayUrlChanged', newDisplayUrl === null ? null : (newDisplayUrl as Object));
  }
}
