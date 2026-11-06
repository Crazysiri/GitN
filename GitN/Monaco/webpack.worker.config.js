const path = require('path');

module.exports = {
  mode: 'production',
  target: 'webworker',
  entry: './src/diff-worker.js',
  output: {
    path: path.resolve(__dirname, '.worker-build'),
    filename: 'diff-worker.js',
    clean: true,
    globalObject: 'self',
  },
  devtool: false,
  performance: { hints: false },
};
