import {Capacitor, registerPlugin} from '@capacitor/core';

export type PangguaiPage = 'wallet' | 'operators' | 'login';
export type PangguaiLaunchStatus = 'opened' | 'cancelled' | 'unavailable' | 'unsupported';
export interface PangguaiLaunchResult {page: PangguaiPage; status: PangguaiLaunchStatus}
interface PangguaiOfficialPlugin {open(options: {page: PangguaiPage}): Promise<unknown>}
const native = registerPlugin<PangguaiOfficialPlugin>('PangguaiOfficial');

export const pangguaiOfficialSupported = () => Capacitor.getPlatform() === 'android' && Capacitor.isPluginAvailable('PangguaiOfficial');

/** Only a fixed page name crosses the bridge. No URLs, account data or payment parameters. */
export async function openPangguaiOfficial(page: PangguaiPage): Promise<PangguaiLaunchResult> {
  if (!['wallet', 'operators', 'login'].includes(page)) throw new Error('INVALID_PAGE');
  if (!pangguaiOfficialSupported()) return {page, status: 'unsupported'};
  try {
    const result = await native.open({page});
    if (result && typeof result === 'object' && 'page' in result && result.page === page && 'status' in result &&
        typeof result.status === 'string' && ['opened', 'cancelled', 'unavailable'].includes(result.status)) {
      return {page, status: result.status as PangguaiLaunchStatus};
    }
  } catch {
    // Native error payloads may contain third-party information; show only our fixed message.
  }
  return {page, status: 'unavailable'};
}

export function pangguaiLaunchMessage(result: PangguaiLaunchResult): string {
  switch (result.status) {
    case 'opened': return '已请求打开胖乖官方页面。余额、登录与充值结果请在官方页面核对，返回不代表充值成功。';
    case 'cancelled': return '已取消打开胖乖官方页面，需要时可再次点击。';
    case 'unsupported': return '请在 Android 客户端中打开胖乖官方页面。';
    default: return '暂时无法打开胖乖官方页面，请手动进入胖乖官方 App 或支付宝胖乖生活小程序。';
  }
}
