import { webview } from '@kit.ArkWeb';
import router from '@ohos.router';
import { KeyCode, pointer } from '@kit.InputKit';
import { ConfigStore } from '../services/ConfigStore';
import { Watchdog } from '../services/Watchdog';
import { ScreenshotService } from '../services/ScreenshotService';
import { BrightnessChangePayload } from '../services/SystemControl';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';

const TAG = 'IndexPage';

@Entry
@Component
struct Index {
  @State currentUrl: string = '';
  @State isConfigMissing: boolean = false;
  /**
   * 亮度叠加层不透明度。SystemControl.setBrightness/screenOff 通过 eventBus 改这个值。
   * brightnessChanged 事件来时：overlay opacity = 1 - brightness
   * IDO-SBC7602 等屏蔽硬件背光的标牌主板上，这是唯一可见的亮度效果。
   */
  @State brightnessOverlayOpacity: number = 0;
  controller: webview.WebviewController = new webview.WebviewController();

  // 解绑句柄
  private offDisplayUrl: (() => void) | null = null;
  private offRefresh: (() => void) | null = null;
  private offCapture: (() => void) | null = null;
  private offBrightness: (() => void) | null = null;

  aboutToAppear(): void {
    // 进入显示页面 → 隐藏鼠标（数字标牌纯展示，不需要鼠标）
    // ConfigPage 会在 aboutToAppear 重新显示，方便操作配置表单
    pointer.setPointerVisible(false).catch((e: Object): void => {
      Logger.warn(TAG, 'setPointerVisible(false) 失败', e);
    });

    const cfg = ConfigStore.getInstance().getAll();
    Logger.info(TAG, 'aboutToAppear cfg=', JSON.stringify(cfg));
    if (!cfg.deviceId) {
      // 未配置 → 显示静态提示页，让用户按 F2 手动进配置页（避免 ConfigPage 保存失败时反复闪屏）
      Logger.warn(TAG, 'deviceId 未配置 → 显示静态提示');
      this.isConfigMissing = true;
      return;
    }
    this.currentUrl = cfg.displayUrl ?? 'about:blank';

    // 订阅 displayUrl 变化（来自 ConfigStore.set 或 MQTT displayPage / 心跳响应）
    // ArkUI Web 的 src 属性只在 mount 时使用一次，运行时变更不会触发 reload；
    // 必须通过 controller.loadUrl 显式加载新 URL。
    this.offDisplayUrl = eventBus.on('displayUrlChanged', (url?: Object | null): void => {
      const newUrl: string = (typeof url === 'string') ? url : 'about:blank';
      if (newUrl !== this.currentUrl) {
        Logger.info(TAG, `displayUrl 切换 ${this.currentUrl} → ${newUrl}`);
        this.currentUrl = newUrl;
        Watchdog.getInstance().reset();
        try {
          this.controller.loadUrl(newUrl);
        } catch (e) {
          Logger.warn(TAG, 'controller.loadUrl 失败', e);
        }
      }
    });

    // MQTT refreshPage 指令
    this.offRefresh = eventBus.on('refreshPage', () => {
      try { this.controller.refresh(); } catch (e) { Logger.warn(TAG, 'refresh 失败', e); }
    });

    // MQTT screenshot 指令
    this.offCapture = eventBus.on('captureScreenshot', () => {
      ScreenshotService.captureAndUpload(this.controller);
    });

    // 亮度变化 → 调整黑色覆盖层不透明度
    this.offBrightness = eventBus.on('brightnessChanged', (payload?: Object | null): void => {
      if (!payload) return;
      const p = payload as BrightnessChangePayload;
      const v = Math.max(0, Math.min(1, p.brightness));
      this.brightnessOverlayOpacity = 1 - v;
      Logger.info(TAG, `亮度 overlay opacity → ${this.brightnessOverlayOpacity}`);
    });
  }

  aboutToDisappear(): void {
    this.offDisplayUrl?.();
    this.offRefresh?.();
    this.offCapture?.();
    this.offBrightness?.();
    Watchdog.getInstance().stop();
  }

  build() {
    Stack() {
      if (this.isConfigMissing) {
        Column() {
          Text('设备未配置')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#fff')
          Text('按 F2 进入配置页（或长按屏幕 5 秒）')
            .fontSize(20)
            .fontColor('#aaa')
            .margin({ top: 24 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#000')
      } else {
        Web({ src: this.currentUrl, controller: this.controller })
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .fileAccess(true)
          .imageAccess(true)
          // 注：userAgent() 在 API 12 deprecated，但替代 API customizeSchemes 不通用，先保留
          .userAgent('FidsHarmonyPlayer/1.0 (OpenHarmony)')
          .onPageEnd((): void => {
            Watchdog.getInstance().attach(this.controller);
          })
          .onErrorReceive((event): void => {
            Logger.warn(TAG, 'Web 加载错误', event?.error?.getErrorInfo?.());
          })
          // Web 抢键盘焦点，外层 Stack onKeyEvent 收不到 F2，
          // 必须在 Web 组件上 onInterceptKeyEvent 提前拦截
          .onInterceptKeyEvent((e: KeyEvent): boolean => {
            if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_F2) {
              Logger.info(TAG, 'Web onInterceptKeyEvent F2 → 进入配置页');
              router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: Object): void =>
                Logger.warn(TAG, 'router error', err)
              );
              return true; // 拦截，不让 Web 处理
            }
            return false;
          })
          .width('100%')
          .height('100%')

        // displayUrl 为空时显示"等待显示页面"提示层（防止用户面对一片白屏不知所措）
        if (!this.currentUrl || this.currentUrl === 'about:blank') {
          Column() {
            Text('等待显示页面')
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#fff')
            Text('心跳成功后会自动从后台拉取，或等待 MQTT displayPage 推送')
              .fontSize(16).fontColor('#aaa').margin({ top: 16 })
            Text('按 F2 进入配置页')
              .fontSize(14).fontColor('#666').margin({ top: 8 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#000')
        }
      }

      // 亮度黑色覆盖层（hitTestBehavior=None 让点击穿透到 Web）
      if (this.brightnessOverlayOpacity > 0) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#000')
          .opacity(this.brightnessOverlayOpacity)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((e: KeyEvent): void => {
      // 按键 F2 进入配置页（非触摸屏设备的逃生通道）
      // 同时保留长按 5 秒触摸手势
      if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_F2) {
        router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: Object): void => Logger.warn(TAG, 'router error', err));
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 5000 })
        .onAction((): void => {
          router.pushUrl({ url: 'pages/ConfigPage' }).catch((e: Object): void => Logger.warn(TAG, 'router error', e));
        })
    )
  }
}
