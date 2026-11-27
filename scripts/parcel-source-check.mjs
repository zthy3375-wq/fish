import {pathToFileURL} from 'node:url';

// Public destinations only. This tool never signs in, sets cookies, runs page scripts, or prints response bodies.
const routes = {
  'xiaomi-account': {url: 'https://account.xiaomi.com/', hosts: ['account.xiaomi.com']},
  'cainiao-site': {url: 'https://www.cainiao.com/', hosts: ['www.cainiao.com', 'cainiao.com']},
  'taobao-campus': {
    url: 'https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home',
    hosts: ['pages-fast.m.taobao.com', 'login.m.taobao.com', 'login.taobao.com', 'passport.taobao.com', 'm.taobao.com'],
  },
  'pinduoduo-pickup': {
    url: 'https://m.pinduoduo.net/mdkd/package?tab=ID_CODE',
    hosts: ['m.pinduoduo.net', 'mobile.yangkeduo.com'],
  },
};

export async function probePublicRoute(name, fetchPage = fetch, timeoutMs = 12_000) {
  const route = Object.hasOwn(routes, name) ? routes[name] : null;
  if (!route) throw new Error('Unknown public route');
  const signal = AbortSignal.timeout(timeoutMs);
  let target = new URL(route.url);
  const seen = new Set();
  for (let hop = 0; hop < 4; hop++) {
    if (seen.has(target.href)) return {name, outcome: 'redirect_loop', host: target.hostname};
    seen.add(target.href);
    let response;
    try {
      response = await fetchPage(target, {
        method: 'GET', redirect: 'manual', credentials: 'omit', referrerPolicy: 'no-referrer', signal,
        headers: {accept: 'text/html,application/xhtml+xml'},
      });
    } catch (error) {
      return {name, outcome: signal.aborted ? 'timeout' : 'network_error', host: target.hostname};
    }
    // A single GET is enough for each hop. Do not materialize HTML or inspect Set-Cookie.
    try { await response.body?.cancel(); } catch { /* Connection may already have closed. */ }
    const status = response.status;
    if (status >= 300 && status < 400) {
      const location = response.headers.get('location');
      if (!location) return {name, status, outcome: 'redirect_missing', host: target.hostname};
      let next;
      try { next = new URL(location, target); }
      catch { return {name, status, outcome: 'redirect_invalid', host: target.hostname}; }
      if (next.protocol !== 'https:' || next.username || next.password || next.port || !route.hosts.includes(next.hostname)) {
        return {name, status, outcome: 'outside_verified_hosts', host: target.hostname};
      }
      target = next;
      continue;
    }
    const media = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
    const html = media === 'text/html' || media === 'application/xhtml+xml';
    const authPage = /(?:^|[./-])(login|passport|verify|captcha)(?:[./-]|$)/i.test(target.hostname + target.pathname);
    return {name, status, host: target.hostname, outcome: status === 401 || status === 403 ? 'access_required_or_blocked' :
      !response.ok ? 'http_error' : !html ? 'unexpected_media' : authPage ? 'public_login_page' : 'public_html'};
  }
  return {name, outcome: 'redirect_limit', host: target.hostname};
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  const results = await Promise.all(Object.keys(routes).map(name => probePublicRoute(name)));
  console.log(JSON.stringify({authenticated: false, parcelDataInspected: false, results}, null, 2));
}
