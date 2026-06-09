/**
 * 进程内事件总线 — service 之间通信，避免循环依赖
 *
 * 已知事件（约定）：
 *   'configChanged'           ConfigStore 任意字段变更
 *   'displayUrlChanged'       displayUrl 变化（Index 页面订阅刷新 Web 组件）
 *   'refreshPage'             MQTT refreshPage 指令触发 webview reload
 *   'mqttConnected'/'mqttDisconnected'
 *   'watchdogFreezeDetected'
 */

// ArkTS 严格模式不允许 ESObject / any，统一用 Object | null 作为弱类型 payload；
// 真正需要结构时各订阅方自己 as 到具体类型。
type Listener = (payload?: Object | null) => void;

class EventBus {
  private listeners = new Map<string, Set<Listener>>();

  on(event: string, fn: Listener): () => void {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(fn);
    return (): void => this.off(event, fn);
  }

  off(event: string, fn: Listener): void {
    this.listeners.get(event)?.delete(fn);
  }

  emit(event: string, payload?: Object | null): void {
    this.listeners.get(event)?.forEach((fn: Listener): void => {
      try { fn(payload); } catch (_) { /* 静默 */ }
    });
  }
}

export const eventBus = new EventBus();
