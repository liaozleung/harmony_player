import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ConfigStore } from '../services/ConfigStore';
import { HeartbeatService } from '../services/HeartbeatService';
import { MqttClient } from '../services/MqttClient';
import { SystemControl } from '../services/SystemControl';
import { Logger } from '../utils/logger';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    Logger.info(TAG, 'onCreate');
    // 初始化配置（必须最先完成，后续 service 都依赖 ConfigStore）
    await ConfigStore.getInstance().init(this.context);
    // 屏幕常亮
    await SystemControl.acquireScreenAwake();
    // 启动后台 service
    HeartbeatService.getInstance().start();
    MqttClient.getInstance().attachContext(this.context);
    MqttClient.getInstance().start();
  }

  onDestroy(): void {
    Logger.info(TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.info(TAG, 'onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error(TAG, 'loadContent 失败', JSON.stringify(err));
        return;
      }
      // 全屏 + 隐藏状态栏 + 隐藏导航栏 + 屏幕常亮（数字标牌专用）
      windowStage.getMainWindow().then((win: window.Window): void => {
        // 把 mainWindow 注入 SystemControl，供 setBrightness / screenOff 等使用
        SystemControl.attachWindow(win);
        win.setWindowLayoutFullScreen(true).catch((e: Object): void => Logger.warn(TAG, 'setWindowLayoutFullScreen', e));
        try { win.setWindowKeepScreenOn(true); } catch (e) { Logger.warn(TAG, 'setWindowKeepScreenOn', e); }
        try {
          win.setSpecificSystemBarEnabled('status', false);
          win.setSpecificSystemBarEnabled('navigation', false);
        } catch (e) {
          Logger.warn(TAG, 'setSpecificSystemBarEnabled', e);
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    Logger.info(TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.info(TAG, 'onForeground');
  }

  onBackground(): void {
    Logger.info(TAG, 'onBackground');
  }
}
