import type {AuthorizedAcademicConnector} from './academic-connection';

/**
 * The product intentionally ships with no school connector.
 * A verified, separately-reviewed integration may register one at bootstrap.
 * Do not register a connector that accepts passwords or reuses website cookies.
 */
let connector: AuthorizedAcademicConnector | null = null;

export function registerAuthorizedAcademicConnector(value: AuthorizedAcademicConnector) {
  if (connector) throw new Error('教务连接器已注册，不允许重复覆盖');
  if (!value.id || !value.displayName) throw new Error('连接器标识不能为空');
  connector = value;
}

export function getAuthorizedAcademicConnector(): AuthorizedAcademicConnector | null {
  return connector;
}
