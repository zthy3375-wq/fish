import {
  AcademicConnectionController,
  validProviderId,
  type AuthorizedAcademicConnector,
} from "./academic-connection";
// Deliberately empty: a public login page is not evidence of an approved API.
let connector: AuthorizedAcademicConnector | null = null;
let controller: AcademicConnectionController | null = null;
export function registerAuthorizedAcademicConnector(
  value: AuthorizedAcademicConnector,
) {
  if (connector) throw Error("教务连接器已注册，不允许重复覆盖");
  if (
    !value ||
    !validProviderId(value.id) ||
    typeof value.displayName !== "string" ||
    !value.displayName.trim() ||
    value.displayName.length > 80 ||
    ![
      "beginOfficialAuthorization",
      "getSessionStatus",
      "fetchMyAcademicData",
      "disconnect",
    ].every(
      (key) =>
        typeof value[key as keyof AuthorizedAcademicConnector] === "function",
    )
  )
    throw Error("教务连接器契约不完整");
  const instance = new AcademicConnectionController(value);
  connector = value;
  controller = instance;
}
export const getAuthorizedAcademicConnector = () => connector;
export const getAcademicConnectionController = () => controller;
