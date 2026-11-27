import {describe, expect, it, vi} from 'vitest';
// The diagnostics CLI is a standalone Node module.
import {probePublicRoute} from '../scripts/parcel-source-check.mjs';

const response = (status, headers = {}) => new Response(null, {status, headers});
describe('public parcel entry diagnostics', () => {
  it('reports an official login without forwarding or returning credentials', async () => {
    const get = vi.fn()
      .mockResolvedValueOnce(response(302, {location: '/fe/service/login?opaque=discard-me', 'Set-Cookie': 'fixture=sensitive'}))
      .mockResolvedValueOnce(response(200, {'Content-Type': 'text/html; charset=UTF-8'}));
    const result = await probePublicRoute('xiaomi-account', get);
    expect(result).toEqual({name: 'xiaomi-account', status: 200, host: 'account.xiaomi.com', outcome: 'public_login_page'});
    expect(JSON.stringify(result)).not.toContain('discard-me');
    expect(get).toHaveBeenCalledTimes(2);
    for (const [, options] of get.mock.calls) {
      expect(options).toMatchObject({method: 'GET', credentials: 'omit', redirect: 'manual', referrerPolicy: 'no-referrer'});
      expect(options.headers).toEqual({accept: 'text/html,application/xhtml+xml'});
    }
  });
  it('never follows an unverified destination or misreads access denial as empty', async () => {
    const get = vi.fn().mockResolvedValue(response(302, {location: 'https://example.invalid/'}));
    expect((await probePublicRoute('cainiao-site', get)).outcome).toBe('outside_verified_hosts');
    expect(get).toHaveBeenCalledTimes(1);
    get.mockResolvedValue(response(403));
    expect((await probePublicRoute('taobao-campus', get)).outcome).toBe('access_required_or_blocked');
  });
  it('terminates redirects and refuses unlisted destinations', async () => {
    const get = vi.fn().mockResolvedValue(response(302, {location: '/'}));
    expect((await probePublicRoute('cainiao-site', get)).outcome).toBe('redirect_loop');
    expect(get).toHaveBeenCalledTimes(1);
    await expect(probePublicRoute('https://example.invalid', get)).rejects.toThrow('Unknown public route');
  });
});
