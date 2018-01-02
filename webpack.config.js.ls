
module.exports =
  entry: ['./dashboard_front.js']
  # module:
  #   loaders: [test: /\.css$/, loader: "style-loader!css-loader"]
  output:
    filename: './dashboard_fronts.js',
    library: 'dashboard',
    libraryTarget: 'var'
