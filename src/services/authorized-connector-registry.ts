import {AcademicConnectionController, type AuthorizedAcademicConnector} from './academic-connection';

/**
 * No school connector is bundled. Integrations must be explicitly reviewed,
 * use school-supported authorization and be registered at app bootstrap.
 */
let connector: AuthorizedAcademicConnector | null = null;
let controller: AcademicConnectionController | null = null;

export function registerAuthorizedAcademicConnector(value: AuthorizedAcademicConnector) {
  if (connector) throw new Error('教务连接器已注册，不允许重复覆盖');
  if (!value.id || !value.displayName) throw new Error('连接器标识不能为空');
  connector = value;
  controller = new AcademicConnectionController(value);
}

export function getAuthorizedAcademicConnector(): AuthorizedAcademicConnector | null {
  return connector;
}

export function getAcademicConnectionController(): AcademicConnectionController | null {
  return controller;
}
