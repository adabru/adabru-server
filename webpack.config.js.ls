
module.exports =
  # see https://webpack.js.org/configuration/devtool/
  # and https://reactjs.org/docs/cross-origin-errors.html
  devtool: 'cheap-module-source-map'
  entry: ['./dashboard_front.js']
  # module:
  #   loaders: [test: /\.css$/, loader: "style-loader!css-loader"]
  output:
    path: "#{__dirname}",
    filename: './dashboard_app.js',
    library: 'dashboard',
    libraryTarget: 'var'
