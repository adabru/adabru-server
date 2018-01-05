
module.exports =
  entry: ['./dashboard_front.js']
  # module:
  #   loaders: [test: /\.css$/, loader: "style-loader!css-loader"]
  output:
    filename: './dashboard_app.js',
    library: 'dashboard',
    libraryTarget: 'var'
