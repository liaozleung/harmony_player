import { runningLock } from '@kit.BasicServicesKit';
import { Logger } from '../utils/logger';

const TAG = 'SystemControl';

/**
 * 系统控制 — Stub 模式
 *
 * 设计目的：调用方代码（MqttClient）零感知签名等级。
 * 普通签名能做的功能直接实现；EDM 才能做的功能暂时只打日志。
 * 等 EDM 证书就绪，把对应方法的 stub 部分替换为真实 API 调用即可。
 *
 * 状态对照表：
 * | 方法            | 普通签名         | EDM 签名               |
 * |---------------- |------------------|------------------------|
 * | reboot          | stub             | enterpriseDeviceControl.rebootDevice |
 * | poweroff        | stub             | enterpriseDeviceControl.shutdownDevice |
 * | screenOff       | stub             | lockScreen             |
 * | screenOn        | stub             | wakeUpDevice           |
 * | setBrightness   | stub（待选 API） | display 系列 API       |
 *
 * 注：@ohos.brightness 模块在 OpenHarmony 5.0 API 12 普通签名下不可用，
 *     全部亮度/锁屏接口改 stub；下个迭代选用 @kit.ArkUI / display 替代方案。
 */
export class SystemControl {
  private static keepAwakeLock: runningLock.RunningLock | null = null;
  private static lastBrightness = 0.5; // 关屏前缓存的亮度值

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

  /** 关屏 stub（普通签名暂无可用 API；EDM 用 lockScreen） */
  static async screenOff(): Promise<void> {
    Logger.info(TAG, 'screenOff 调用');
    Logger.warn(TAG, 'screenOff stub — 等待 @kit.ArkUI display API 评估 / EDM');
  }

  /** 开屏 stub */
  static async screenOn(): Promise<void> {
    Logger.info(TAG, 'screenOn 调用');
    Logger.warn(TAG, 'screenOn stub — 等待 @kit.ArkUI display API 评估 / EDM');
  }

  /** 设置亮度，0..1（stub，只更新缓存值） */
  static async setBrightness(value: number): Promise<void> {
    const v = Math.max(0, Math.min(1, value));
    SystemControl.lastBrightness = v;
    Logger.info(TAG, `setBrightness ${v} (stub)`);
  }

  /**
   * 屏幕常亮（数字标牌一般需要）
   * OpenHarmony 5.0 API 12 RunningLockType 在普通签名仅 BACKGROUND 可用，
   * 用 PROXIMITY_SCREEN_CONTROL / SCREEN 都需要系统签名。
   * 这里用 BACKGROUND 让进程不被冻结；KEEP_SCREEN_ON 改由 window.setKeepScreenOn 在 Index 页面控制。
   */
  static async acquireScreenAwake(): Promise<void> {
    if (SystemControl.keepAwakeLock) return;
    try {
      const lock = await runningLock.create('fids-bg-awake', runningLock.RunningLockType.BACKGROUND);
      lock.hold(0); // 0 = 一直持有
      SystemControl.keepAwakeLock = lock;
      Logger.info(TAG, '后台运行锁已开启（屏幕常亮由 window.setKeepScreenOn 单独处理）');
    } catch (e) {
      Logger.warn(TAG, '获取后台运行锁失败', e);
    }
  }
}
