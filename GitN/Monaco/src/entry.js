import * as monaco from 'monaco-editor';
const { DiffScheduler } = require('./diff-scheduler.cjs');
const { installMonacoWorkerFactory } = require('./monaco-worker-bridge.cjs');
import diffWorkerSource from '../.worker-build/diff-worker.js';

// Expose globals consumed by host.js
window.monaco = monaco;
window.gitnHunkLayout = require('./hunk-layout.cjs');
installMonacoWorkerFactory(window);
// WKWebView loads index.html from file://, which cannot launch a file:// Worker.
// Bundle the small diff worker as source and launch it from a same-page blob URL.
const diffWorkerURL = URL.createObjectURL(new Blob([diffWorkerSource], { type: 'text/javascript' }));
window.gitnDiffScheduler = new DiffScheduler(
  () => new Worker(diffWorkerURL)
);
window.addEventListener('pagehide', () => {
  window.gitnDiffScheduler.dispose();
  URL.revokeObjectURL(diffWorkerURL);
});
