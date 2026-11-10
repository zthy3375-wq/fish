import {Capacitor, registerPlugin} from '@capacitor/core';

export type ParcelProvider = 'taobao' | 'pinduoduo';
export type ParcelLaunchStatus = 'opened' | 'not_installed' | 'unavailable' | 'cancelled' | 'unsupported';
export interface ParcelLaunchResult {provider: ParcelProvider; status: ParcelLaunchStatus}
interface ParcelShortcutsPlugin {
  open(options: {provider: ParcelProvider}): Promise<unknown>;
  openEmbedded(options: {provider: ParcelProvider}): Promise<unknown>;
}
const native = registerPlugin<ParcelShortcutsPlugin>('ParcelShortcuts');
export const parcelProviders = [
  {id: 'taobao', name: '淘宝', label: '淘宝出库码'},
  {id: 'pinduoduo', name: '拼多多', label: '拼多多出库码'},
] as const;

export const parcelShortcutsSupported = () => Capacitor.getPlatform() === 'android' && Capacitor.isPluginAvailable('ParcelShortcuts');

export async function openEmbeddedParcel(provider: ParcelProvider): Promise<boolean> {
  if (!['taobao', 'pinduoduo'].includes(provider) || !parcelShortcutsSupported()) return false;
  try {
    const result = await native.openEmbedded({provider});
    return !!result && typeof result === 'object' && 'provider' in result && result.provider === provider &&
      'status' in result && result.status === 'opened';
  } catch { return false }
}

export async function openParcelShortcut(provider: ParcelProvider): Promise<ParcelLaunchResult> {
  if (provider !== 'taobao' && provider !== 'pinduoduo') throw new Error('INVALID_PROVIDER');
  if (!parcelShortcutsSupported()) return {provider, status: 'unsupported'};
  try {
    // No arbitrary URI, account identity, credentials or identity code crosses this bridge.
    const result = await native.open({provider});
    if (result && typeof result === 'object' && 'provider' in result && result.provider === provider && 'status' in result && typeof result.status === 'string' &&
        ['opened', 'not_installed', 'unavailable', 'cancelled'].includes(result.status)) {
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
    case 'not_installed': return `未检测到${name} App，请先安装官方 App，再重试。`;
    case 'cancelled': return `已取消打开${name}，需要时可再次点击。`;
    case 'unsupported': return '请在 Android 客户端中使用出库码快捷入口。';
    default: return `暂时无法打开${name}出库码，请手动进入官方 App 查看身份码。`;
  }
}
