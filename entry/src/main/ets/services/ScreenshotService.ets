import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import http from '@ohos.net.http';
import { ConfigStore } from './ConfigStore';
import { Logger } from '../utils/logger';

const TAG = 'ScreenshotService';

/**
 * 截图上传 — 占位骨架
 *
 * 流程：
 *   1. 调 webview.WebviewController 截当前 Web 内容
 *   2. 通过 image.createImagePacker() 编码为 JPEG（quality 65）
 *   3. multipart/form-data POST 到 {serverUrl}/api/fids-devices/screenshot
 *
 * 注意：
 *   - HTTP 库 multipart 上传当前需要手动构造 boundary 与字节流
 *   - 第二阶段实现完整版；当前只列骨架
 */
export class ScreenshotService {
  /**
   * 截图并上传。需要传入当前页面的 WebviewController（由 Index 页面持有）。
   */
  static async captureAndUpload(controller: webview.WebviewController): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.serverUrl || !cfg.deviceId) {
      Logger.warn(TAG, '设备未配置，跳过截图');
      return;
    }

    try {
      // 1. 截图（鸿蒙 ArkWeb API：getBackForwardEntries / takeSnapshot）
      // 具体 API 名以 5.0 SDK 为准；下面是设计骨架
      // const pixelMap = await controller.takeSnapshot({ pixelType: image.PixelMapFormat.RGBA_8888 });

      // 2. 编码为 JPEG
      // const packer = image.createImagePacker();
      // const buf = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 65 });

      // 3. 上传 multipart
      // TODO: 完整 multipart 构造 + http.request

      Logger.info(TAG, 'captureAndUpload — 骨架待完成');
    } catch (e) {
      Logger.error(TAG, '截图上传失败', e);
    }
  }
}
