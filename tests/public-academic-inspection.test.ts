import { it, expect } from "vitest";
// This is a pure parser test. The CLI's live GET is only run manually and never by npm test.
import { inspectPublicLogin } from "../scripts/inspect-public-academic.mjs";
it("distinguishes an empty template SSO target from a configured one and retains no secrets", () => {
  const html = `<form action="/xtgl/login_slogin.html" method="post"></form>
    <input id="authJwglxtLoginURL" value=""><input id="rzzxxs" value="">
    <input id="csrftoken" value="DO-NOT-RETAIN"><script src="/zftal-ui-v5/app.js"></script>
    统一身份认证 版本V-9.0`;
  const report = inspectPublicLogin(html);
  expect(report).toMatchObject({
    publicVersionLabel: "V-9.0",
    zftalAssetsPresent: true,
    directLoginFormPresent: true,
    unifiedAuthTarget: { present: true, nonempty: false },
    unifiedAuthLabelPresent: true,
    authorizationProtocol: "not-established",
  });
  expect(JSON.stringify(report)).not.toContain("DO-NOT-RETAIN");
  const configured = inspectPublicLogin(
    `<input value='https://sso.invalid/?secret=DO-NOT-RETAIN' id='authJwglxtLoginURL'>`,
  );
  expect(configured.unifiedAuthTarget).toEqual({
    present: true,
    nonempty: true,
  });
  expect(configured.authorizationProtocol).toBe("not-established");
  expect(JSON.stringify(configured)).not.toContain("DO-NOT-RETAIN");
});
it("makes no authentication claims for missing inputs or unrelated HTML", () => {
  expect(inspectPublicLogin("<html>unavailable</html>")).toMatchObject({
    publicVersionLabel: null,
    unifiedAuthTarget: { present: false, nonempty: false },
    authorizationProtocol: "not-established",
  });
});
