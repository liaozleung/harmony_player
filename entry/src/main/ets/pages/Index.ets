import { webview } from '@kit.ArkWeb';
import router from '@ohos.router';
import { KeyCode } from '@kit.InputKit';
import { ConfigStore } from '../services/ConfigStore';
import { Watchdog } from '../services/Watchdog';
import { ScreenshotService } from '../services/ScreenshotService';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';

const TAG = 'IndexPage';

@Entry
@Component
struct Index {
  @State currentUrl: string = '';
  @State isConfigMissing: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();

  // 解绑句柄
  private offDisplayUrl: (() => void) | null = null;
  private offRefresh: (() => void) | null = null;
  private offCapture: (() => void) | null = null;

  aboutToAppear(): void {
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
  }

  aboutToDisappear(): void {
    this.offDisplayUrl?.();
    this.offRefresh?.();
    this.offCapture?.();
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
          .width('100%')
          .height('100%')

        // displayUrl 为空时显示"等待显示页面"提示层（防止用户面对一片白屏不知所措）
        if (!this.currentUrl || this.currentUrl === 'about:blank') {
          Column() {
            Text('等待显示页面')
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#fff')
            Text('心跳成功后会自动从后台拉取，或等待 MQTT displayPage 推送')
              .fontSize(16).fontColor('#aaa').margin({ top: 16 })
            Text('点击右上角"⚙ 配置"可重新进入配置页')
              .fontSize(14).fontColor('#666').margin({ top: 8 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#000')
        }
      }

      // 右上角永远显示的"⚙ 配置"悬浮按钮（鼠标可点；按 Z 排序在 Web 上方）
      Button('⚙ 配置')
        .fontSize(14)
        .fontColor('#fff')
        .backgroundColor('rgba(0,0,0,0.55)')
        .height(36)
        .padding({ left: 12, right: 12 })
        .position({ x: '100%', y: 0 })
        .markAnchor({ x: '100%', y: 0 })
        .margin({ right: 16, top: 16 })
        .onClick((): void => {
          Logger.info(TAG, '点击⚙ 配置按钮');
          router.pushUrl({ url: 'pages/ConfigPage' }).catch((e: Object): void => Logger.warn(TAG, 'router error', e));
        })
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
