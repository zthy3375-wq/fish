import {test} from 'vitest';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lookupPickupCode} from './parcel-kuaidi100.mjs';

const input = {carrier: 'jtexpress', trackingNumber: 'TEST00001', receiverPhone: '13000000000'};
const credentials = {key: 'test-only-key', secret: 'test-only-secret'};
const result = {kuaidicom: input.carrier, kuaidinum: input.trackingNumber, pickUpCode: '001-5', pickUpStation: '测试站'};
const mock = body => async () => Response.json(body);

test('query follows the published entitlements, form and response mapping', async () => {
  const code = await lookupPickupCode(input, credentials, {
    now: () => 1800000000000,
    fetcher: async (url, init) => {
      assert.equal(url, 'https://api.kuaidi100.com/pickupCode/query');
      assert.equal(init.method, 'POST');
      assert.equal(init.redirect, 'error');
      const {param, t, key, sign, method} = Object.fromEntries(init.body);
      assert.equal(method, 'pickupCodeQuery');
      assert.equal(key, credentials.key);
      assert.equal(t, '1800000000000');
      assert.deepEqual(JSON.parse(param), {kuaidicom: input.carrier, kuaidinum: input.trackingNumber, receiverPhone: input.receiverPhone});
      assert.equal(sign, createHash('md5').update(param + t + key + credentials.secret).digest('hex').toUpperCase());
      assert.equal(init.body.toString().includes(credentials.secret), false);
      return Response.json({code: 200, success: true, data: result});
    },
  });
  assert.equal(code.pickupCode, '001-5');
  assert.equal(code.station, '测试站');
});

test('refuses unregistered requests and does not accept codes for a different waybill', async () => {
  await assert.rejects(lookupPickupCode(input, credentials, {fetcher: mock({code: 10005, success: false})}), {code: 'not_subscribed'});
  await assert.rejects(lookupPickupCode(input, credentials, {fetcher: mock({code: 30002, success: false})}), {code: 'invalid_signature'});
  await assert.rejects(lookupPickupCode(input, credentials, {fetcher: mock({
    code: 200, success: true, data: {...result, kuaidinum: 'TEST00002'},
  })}), {code: 'waybill_mismatch'});
});
