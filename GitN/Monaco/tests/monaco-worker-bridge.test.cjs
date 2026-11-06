const test = require('node:test');
const assert = require('node:assert/strict');
const { workerFileForLabel, installMonacoWorkerFactory } = require('../src/monaco-worker-bridge.cjs');

function fakePage(postMessage) {
  const listeners = new Map();
  const created = [];
  const revoked = [];
  let nextURL = 0;
  const page = {
    MonacoEnvironment: { getWorkerUrl: () => './broken-file-worker.js' },
    webkit: { messageHandlers: { monacoWorker: { postMessage } } },
    Blob: class { constructor(parts) { this.parts = parts; } },
    Worker: class { constructor(url) { this.url = url; created.push(this); } },
    URL: {
      createObjectURL: () => `blob:worker-${++nextURL}`,
      revokeObjectURL: url => revoked.push(url),
    },
    addEventListener: (name, listener) => listeners.set(name, listener),
  };
  return { page, created, revoked, listeners };
}

test('routes Monaco language labels to allowlisted worker files', () => {
  assert.equal(workerFileForLabel('json'), 'json.worker.js');
  assert.equal(workerFileForLabel('scss'), 'css.worker.js');
  assert.equal(workerFileForLabel('handlebars'), 'html.worker.js');
  assert.equal(workerFileForLabel('typescript'), 'ts.worker.js');
  assert.equal(workerFileForLabel('editorWorkerService'), 'editor.worker.js');
});

test('loads native source once per type and revokes blob URLs on pagehide', async () => {
  const requests = [];
  const fixture = fakePage(({ filename }) => { requests.push(filename); return Promise.resolve('self.onmessage = () => {}'); });
  const getWorker = installMonacoWorkerFactory(fixture.page);
  const [first, second] = await Promise.all([getWorker('a', 'json'), getWorker('b', 'json')]);
  assert.deepEqual(requests, ['json.worker.js']);
  assert.equal(first.url, second.url);
  assert.equal(fixture.created.length, 2);
  fixture.listeners.get('pagehide')();
  assert.deepEqual(fixture.revoked, [first.url]);
});

test('failed native load can be retried', async () => {
  let attempts = 0;
  const fixture = fakePage(() => ++attempts === 1 ? Promise.reject(new Error('missing')) : 'worker source');
  const getWorker = installMonacoWorkerFactory(fixture.page);
  await assert.rejects(getWorker('a', 'json'), /missing/);
  const worker = await getWorker('b', 'json');
  assert.equal(worker.url, 'blob:worker-1');
  assert.equal(attempts, 2);
});
