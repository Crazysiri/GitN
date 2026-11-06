const path = require('path');

module.exports = (env, argv) => ({
  entry: './src/entry.js',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'app.js',
    chunkFilename: '[id].app.js',
    // Must be explicit: webpack 5 'auto' detection rejects file:// URLs,
    // throwing "Automatic publicPath is not supported in this browser".
    // WKWebView loads from file://, so all chunks resolve relative to the HTML.
    publicPath: './',
    clean: true,
  },
  module: {
    rules: [
      {
        test: /\.css$/,
        use: ['style-loader', 'css-loader'],
      },
    ],
  },
  devtool: argv.mode === 'production' ? 'source-map' : 'eval-source-map',
  performance: { hints: false },
});
