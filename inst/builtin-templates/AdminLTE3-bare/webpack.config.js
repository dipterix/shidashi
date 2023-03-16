const path = require('path');

module.exports = {
  mode: "production",
  entry: './src/index.js',
  output: {
    filename: 'shidashi.js',
    path: path.resolve(__dirname, 'www', 'shidashi', 'js'),
    libraryTarget: 'var',
    library: 'Shidashi'
  },
  devtool: 'source-map',
  externals: {
    jquery: 'jQuery',
  },
  module: {
    rules: [
      {
        test: /\.css$/i,
        use: [
          'style-loader',
          'css-loader',
        ]
      },
      {
        test: /\.scss$/i,
        use: [
          'style-loader',
          {
            loader: "css-loader",
            options: {
              importLoaders: 2,
              url: false,
              // 0 => no loaders (default);
              // 1 => postcss-loader;
              // 2 => postcss-loader, sass-loader
            },
          },
          'sass-loader'
        ],
      },
    ],
  },
};
