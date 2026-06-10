import { webview } from '@kit.ArkWeb';
import router from '@ohos.router';
import { KeyCode, pointer } from '@kit.InputKit';
import { ConfigStore } from '../services/ConfigStore';
import { Watchdog } from '../services/Watchdog';
import { ScreenshotService } from '../services/ScreenshotService';
import { BrightnessChangePayload } from '../services/SystemControl';
import { RegionChangePayload, MarqueeChangePayload } from '../types/MqttCommand';
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
  /**
   * 区域公告（displayRegion）。url 非空时主 Web 缩到 1-fraction，position 侧显示公告 iframe。
   * 收到 displayRegion url='' 时清空 url 恢复主区全屏。
   */
  @State regionUrl: string = '';
  @State regionPosition: 'right' | 'bottom' = 'right';
  @State regionFraction: number = 0.3;
  /**
   * 底部滚动字幕 overlay 模式文本（embedded 模式不存这里，直接 postMessage 给 Web）。
   * 空字符串=隐藏底部 bar。
   */
  @State marqueeOverlayText: string = '';
  controller: webview.WebviewController = new webview.WebviewController();
  regionController: webview.WebviewController = new webview.WebviewController();

  // 解绑句柄
  private offDisplayUrl: (() => void) | null = null;
  private offRefresh: (() => void) | null = null;
  private offCapture: (() => void) | null = null;
  private offBrightness: (() => void) | null = null;
  private offRegion: (() => void) | null = null;
  private offMarquee: (() => void) | null = null;

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

    // 底部滚动字幕 displayMarquee — 分 embedded/overlay 两种模式
    this.offMarquee = eventBus.on('marqueeChanged', (payload?: Object | null): void => {
      if (!payload) { this.marqueeOverlayText = ''; this.postMarqueeToWeb(''); return; }
      const p = payload as MarqueeChangePayload;
      Logger.info(TAG, `字幕变更 mode=${p.mode} text="${p.text}"`);
      if (p.mode === 'embedded') {
        // 字幕由 fids_webpage 自己显示在页脚 → player 原生底部 bar 不显示
        this.marqueeOverlayText = '';
        this.postMarqueeToWeb(p.text);
      } else {
        // overlay 模式 → 显示底部 bar；同时清空 webview 内部 marquee（防双重显示）
        this.marqueeOverlayText = p.text;
        this.postMarqueeToWeb('');
      }
    });

    // 区域公告 displayRegion
    this.offRegion = eventBus.on('regionChanged', (payload?: Object | null): void => {
      if (!payload) return;
      const p = payload as RegionChangePayload;
      if (!p.url || p.url.length === 0) {
        // 撤销区域公告
        Logger.info(TAG, '区域公告撤销 → 主 Web 全屏');
        this.regionUrl = '';
        return;
      }
      Logger.info(TAG, `区域公告启用 position=${p.position} fraction=${p.fraction} url=${p.url}`);
      this.regionPosition = p.position;
      this.regionFraction = p.fraction;
      this.regionUrl = p.url;
      // 用 controller.loadUrl 确保 region Web reload 到新 url
      try { this.regionController.loadUrl(p.url); } catch (_) { /* 第一次 mount 时 controller 还没初始化，直接靠 src 加载 */ }
    });
  }

  aboutToDisappear(): void {
    this.offDisplayUrl?.();
    this.offRefresh?.();
    this.offCapture?.();
    this.offBrightness?.();
    this.offRegion?.();
    this.offMarquee?.();
    Watchdog.getInstance().stop();
  }

  /**
   * embedded 模式注入：通过 runJavaScript 给 fids_webpage 发 `marqueeOverride` 消息，
   * 让 universal 等模板的页脚 marquee 区自己渲染。
   *
   * fids_webpage 的语义（FidsPageTemplate.jsx）：
   *   - text 是字符串（含空字符串）→ override 该值（空字符串=显式清空 marquee）
   *   - text 是 null 或非字符串    → 撤销 override，恢复 fids_page_config.marqueeTextZh
   *
   * 所以：text 非空 → 注入字符串；text 空 → 注入 null（让原本字幕恢复）。
   */
  private postMarqueeToWeb(text: string): void {
    try {
      // 空字符串当撤回处理：postMessage 的 text 传 null，触发 fids_webpage 恢复原 marquee
      const safe = text && text.length > 0 ? JSON.stringify(text) : 'null';
      const js = `(function(){try{window.postMessage({type:'marqueeOverride',text:${safe}},'*');}catch(e){}})();`;
      this.controller.runJavaScript(js).catch((e: Object): void => {
        Logger.warn(TAG, 'postMarqueeToWeb runJavaScript 失败', e);
      });
    } catch (e) {
      Logger.warn(TAG, 'postMarqueeToWeb 失败', e);
    }
  }

  @Builder
  MainWeb() {
    Web({ src: this.currentUrl, controller: this.controller })
      .domStorageAccess(true)
      .javaScriptAccess(true)
      .fileAccess(true)
      .imageAccess(true)
      .userAgent('FidsHarmonyPlayer/1.0 (OpenHarmony)')
      .onPageEnd((): void => {
        Watchdog.getInstance().attach(this.controller);
      })
      .onErrorReceive((event): void => {
        Logger.warn(TAG, 'Web 加载错误', event?.error?.getErrorInfo?.());
      })
      // Web 抢键盘焦点 → 必须在 Web 组件上 onInterceptKeyEvent 提前拦截
      .onInterceptKeyEvent((e: KeyEvent): boolean => {
        if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_F2) {
          Logger.info(TAG, 'Web onInterceptKeyEvent F2 → 进入配置页');
          router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: Object): void =>
            Logger.warn(TAG, 'router error', err)
          );
          return true;
        }
        return false;
      })
      .width('100%')
      .height('100%')
  }

  @Builder
  RegionWeb() {
    Web({ src: this.regionUrl, controller: this.regionController })
      .domStorageAccess(true)
      .javaScriptAccess(true)
      .fileAccess(true)
      .imageAccess(true)
      .onErrorReceive((event): void => {
        Logger.warn(TAG, 'Region Web 加载错误', event?.error?.getErrorInfo?.());
      })
      .width('100%')
      .height('100%')
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
      } else if (this.regionUrl && this.regionUrl.length > 0) {
        // displayRegion 区域公告分屏模式：主区缩 + position 侧显示公告 iframe
        if (this.regionPosition === 'right') {
          Row() {
            Column() { this.MainWeb() }.layoutWeight(1 - this.regionFraction).height('100%')
            Column() { this.RegionWeb() }.layoutWeight(this.regionFraction).height('100%')
          }.width('100%').height('100%')
        } else {
          Column() {
            Column() { this.MainWeb() }.layoutWeight(1 - this.regionFraction).width('100%')
            Column() { this.RegionWeb() }.layoutWeight(this.regionFraction).width('100%')
          }.width('100%').height('100%')
        }
      } else {
        this.MainWeb()

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

      // 底部滚动字幕 overlay 模式（embedded 模式由 fids_webpage 自己渲染，这里不显示）
      // 在亮度 overlay 之下，会被亮度遮挡
      if (this.marqueeOverlayText && this.marqueeOverlayText.length > 0) {
        Row() {
          Marquee({
            start: true,
            step: 8,           // 滚动速度 px/帧
            loop: -1,          // 无限循环
            fromStart: true,
            src: this.marqueeOverlayText
          })
            .fontSize(28)
            .fontColor('#ffeb3b')
            .fontWeight(FontWeight.Bold)
            .width('100%')
        }
        .width('100%')
        .height(56)
        .backgroundColor('rgba(0,0,0,0.7)')
        .padding({ left: 16, right: 16 })
        .position({ x: 0, y: '100%' })
        .markAnchor({ x: 0, y: '100%' })
        .hitTestBehavior(HitTestMode.None)
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
