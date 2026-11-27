import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const endpoint = 'https://api.kuaidi100.com/pickupCode/query';

export class PickupQueryError extends Error {
  constructor(code) {
    super(code);
    this.name = 'PickupQueryError';
    this.code = code;
  }
}

/** The Kuaidi100 business API requires a previously subscribed waybill and recipient authorization. */
export async function lookupPickupCode(input, credentials, {fetcher = fetch, now = Date.now} = {}) {
  const {carrier, trackingNumber, receiverPhone} = input;
  const {key, secret} = credentials;
  if (typeof carrier !== 'string' || !/^[a-z0-9]{1,50}$/.test(carrier) ||
      typeof trackingNumber !== 'string' || !/^[A-Z0-9-]{4,64}$/.test(trackingNumber) ||
      typeof receiverPhone !== 'string' || !/^1[3-9]\d{9}$/.test(receiverPhone)) {
    throw new PickupQueryError('invalid_waybill');
  }
  if (typeof key !== 'string' || typeof secret !== 'string' || !key.trim() || !secret.trim() || key.length > 512 || secret.length > 512) {
    throw new PickupQueryError('missing_credentials');
  }

  const param = JSON.stringify({kuaidicom: carrier, kuaidinum: trackingNumber, receiverPhone});
  const t = String(now());
  const sign = createHash('md5').update(param + t + key + secret, 'utf8').digest('hex').toUpperCase();
  let response;
  try {
    response = await fetcher(endpoint, {
      method: 'POST', redirect: 'error', cache: 'no-store', signal: AbortSignal.timeout(10_000),
      headers: {'content-type': 'application/x-www-form-urlencoded', accept: 'application/json'},
      body: new URLSearchParams({method: 'pickupCodeQuery', key, t, sign, param}),
    });
  } catch {
    throw new PickupQueryError('unreachable');
  }
  if (response.status === 429) throw new PickupQueryError('rate_limited');
  if (!response.ok) throw new PickupQueryError('http_error');

  let data;
  try { data = await limitedJson(response); }
  catch { throw new PickupQueryError('invalid_response'); }
  if (String(data?.code) !== '200' || data?.success !== true) {
    const reason = {
      10002: 'recipient_or_carrier_mismatch', 10005: 'not_subscribed',
      30002: 'invalid_signature', 30003: 'invalid_credentials',
    }[String(data?.code)];
    throw new PickupQueryError(reason ?? 'provider_rejected');
  }

  const parcel = data.data;
  if (parcel?.kuaidicom !== carrier || parcel?.kuaidinum !== trackingNumber) throw new PickupQueryError('waybill_mismatch');
  const pickupCode = cleanText(parcel.pickUpCode, 64);
  if (!pickupCode) throw new PickupQueryError('code_not_returned');
  return {
    carrier, trackingNumber, pickupCode,
    station: cleanText(parcel.pickUpStation, 160),
    address: cleanText(parcel.pickUpAddress, 280),
    statusDescription: cleanText(parcel.statusDesc, 160),
  };
}

async function limitedJson(response) {
  const body = response.body?.getReader();
  if (!body) throw new Error('Empty body');
  const decoder = new TextDecoder('utf-8', {fatal: true});
  let size = 0;
  let text = '';
  try {
    for (;;) {
      const {done, value} = await body.read();
      if (done) break;
      size += value.byteLength;
      if (size > 65_536) throw new Error('Oversize response');
      text += decoder.decode(value, {stream: true});
    }
    return JSON.parse(text + decoder.decode());
  } finally { await body.cancel().catch(() => {}); }
}

function cleanText(value, maximum) {
  if (typeof value !== 'string') return undefined;
  const text = value.trim();
  return text && text.length <= maximum && !/[\u0000-\u001f\u007f-\u009f]/.test(text) ? text : undefined;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv[2] !== '--live') {
    console.error('Run with --live only for an authorized, previously subscribed waybill. The provider may charge.');
    process.exitCode = 2;
  } else {
    try {
      const chunks = [];
      let length = 0;
      for await (const chunk of process.stdin) {
        length += chunk.length;
        if (length > 4096) throw new PickupQueryError('invalid_input');
        chunks.push(chunk);
      }
      const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const result = await lookupPickupCode(input, {key: process.env.KUAIDI100_KEY, secret: process.env.KUAIDI100_SECRET});
      // Print a result marker only. The CLI must not log phone numbers, keys, waybills or codes.
      console.log(JSON.stringify({result: 'pickup_code_returned', codeLength: result.pickupCode.length}));
    } catch (error) {
      console.error(JSON.stringify({result: 'failed', reason: error instanceof PickupQueryError ? error.code : 'invalid_input'}));
      process.exitCode = 1;
    }
  }
}
