'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  decodeBase64ToBytes,
  encodeBytesToBase64,
  sanitizeSize,
  postEvent,
} = require('../src/bridge.cjs');

const deps = {
  atob: (value) => Buffer.from(value, 'base64').toString('binary'),
  btoa: (value) => Buffer.from(value, 'binary').toString('base64'),
  String,
  Uint8Array,
};

test('base64 round-trip preserves raw bytes including high bytes', () => {
  const original = Uint8Array.from([0x00, 0x1b, 0x5b, 0x41, 0xe4, 0xbd, 0xa0, 0xff]);
  const encoded = encodeBytesToBase64(original, deps);
  const decoded = decodeBase64ToBytes(encoded, deps);
  assert.deepEqual(Array.from(decoded), Array.from(original));
});

test('decode handles multi-byte UTF-8 (Chinese) intact', () => {
  const utf8 = Buffer.from('你好', 'utf8');
  const encoded = utf8.toString('base64');
  const decoded = decodeBase64ToBytes(encoded, deps);
  assert.equal(Buffer.from(decoded).toString('utf8'), '你好');
});

test('sanitizeSize floors fractional dimensions and rejects non-positive', () => {
  assert.deepEqual(sanitizeSize(80.7, 24.9), { cols: 80, rows: 24 });
  assert.deepEqual(sanitizeSize(0, 0), { cols: 1, rows: 1 });
  assert.deepEqual(sanitizeSize(-5, 10), { cols: 1, rows: 10 });
  assert.deepEqual(sanitizeSize(NaN, 24), { cols: 1, rows: 24 });
});

test('postEvent no-ops safely without a handler', () => {
  assert.equal(postEvent(undefined, 'input', { bytes: 'AA==' }), false);
  assert.equal(postEvent({}, 'input', {}), false);
});

test('postEvent forwards the event name merged with the payload', () => {
  const sent = [];
  const handler = { postMessage: (msg) => sent.push(msg) };
  assert.equal(postEvent(handler, 'resize', { cols: 80, rows: 24 }), true);
  assert.deepEqual(sent, [{ event: 'resize', cols: 80, rows: 24 }]);
});
