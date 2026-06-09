import { webview } from '@kit.ArkWeb';
import http from '@ohos.net.http';
import { ConfigStore } from './ConfigStore';
import { Logger } from '../utils/logger';

const TAG = 'Watchdog';
const CHECK_INTERVAL_MS = 30_000;
const STALE_THRESHOLD_MS = 90_000;
const MODULUS = 16_777_216; // 2^24

/**
 * 注入到页面的脚本：每秒在 1×1 canvas 编码当前时间戳
 * 对应 fids_player_electron/src/main/watchdog.ts INJECT_SCRIPT
 */
const INJECT_SCRIPT = `(function(){
  if(window.__fidsWatchdogTimer||window.__FIDS_WATCHDOG_MANAGED__)return;
  function getCanvas(){
    var c=document.getElementById('__fids-watchdog__');
    if(!c){
      c=document.createElement('canvas');
      c.id='__fids-watchdog__';
      c.width=1; c.height=1;
      c.style.cssText='position:fixed;right:0;bottom:0;width:1px;height:1px;z-index:2147483647;pointer-events:none';
      document.body.appendChild(c);
    }
    return c;
  }
  function tick(){
    try{
      var v=Date.now()%16777216;
      var ctx=getCanvas().getContext('2d');
      ctx.fillStyle='rgb('+((v>>16)&255)+','+((v>>8)&255)+','+(v&255)+')';
      ctx.fillRect(0,0,1,1);
    }catch(e){}
  }
  tick();
  window.__fidsWatchdogTimer=setInterval(tick,1000);
})();`;

const READ_SCRIPT = `(function(){
  var c=document.getElementById('__fids-watchdog__');
  if(!c)return null;
  try{
    var d=c.getContext('2d').getImageData(0,0,1,1).data;
    return d[0]*65536+d[1]*256+d[2];
  }catch(e){return null;}
})()`;

/**
 * 页面冻结检测器
 *
 * 行为完全对齐 fids_player_electron/src/main/watchdog.ts：
 *   - 每 30 秒检测一次
 *   - 像素时间戳与当前时间差 > 90 秒 → 判定冻结，上报 alert=true
 *   - 恢复正常后上报 alert=false
 *   - 启动后首次正常检测主动上报 alert=false（自愈）
 */
export class Watchdog {
  private static instance: Watchdog | null = null;
  private controller: webview.WebviewController | null = null;
  private timer: number | null = null;
  private frozenSince: number | null = null;
  private recoveryAcknowledged = false;

  static getInstance(): Watchdog {
    if (!Watchdog.instance) Watchdog.instance = new Watchdog();
    return Watchdog.instance;
  }

  /** 在 Web 组件 onPageEnd 时调用，注入脚本到页面 */
  attach(controller: webview.WebviewController): void {
    this.controller = controller;
    try {
      controller.runJavaScript(INJECT_SCRIPT);
    } catch (e) {
      Logger.warn(TAG, '注入失败', e);
    }
    this.start();
  }

  start(): void {
    if (this.timer !== null) return;
    Logger.info(TAG, '启动，间隔 30s，冻结阈值 90s');
    this.timer = setInterval(() => this.check(), CHECK_INTERVAL_MS);
  }

  stop(): void {
    if (this.timer !== null) { clearInterval(this.timer); this.timer = null; }
  }

  /** URL 切换时调用，重置状态 */
  reset(): void {
    this.frozenSince = null;
    this.recoveryAcknowledged = false;
    Logger.debug(TAG, '状态已重置');
  }

  private async check(): Promise<void> {
    if (!this.controller) return;
    try {
      const result = await this.controller.runJavaScript(READ_SCRIPT);
      const decoded = result === undefined || result === null ? null : Number(result);
      if (decoded === null || Number.isNaN(decoded)) {
        Logger.debug(TAG, '未找到 canvas，等待页面加载');
        return;
      }
      const nowMod = Date.now() % MODULUS;
      let diff = nowMod - decoded;
      if (diff < 0) diff += MODULUS;
      Logger.debug(TAG, `canvas=${decoded} now=${nowMod} diff=${Math.round(diff / 1000)}s`);

      if (diff > STALE_THRESHOLD_MS) {
        const wasFrozen = this.frozenSince !== null;
        if (!this.frozenSince) this.frozenSince = Date.now();
        const frozenSec = Math.round((Date.now() - this.frozenSince) / 1000);
        Logger.warn(TAG, `页面疑似冻结 ${frozenSec}s，像素时差 ${Math.round(diff / 1000)}s`);
        if (!wasFrozen) {
          await this.notifyAlert(true, `页面冻结 ${frozenSec}s`);
          this.recoveryAcknowledged = false;
        }
      } else {
        if (this.frozenSince) {
          this.frozenSince = null;
          this.recoveryAcknowledged = true;
          await this.notifyAlert(false);
        } else if (!this.recoveryAcknowledged) {
          // 启动后首次正常检测，主动同步未冻结状态（自愈）
          this.recoveryAcknowledged = true;
          await this.notifyAlert(false);
        }
      }
    } catch (e) {
      Logger.error(TAG, '检测异常', e);
    }
  }

  private async notifyAlert(alert: boolean, message?: string): Promise<void> {
    const cfg = ConfigStore.getInstance().getAll();
    if (!cfg.serverUrl || !cfg.deviceId) return;
    try {
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request(
        `${cfg.serverUrl}/api/device-watchdog`,
        {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify({ deviceId: cfg.deviceId, alert, message }),
          connectTimeout: 5000
        }
      );
      httpRequest.destroy();
      Logger.info(TAG, `通知 alert=${alert} → HTTP ${resp.responseCode}`);
    } catch (e) {
      Logger.error(TAG, '上报失败', e);
    }
  }
}
