const path = require('path');
const MonacoWebpackPlugin = require('monaco-editor-webpack-plugin');

module.exports = (env, argv) => ({
  entry: './src/entry.js',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'app.js',
    chunkFilename: '[id].app.js',
    // Must be explicit: webpack5 'auto' detection rejects file:// URLs,
    // throwing "Automatic publicPath is not supported in this browser".
    // WKWebView loads from file://, so all chunks must resolve relative to the HTML.
    publicPath: './',
    clean: true,
  },
  module: {
    rules: [
      {
        test: /diff-worker\.js$/,
        type: 'asset/source',
      },
      {
        test: /\.css$/,
        use: ['style-loader', 'css-loader'],
      },
      {
        test: /\.ttf$/,
        type: 'asset/resource',
      },
    ],
  },
  plugins: [
    new MonacoWebpackPlugin({
      // Add or remove languages here as needed.
      // Full list: https://github.com/microsoft/monaco-editor-webpack-plugin#options
      languages: [
        'css', 'html', 'json', 'javascript', 'typescript',
        'markdown', 'shell', 'yaml', 'xml', 'python', 'rust', 'go',
      ],
      filename: '[name].worker.js',
    }),
  ],
  devtool: argv.mode === 'production' ? 'source-map' : 'eval-source-map',
  performance: { hints: false },
});
