const { buildUnifiedDiffModel } = require('./diff-model.cjs');

self.onmessage = ({ data }) => {
  try {
    self.postMessage({ id: data.id, result: buildUnifiedDiffModel(data.original, data.modified) });
  } catch (error) {
    self.postMessage({ id: data.id, error: error.message || String(error) });
  }
};
