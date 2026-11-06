export const publicLoginUrl: 'https://jwgl.hdc.edu.cn/xtgl/login_slogin.html';
export interface PublicLoginInspection {
  sha256: string;
  bytes: number;
  publicVersionLabel: string | null;
  zftalAssetsPresent: boolean;
  directLoginFormPresent: boolean;
  unifiedAuthTarget: { present: boolean; nonempty: boolean };
  unifiedAuthDisplayFlag: { present: boolean; nonempty: boolean };
  unifiedAuthLabelPresent: boolean;
  authorizationProtocol: 'not-established';
}
export function inspectPublicLogin(html: string): PublicLoginInspection;
export function inspectLivePublicLogin(): Promise<PublicLoginInspection & {
  observedAt: string; url: typeof publicLoginUrl; method: 'GET'; status: number; xFrameOptions: string | null;
}>;
