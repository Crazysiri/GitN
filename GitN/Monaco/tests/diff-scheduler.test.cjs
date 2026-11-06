const test = require('node:test');
const assert = require('node:assert/strict');
const { DiffScheduler } = require('../src/diff-scheduler.cjs');

class FakeWorker {
  constructor() { this.terminated = false; this.messages = []; }
  postMessage(message) { this.messages.push(message); }
  terminate() { this.terminated = true; }
  reply(result) { this.onmessage({ data: { id: this.messages.at(-1).id, result } }); }
}

test('cancels superseded work and ignores its late result', async () => {
  const workers = [];
  const scheduler = new DiffScheduler(() => {
    const worker = new FakeWorker();
    workers.push(worker);
    return worker;
  });
  const first = scheduler.run('old', 'first');
  const second = scheduler.run('old', 'second');
  assert.equal(workers[0].terminated, true);
  workers[0].reply({ stale: true });
  workers[1].reply({ latest: true });
  assert.equal(await first, null);
  assert.deepEqual(await second, { latest: true });
  scheduler.dispose();
});

test('worker failures and deadlines reject, then allow a new request', async () => {
  const workers = [];
  const scheduler = new DiffScheduler(() => {
    const worker = new FakeWorker();
    workers.push(worker);
    return worker;
  }, 10);
  const first = scheduler.run('a', 'b');
  workers[0].onerror();
  await assert.rejects(first, /could not load/);
  const second = scheduler.run('a', 'c');
  await assert.rejects(second, /timed out/);
  assert.equal(workers[1].terminated, true);
  const third = scheduler.run('a', 'd');
  workers[2].reply({ ok: true });
  assert.deepEqual(await third, { ok: true });
  scheduler.dispose();
});
