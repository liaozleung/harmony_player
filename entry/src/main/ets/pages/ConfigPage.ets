import router from '@ohos.router';
import { KeyCode } from '@kit.InputKit';
import { ConfigStore } from '../services/ConfigStore';
import { DeviceConfig } from '../types/DeviceConfig';
import { Logger } from '../utils/logger';

const TAG = 'ConfigPage';

/**
 * 配置页。
 *
 * 注意 ArkTS 严格模式下 `@State cfg: DeviceConfig` 后再写 `this.cfg.deviceId = v`
 * 子字段赋值，往往不会被 ArkUI 状态机识别为变更（不持久化也不触发 build），
 * 导致 save 时拿到的是初始空值 → 跳回 Index 时还是 deviceId 为空 → 又跳回 ConfigPage
 * → 来回闪屏 / 看起来"保存按钮无反应"。
 *
 * 所以这里把每个字段拆成独立 @State 简单类型变量，TextInput 用 onChange 写回，
 * 简单可靠。
 */
@Entry
@Component
struct ConfigPage {
  @State deviceId: string = '';
  @State deviceName: string = '';
  @State serverUrl: string = '';
  @State dataChannelUrl: string = '';
  @State mqttBroker: string = '';
  @State mqttPort: string = '1883';
  @State mqttUsername: string = '';
  @State mqttPassword: string = '';
  @State heartbeatInterval: string = '15';
  @State displayUrl: string = '';

  @State saving: boolean = false;
  @State message: string = '';

  aboutToAppear(): void {
    const c = ConfigStore.getInstance().getAll();
    this.deviceId = c.deviceId;
    this.deviceName = c.deviceName;
    this.serverUrl = c.serverUrl;
    this.dataChannelUrl = c.dataChannelUrl;
    this.mqttBroker = c.mqttBroker;
    this.mqttPort = String(c.mqttPort);
    this.mqttUsername = c.mqttUsername;
    this.mqttPassword = c.mqttPassword;
    this.heartbeatInterval = String(c.heartbeatInterval);
    this.displayUrl = c.displayUrl ?? '';
    Logger.info(TAG, 'aboutToAppear loaded', JSON.stringify(c));
  }

  build() {
    Column() {
      Text('FIDS 播放器配置')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111')
        .margin({ bottom: 24 })

      Scroll() {
        Column({ space: 16 }) {
          this.field('deviceId （必填，与后台一致）', this.deviceId, (v: string): void => { this.deviceId = v; })
          this.field('设备名称', this.deviceName, (v: string): void => { this.deviceName = v; })
          this.field('Next.js 后台地址', this.serverUrl, (v: string): void => { this.serverUrl = v; })
          this.field('Spring Boot 数据通道', this.dataChannelUrl, (v: string): void => { this.dataChannelUrl = v; })
          this.field('MQTT broker', this.mqttBroker, (v: string): void => { this.mqttBroker = v; })
          this.field('MQTT 端口', this.mqttPort, (v: string): void => { this.mqttPort = v; })
          this.field('MQTT 用户名', this.mqttUsername, (v: string): void => { this.mqttUsername = v; })
          this.field('MQTT 密码', this.mqttPassword, (v: string): void => { this.mqttPassword = v; }, true)
          this.field('心跳间隔（秒，最小 5）', this.heartbeatInterval, (v: string): void => { this.heartbeatInterval = v; })
          this.field('显示页面 URL（手动指定时填，空则等待后台推送）', this.displayUrl, (v: string): void => { this.displayUrl = v; })
        }
        .padding({ left: 24, right: 24 })
      }
      .layoutWeight(1)
      .width('100%')

      if (this.message) {
        Text(this.message)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.message.startsWith('✓') ? '#15803d' : '#b91c1c')
          .backgroundColor(this.message.startsWith('✓') ? '#dcfce7' : '#fee2e2')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(6)
          .margin({ top: 12 })
      }

      Row({ space: 16 }) {
        Button('取消')
          .width(120)
          .onClick((): void => {
            Logger.info(TAG, '取消按钮被点击');
            router.back();
          })
        Button(this.saving ? '保存中...' : '保存并应用 (Enter)')
          .width(220)
          .enabled(!this.saving)
          .onClick((): void => {
            // 同步 lambda，内部不 await（避免 ArkTS 对 Promise<void> 返回类型的 onClick 静默丢弃）
            Logger.info(TAG, '保存按钮被点击, deviceId=', this.deviceId);
            this.save().catch((e: Object): void => Logger.error(TAG, 'save promise rejected', e));
          })
      }
      .margin({ top: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24 })
    .backgroundColor('#f5f5f5')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((e: KeyEvent): void => {
      // 键盘 Enter / NumPad Enter 触发保存（非触摸屏 + Button onClick 不稳的保险通道）
      if (e.type === KeyType.Down && (e.keyCode === KeyCode.KEYCODE_ENTER || e.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
        Logger.info(TAG, 'Enter 键触发保存');
        this.save().catch((err: Object): void => Logger.error(TAG, 'save promise rejected', err));
      } else if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
        Logger.info(TAG, 'Esc 取消');
        router.back();
      }
    })
  }

  @Builder
  field(label: string, value: string, onChange: (v: string) => void, isPassword: boolean = false) {
    Column() {
      Text(label).fontSize(14).fontColor('#666').alignSelf(ItemAlign.Start)
      TextInput({ text: value })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .onChange((v: string): void => { onChange(v); })
        .height(44)
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  async save(): Promise<void> {
    if (!this.deviceId || this.deviceId.trim().length === 0) {
      this.message = '✗ deviceId 必填';
      return;
    }
    this.saving = true;
    this.message = '';

    const port: number = Number(this.mqttPort) || 1883;
    const interval: number = Math.max(5, Number(this.heartbeatInterval) || 15);

    const displayUrlTrimmed = this.displayUrl.trim();
    const partial: Partial<DeviceConfig> = {
      deviceId: this.deviceId.trim(),
      deviceName: this.deviceName.trim(),
      serverUrl: this.serverUrl.trim(),
      dataChannelUrl: this.dataChannelUrl.trim(),
      mqttBroker: this.mqttBroker.trim(),
      mqttPort: port,
      mqttUsername: this.mqttUsername,
      mqttPassword: this.mqttPassword,
      heartbeatInterval: interval,
      displayUrl: displayUrlTrimmed.length > 0 ? displayUrlTrimmed : null
    };

    Logger.info(TAG, 'save start', JSON.stringify(partial));

    try {
      await ConfigStore.getInstance().update(partial);
      Logger.info(TAG, 'save done, replacing to Index');
      this.message = '✓ 已保存，正在跳转...';
      setTimeout((): void => {
        router.replaceUrl({ url: 'pages/Index' }).catch((e: Object): void => {
          Logger.warn(TAG, 'replaceUrl(Index) 失败', e);
          this.message = `✗ 跳转失败: ${e}`;
        });
      }, 600);
    } catch (e) {
      Logger.error(TAG, 'save failed', e);
      this.message = `✗ 保存失败：${e}`;
    } finally {
      this.saving = false;
    }
  }
}
