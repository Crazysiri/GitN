'use strict';

// Pure, browser-free bridge logic so it can be unit-tested with `node --test`.
// The DOM/xterm wiring lives in entry.js and calls into these helpers.

/**
 * Decode a base64 payload (shell bytes from the native side) into a Uint8Array.
 * We never interpolate shell output into JS source; bytes always travel as base64.
 */
function decodeBase64ToBytes(base64, deps) {
  const atob = deps.atob;
  const binary = atob(base64);
  const length = binary.length;
  const bytes = new deps.Uint8Array(length);
  for (let i = 0; i < length; i += 1) {
    bytes[i] = binary.charCodeAt(i) & 0xff;
  }
  return bytes;
}

/**
 * Encode a Uint8Array (user input / UTF-8 bytes) into base64 for the native side.
 */
function encodeBytesToBase64(bytes, deps) {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += deps.String.fromCharCode(bytes[i]);
  }
  return deps.btoa(binary);
}

/**
 * Clamp PTY dimensions to safe positive integers. A 0x0 or negative size must
 * never reach TIOCSWINSZ, and fractional values from fit() must be floored.
 */
function sanitizeSize(cols, rows) {
  const c = Math.floor(Number(cols));
  const r = Math.floor(Number(rows));
  return {
    cols: Number.isFinite(c) && c > 0 ? c : 1,
    rows: Number.isFinite(r) && r > 0 ? r : 1,
  };
}

/**
 * Post a structured event to the native side through a WebKit message handler.
 * No-ops safely when the handler is absent (e.g. a plain browser dev page).
 */
function postEvent(handler, event, payload) {
  if (!handler || typeof handler.postMessage !== 'function') return false;
  handler.postMessage(Object.assign({ event }, payload || {}));
  return true;
}

module.exports = {
  decodeBase64ToBytes,
  encodeBytesToBase64,
  sanitizeSize,
  postEvent,
};
