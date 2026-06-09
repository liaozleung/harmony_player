import { connection } from '@kit.NetworkKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import deviceInfo from '@ohos.deviceInfo';
import { Logger } from '../utils/logger';

const TAG = 'SystemInfo';

/** /proc/stat 上次读数缓存 */
interface CpuStat {
  idle: number;
  total: number;
}

export interface SysSnapshot {
  cpu: number;        // CPU 利用率 0..100；未知 = -1
  mem: number;        // 内存使用率 0..100
  disk: number;       // 磁盘使用率 0..100
  osVersion: string;
  osType: string;
  brand: string;
  model: string;
}

/**
 * 系统资源采集
 *
 * OpenHarmony 沙箱较 Linux 严格，部分指标读取受限：
 *   - CPU 用 /proc/stat 直读（容器化设备 ROOT 才能读，非 ROOT 设备返回降级值）
 *   - 内存用 /proc/meminfo
 *   - 磁盘用 statfs.getFreeSize（API 12 把旧的 statvfs 改名 statfs）
 *   - IP 用 NetworkKit
 */
export class SystemInfo {
  private static lastCpuStat: CpuStat | null = null;

  static async collect(): Promise<SysSnapshot> {
    const cpu: number = await SystemInfo.getCpuUsage();
    const mem: number = await SystemInfo.getMemoryUsage();
    const disk: number = await SystemInfo.getDiskUsage();
    const snap: SysSnapshot = {
      cpu,
      mem,
      disk,
      osVersion: deviceInfo.osFullName ?? 'OpenHarmony',
      osType: 'OpenHarmony',
      brand: deviceInfo.brand ?? 'unknown',
      model: deviceInfo.productModel ?? 'unknown'
    };
    return snap;
  }

  /** /proc/stat 计算 CPU 利用率；不可读时返回 -1 表示未知 */
  private static async getCpuUsage(): Promise<number> {
    try {
      const f = fileIo.openSync('/proc/stat', fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(4096);
      const len = fileIo.readSync(f.fd, buf);
      fileIo.closeSync(f);
      const view = new Uint8Array(buf, 0, len);
      let text = '';
      for (let i = 0; i < view.length; i++) text += String.fromCharCode(view[i]);
      const line = text.split('\n')[0]; // "cpu  user nice system idle iowait..."
      const parts = line.split(/\s+/);
      const nums: number[] = [];
      for (let i = 1; i < parts.length; i++) nums.push(Number(parts[i]));
      const idle = nums[3] + (nums[4] ?? 0);
      let total = 0;
      for (let i = 0; i < nums.length; i++) total += nums[i];
      const last = SystemInfo.lastCpuStat;
      if (last !== null) {
        const dIdle = idle - last.idle;
        const dTotal = total - last.total;
        SystemInfo.lastCpuStat = { idle, total };
        if (dTotal > 0) return Math.round(((dTotal - dIdle) / dTotal) * 100);
      }
      SystemInfo.lastCpuStat = { idle, total };
      return -1;
    } catch (e) {
      Logger.warn(TAG, 'cpu read failed', e);
      return -1;
    }
  }

  /** /proc/meminfo 计算内存使用率 */
  private static async getMemoryUsage(): Promise<number> {
    try {
      const f = fileIo.openSync('/proc/meminfo', fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(4096);
      const len = fileIo.readSync(f.fd, buf);
      fileIo.closeSync(f);
      const view = new Uint8Array(buf, 0, len);
      let text = '';
      for (let i = 0; i < view.length; i++) text += String.fromCharCode(view[i]);
      const totalMatch = text.match(/MemTotal:\s+(\d+)/);
      const availMatch = text.match(/MemAvailable:\s+(\d+)/);
      const total = Number(totalMatch !== null && totalMatch[1] !== undefined ? totalMatch[1] : 0);
      const avail = Number(availMatch !== null && availMatch[1] !== undefined ? availMatch[1] : 0);
      if (total > 0) return Math.round(((total - avail) / total) * 100);
      return -1;
    } catch (e) {
      Logger.warn(TAG, 'mem read failed', e);
      return -1;
    }
  }

  /** 沙箱可访问的根目录磁盘使用率 */
  private static async getDiskUsage(): Promise<number> {
    try {
      const total = await statfs.getTotalSize('/data/storage/el2/base');
      const free = await statfs.getFreeSize('/data/storage/el2/base');
      if (total > 0) return Math.round(((total - free) / total) * 100);
      return -1;
    } catch (e) {
      Logger.warn(TAG, 'disk read failed', e);
      return -1;
    }
  }

  /** 获取设备 IP（首选 IPv4） */
  static async getIpAddress(): Promise<string> {
    try {
      const netHandle = await connection.getDefaultNet();
      const props = await connection.getConnectionProperties(netHandle);
      const addrs = props.linkAddresses;
      if (addrs !== undefined) {
        for (let i = 0; i < addrs.length; i++) {
          const a = addrs[i];
          const ip = a.address?.address;
          if (typeof ip === 'string' && ip.indexOf('.') >= 0) return ip;
        }
      }
      return '';
    } catch (e) {
      Logger.warn(TAG, 'ip read failed', e);
      return '';
    }
  }
}
