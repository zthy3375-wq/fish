import {Capacitor, registerPlugin} from '@capacitor/core';

export interface QuzhiWallet {total: string | null; cash: string | null; gift: string | null}
export interface QuzhiBill {id: string; date: string; amount: string | null; description: string}
export interface QuzhiSnapshot {
  connected: boolean;
  expired: boolean;
  phone: string;
  school?: string;
  wallet?: QuzhiWallet;
  walletUpdatedAt?: number;
  bills?: QuzhiBill[];
  billsMonth?: string;
  billsUpdatedAt?: number;
  billsTruncated?: boolean;
  issues?: Partial<Record<'wallet' | 'school' | 'bills', string>>;
}
export interface QuzhiBathCode {code:string|null;enabled:boolean;phone:string;queriedAt:number}
interface QuzhiPlugin {
  getBathCode(): Promise<QuzhiBathCode>;
  getSnapshot(): Promise<QuzhiSnapshot>;
  login(): Promise<QuzhiSnapshot>;
  refresh(options: {month: string}): Promise<QuzhiSnapshot>;
  logout(): Promise<QuzhiSnapshot>;
  openRecharge(): Promise<{opened: boolean}>;
}
export const quzhiClient = registerPlugin<QuzhiPlugin>('QuzhiCampus');
export const quzhiSupported = () => Capacitor.isNativePlatform() && Capacitor.isPluginAvailable('QuzhiCampus');

export function quzhiMonth(date = new Date()): string {
  const fields = new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit'}).formatToParts(date);
  return `${fields.find(p=>p.type==='year')!.value}-${fields.find(p=>p.type==='month')!.value}`;
}
export function quzhiMoney(value?: string | null): string {
  if (value == null || !/^-?\d{1,12}(\.\d{1,6})?$/.test(value)) return '—';
  return Number(value).toLocaleString('zh-CN', {minimumFractionDigits:2, maximumFractionDigits:3, useGrouping:false});
}
export function quzhiIssue(code?: string): string {
  return ({ACCOUNT:'账号信息不完整，请重新连接趣智校园',AUTH:'登录已失效，请重新连接', VERIFY:'平台要求验证或稍后重试，请勿连续提交', FORMAT:'返回信息暂时无法识别，保留上次数据',
    UNVERIFIED_UNITS:'余额单位暂无法核对，保留上次数据', SERVICE:'趣智暂未完成请求，请稍后刷新', NETWORK:'网络连接失败，保留上次数据', NO_ALIPAY:'请先安装支付宝，再进入趣智充值页',
    BUSY:'趣智操作正在进行，请稍候', UNAVAILABLE:'请在 Android 客户端连接趣智校园'} as Record<string,string>)[code ?? ''] ?? '操作未完成，请稍后重试';
}
