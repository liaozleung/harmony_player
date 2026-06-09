import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { ConfigStore } from './ConfigStore';
import { Logger } from '../utils/logger';

const TAG = 'ScreenshotService';

/**
 * 截图上传 — 实装。
 *
 * 截图源：webview.WebviewController.getWebSnapshot()（ArkWeb API 11+，无需系统权限）
 * 编码：JPEG quality 65（压缩到 ~100KB 量级）
 * 上传：multipart/form-data POST 到 {serverUrl}/api/fids-devices/screenshot
 *       fids 后端 endpoint 期望 file + deviceId 两个字段
 *
 * 已知限制：
 * - takeWebSnapshot 只截 Web 内容，不含原生 UI（如悬浮 ⚙ 按钮）
 *   — 对数字标牌这种 Web 全屏的场景刚好够
 * - 系统签名应用可改用 @ohos.screenshot 截整屏
 */
export class ScreenshotService {
  /** MQTT screenshot 命令触发；controller 由 Index 页面通过 eventBus 时附带 */
  static async captureAndUpload(controller: webview.WebviewController): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.serverUrl || !cfg.deviceId) {
      Logger.warn(TAG, '设备未配置，跳过截图');
      return;
    }

    try {
      // 1. 截 Web 内容为 PixelMap（API 12 是 callback 风格，包装成 Promise）
      Logger.info(TAG, 'webPageSnapshot 开始');
      const snapResult: webview.SnapshotResult = await new Promise<webview.SnapshotResult>((resolve, reject): void => {
        controller.webPageSnapshot(
          { id: 'fids-screenshot-' + Date.now().toString(36) },
          (err: Error, result: webview.SnapshotResult): void => {
            if (err) reject(err);
            else resolve(result);
          }
        );
      });
      const pixelMap = snapResult.imagePixelMap;
      if (!pixelMap) {
        Logger.warn(TAG, 'snapResult.imagePixelMap 为空，status=' + snapResult.status);
        return;
      }

      // 2. 编码 JPEG
      const packer = image.createImagePacker();
      const jpegBuf = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 65 });
      await packer.release();
      await pixelMap.release();
      Logger.info(TAG, `截图编码完成 ${jpegBuf.byteLength} bytes`);

      // 3. multipart/form-data 上传
      await ScreenshotService.uploadMultipart(cfg.serverUrl, cfg.deviceId, jpegBuf);
      Logger.info(TAG, '截图上传成功');
    } catch (e) {
      Logger.error(TAG, '截图上传失败', e);
    }
  }

  /**
   * 手工构造 multipart/form-data 上传（@ohos.net.http 不直接支持 FormData，
   * 必须自己拼 boundary + 头 + 字节流）。
   * 字段约定：deviceId（text）+ file（filename={deviceId}.jpg, image/jpeg）
   */
  private static async uploadMultipart(serverUrl: string, deviceId: string, jpegBuf: ArrayBuffer): Promise<void> {
    const boundary = '----fidsHarmonyBoundary' + Date.now().toString(36);
    const encoder = util.TextEncoder.create('utf-8');

    // Part 1: deviceId 字段（text）
    const part1Header = `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="deviceId"\r\n\r\n` +
      `${deviceId}\r\n`;

    // Part 2: file 字段（binary）
    const part2Header = `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${deviceId}.jpg"\r\n` +
      `Content-Type: image/jpeg\r\n\r\n`;

    // Trailer
    const trailer = `\r\n--${boundary}--\r\n`;

    const part1Bytes = encoder.encodeInto(part1Header);
    const part2HeaderBytes = encoder.encodeInto(part2Header);
    const trailerBytes = encoder.encodeInto(trailer);
    const fileBytes = new Uint8Array(jpegBuf);

    const totalLen = part1Bytes.byteLength + part2HeaderBytes.byteLength + fileBytes.byteLength + trailerBytes.byteLength;
    const body = new Uint8Array(totalLen);
    let offset = 0;
    body.set(part1Bytes, offset); offset += part1Bytes.byteLength;
    body.set(part2HeaderBytes, offset); offset += part2HeaderBytes.byteLength;
    body.set(fileBytes, offset); offset += fileBytes.byteLength;
    body.set(trailerBytes, offset);

    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(
        `${serverUrl}/api/fids-devices/screenshot`,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': `multipart/form-data; boundary=${boundary}`
          },
          extraData: body.buffer,
          connectTimeout: 10_000,
          readTimeout: 30_000
        }
      );
      if (resp.responseCode !== 200) {
        throw new Error(`HTTP ${resp.responseCode}: ${resp.result?.toString().slice(0, 200)}`);
      }
    } finally {
      httpRequest.destroy();
    }
  }
}
