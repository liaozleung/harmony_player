import { runningLock } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { eventBus } from '../utils/eventBus';
import { Logger } from '../utils/logger';

const TAG = 'SystemControl';

/** eventBus 'brightnessChanged' 事件 payload */
export interface BrightnessChangePayload {
  brightness: number;  // 0~1
}

/**
 * 系统控制。
 *
 * 设计：调用方代码（MqttClient）零感知签名等级。
 * 普通签名能做的功能直接实现；EDM 才能做的功能暂时只打日志。
 *
 * 状态对照：
 * | 方法            | 普通签名实现                                    | EDM 签名               |
 * |---------------- |-------------------------------------------------|------------------------|
 * | reboot          | stub（无替代 API）                              | enterpriseDeviceControl.rebootDevice |
 * | poweroff        | stub                                            | enterpriseDeviceControl.shutdownDevice |
 * | screenOff       | window.setWindowBrightness(0) + 覆盖黑屏        | lockScreen             |
 * | screenOn        | window.setWindowBrightness(lastBrightness)      | wakeUpDevice           |
 * | setBrightness   | window.setWindowBrightness(value)               | brightness.setValue    |
 *
 * 注：window.setWindowBrightness 只控制 app 窗口亮度，但全屏 KIOSK 模式下
 *     等同于系统屏幕背光（对数字标牌使用场景足够）。
 */
export class SystemControl {
  private static keepAwakeLock: runningLock.RunningLock | null = null;
  private static lastBrightness = 0.8;
  private static mainWindow: window.Window | null = null;

  /** EntryAbility.onWindowStageCreate 内调一次，注入 window 引用 */
  static attachWindow(win: window.Window): void {
    SystemControl.mainWindow = win;
  }

  /** EDM 才能做：整机重启 */
  static async reboot(): Promise<void> {
    Logger.info(TAG, 'reboot 调用');
    Logger.warn(TAG, 'reboot stub — 等待 EDM 证书');
  }

  /** EDM 才能做：整机关机 */
  static async poweroff(): Promise<void> {
    Logger.info(TAG, 'poweroff 调用');
    Logger.warn(TAG, 'poweroff stub — 等待 EDM 证书');
  }

  /**
   * 关屏：双管齐下
   *   1. window.setWindowBrightness(0) — 走系统 API（厂家屏蔽时无效）
   *   2. eventBus emit 'brightnessChanged' 0 → Index 叠一层全黑 overlay 视觉模拟
   * 第 2 步在 IDO-SBC7602 等屏蔽硬件背光的标牌主板上是唯一可见效果。
   */
  static async screenOff(): Promise<void> {
    Logger.info(TAG, 'screenOff 调用');
    await SystemControl.applyBrightness(0);
  }

  /** 开屏：恢复到关屏前的亮度 */
  static async screenOn(): Promise<void> {
    Logger.info(TAG, 'screenOn 调用');
    await SystemControl.applyBrightness(SystemControl.lastBrightness);
  }

  /**
   * 设置亮度。
   * 兼容两种值域：
   *   - 0~1（float，符合 setWindowBrightness 原生 API）
   *   - 0~100（int，fids admin UI slider 是百分比）→ 自动 / 100
   */
  static async setBrightness(value: number): Promise<void> {
    const normalized = value > 1 ? value / 100 : value;
    const v = Math.max(0, Math.min(1, normalized));
    SystemControl.lastBrightness = v;
    Logger.info(TAG, `setBrightness raw=${value} → normalized=${v}`);
    await SystemControl.applyBrightness(v);
  }

  /** 内部：把 [0,1] 亮度值同时下发给 setWindowBrightness 和 UI overlay */
  private static async applyBrightness(v: number): Promise<void> {
    if (SystemControl.mainWindow) {
      try {
        await SystemControl.mainWindow.setWindowBrightness(v);
        Logger.info(TAG, `setWindowBrightness(${v}) 返回成功`);
      } catch (e) {
        Logger.warn(TAG, 'setWindowBrightness 失败（继续走 UI overlay）', e);
      }
    }
    // 触发 Index 叠加黑色 overlay：opacity = 1 - v
    const payload: BrightnessChangePayload = { brightness: v };
    eventBus.emit('brightnessChanged', payload as Object);
  }

  /**
   * 后台运行锁（屏幕常亮由 window.setWindowKeepScreenOn 单独处理）。
   * RunningLockType.SCREEN 需要系统签名；BACKGROUND 普通签名可用（API 12 deprecated 但仍可用）。
   */
  static async acquireScreenAwake(): Promise<void> {
    if (SystemControl.keepAwakeLock) return;
    try {
      const lock = await runningLock.create('fids-bg-awake', runningLock.RunningLockType.BACKGROUND);
      lock.hold(0);
      SystemControl.keepAwakeLock = lock;
      Logger.info(TAG, '后台运行锁已开启');
    } catch (e) {
      Logger.warn(TAG, '获取后台运行锁失败', e);
    }
  }
}
