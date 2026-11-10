import {Capacitor, registerPlugin} from '@capacitor/core';

export type ParcelProvider = 'taobao' | 'pinduoduo';
export type ParcelLaunchStatus = 'opened' | 'app_opened' | 'system_opened' | 'web_opened' | 'not_installed' | 'unavailable' | 'cancelled' | 'unsupported';
export interface ParcelLaunchResult {provider: ParcelProvider; status: ParcelLaunchStatus}
export type ParcelOpenMode = 'app' | 'system';
interface ParcelShortcutsPlugin {open(options: {provider: ParcelProvider; mode?: ParcelOpenMode}): Promise<unknown>}
const native = registerPlugin<ParcelShortcutsPlugin>('ParcelShortcuts');
export const parcelProviders = [
  {id: 'taobao', name: '淘宝', label: '淘宝出库码'},
  {id: 'pinduoduo', name: '拼多多', label: '拼多多出库码'},
] as const;

export const parcelShortcutsSupported = () => Capacitor.getPlatform() === 'android' && Capacitor.isPluginAvailable('ParcelShortcuts');

export async function openParcelShortcut(provider: ParcelProvider, mode: ParcelOpenMode = 'app'): Promise<ParcelLaunchResult> {
  if (provider !== 'taobao' && provider !== 'pinduoduo') throw new Error('INVALID_PROVIDER');
  if (mode !== 'app' && mode !== 'system') throw new Error('INVALID_PROVIDER');
  if (!parcelShortcutsSupported()) return {provider, status: 'unsupported'};
  try {
    // No arbitrary URI, account identity, credentials or identity code crosses this bridge.
    const result = await native.open(mode === 'system' ? {provider, mode} : {provider});
    if (result && typeof result === 'object' && 'provider' in result && result.provider === provider && 'status' in result && typeof result.status === 'string' &&
        ['opened', 'app_opened', 'system_opened', 'web_opened', 'not_installed', 'unavailable', 'cancelled'].includes(result.status)) {
      return {provider, status: result.status as ParcelLaunchStatus};
    }
  } catch (error) {
    if (error && typeof error === 'object' && 'code' in error && error.code === 'CANCELLED') return {provider, status: 'cancelled'};
  }
  return {provider, status: 'unavailable'};
}

export function parcelLaunchMessage(result: ParcelLaunchResult): string {
  const name = result.provider === 'taobao' ? '淘宝' : '拼多多';
  switch (result.status) {
    case 'opened': return `已请求打开${name}，请在官方 App 内查看身份码。返回本应用不代表已出库。`;
    case 'app_opened': return `已请求打开${name}首页，请在官方 App 内进入出库码。当前未确认进入身份码页面。`;
    case 'system_opened': return `已交给系统打开${name}链接。如出现应用选择，请选择官方${name}；当前未确认进入身份码页面。`;
    case 'web_opened': return `已交给系统打开${name}官方网页，出库身份码仍需在官方 App 内查看。`;
    case 'not_installed': return `未检测到${name}的安卓版本。已安装鸿蒙版可尝试系统兼容打开；尚未安装请先安装官方 App。`;
    case 'cancelled': return `已取消打开${name}，需要时可再次点击。`;
    case 'unsupported': return '请在 Android 客户端中使用出库码快捷入口。';
    default: return `暂时无法打开${name}出库码，请手动进入官方 App 查看身份码。`;
  }
}
