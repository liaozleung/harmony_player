import hilog from '@ohos.hilog';

const DOMAIN = 0xFA00;

export class Logger {
  private static log(level: 'D' | 'I' | 'W' | 'E', tag: string, ...args: Object[]) {
    const msg = args.map((a) => {
      if (a === null) return 'null';
      if (a === undefined) return 'undefined';
      if (typeof a === 'object') {
        try { return JSON.stringify(a); } catch (_) { return String(a); }
      }
      return String(a);
    }).join(' ');
    switch (level) {
      case 'D': hilog.debug(DOMAIN, tag, '%{public}s', msg); break;
      case 'I': hilog.info(DOMAIN, tag, '%{public}s', msg); break;
      case 'W': hilog.warn(DOMAIN, tag, '%{public}s', msg); break;
      case 'E': hilog.error(DOMAIN, tag, '%{public}s', msg); break;
    }
  }
  static debug(tag: string, ...args: Object[]) { Logger.log('D', tag, ...args); }
  static info(tag: string, ...args: Object[]) { Logger.log('I', tag, ...args); }
  static warn(tag: string, ...args: Object[]) { Logger.log('W', tag, ...args); }
  static error(tag: string, ...args: Object[]) { Logger.log('E', tag, ...args); }
}
