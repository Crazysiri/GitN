const languageWorkers = {
  css: 'css.worker.js',
  scss: 'css.worker.js',
  less: 'css.worker.js',
  html: 'html.worker.js',
  handlebars: 'html.worker.js',
  razor: 'html.worker.js',
  json: 'json.worker.js',
  javascript: 'ts.worker.js',
  typescript: 'ts.worker.js',
};

function workerFileForLabel(label) {
  return languageWorkers[label] || 'editor.worker.js';
}

function installMonacoWorkerFactory(page) {
  const environment = page.MonacoEnvironment || {};
  const sourceURLs = new Map();
  const activeURLs = new Set();

  environment.getWorker = (_workerId, label) => {
    const filename = workerFileForLabel(label);
    const bridge = page.webkit?.messageHandlers?.monacoWorker;
    if (!bridge || typeof bridge.postMessage !== 'function') {
      return new page.Worker(`./${filename}`);
    }

    let urlPromise = sourceURLs.get(filename);
    if (!urlPromise) {
      urlPromise = Promise.resolve(bridge.postMessage({ filename })).then(source => {
        if (typeof source !== 'string' || !source.length) {
          throw new Error(`Empty Monaco worker resource: ${filename}`);
        }
        const url = page.URL.createObjectURL(new page.Blob([source], { type: 'text/javascript' }));
        activeURLs.add(url);
        return url;
      });
      sourceURLs.set(filename, urlPromise);
      urlPromise.catch(() => {
        if (sourceURLs.get(filename) === urlPromise) sourceURLs.delete(filename);
      });
    }
    return urlPromise.then(url => new page.Worker(url));
  };

  page.MonacoEnvironment = environment;
  page.addEventListener('pagehide', () => {
    for (const url of activeURLs) page.URL.revokeObjectURL(url);
    activeURLs.clear();
    sourceURLs.clear();
  });
  return environment.getWorker;
}

module.exports = { workerFileForLabel, installMonacoWorkerFactory };
