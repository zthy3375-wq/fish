/** Only one known public login GET. No login POST, cookie jar, internal endpoints or resource crawl. */
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
export const publicLoginUrl = "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html";
export function inspectPublicLogin(html) {
  const input = (id) => {
    const tag = [...html.matchAll(/<input\b[^>]*>/gi)]
      .map((m) => m[0])
      .find((t) => new RegExp(`\\bid\\s*=\\s*["']${id}["']`, "i").test(t));
    const value = tag?.match(/\bvalue\s*=\s*["']([^"']*)["']/i)?.[1] ?? "";
    return { present: !!tag, nonempty: !!value.trim() };
  };
  return {
    sha256: createHash("sha256").update(html).digest("hex"),
    bytes: Buffer.byteLength(html),
    publicVersionLabel: html.match(/版本\s*(V-[\d.]+)/i)?.[1] ?? null,
    zftalAssetsPresent: html.includes("/zftal-ui-"),
    directLoginFormPresent:
      /<form\b[^>]*action=["']\/xtgl\/login_slogin\.html["'][^>]*method=["']post["']/i.test(
        html,
      ),
    unifiedAuthTarget: input("authJwglxtLoginURL"),
    unifiedAuthDisplayFlag: input("rzzxxs"),
    // Presence is not proof of an enabled authorization service or a callable API.
    unifiedAuthLabelPresent: html.includes("统一身份认证"),
    authorizationProtocol: "not-established",
  };
}
export async function inspectLivePublicLogin() {
  const response = await fetch(publicLoginUrl, {
    redirect: "error",
    signal: AbortSignal.timeout(20000),
    headers: { accept: "text/html" },
  });
  if (
    !response.ok ||
    !response.headers.get("content-type")?.includes("text/html")
  )
    throw Error("Public login request did not return HTML successfully");
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 1024 * 1024) throw Error("Public page exceeds 1 MB limit");
    chunks.push(chunk);
  }
  return {
    observedAt: new Date().toISOString(),
    url: publicLoginUrl,
    method: "GET",
    status: response.status,
    xFrameOptions: response.headers.get("x-frame-options"),
    ...inspectPublicLogin(Buffer.concat(chunks).toString("utf8")),
  };
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    console.log(JSON.stringify(await inspectLivePublicLogin(), null, 2));
  } catch {
    console.error(
      "Public page inspection failed; no authentication or alternate endpoint was attempted.",
    );
    process.exitCode = 1;
  }
}
