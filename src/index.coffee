# Pass in local Gulp and options object

module.exports = (gulp, options) ->
  
  # Load all 'gulp-' plugins from package.json
  plugins = (require 'gulp-load-plugins')()
  # This can be removed after Gulp 4 is released
  runSequence = (require 'run-sequence').use(gulp)

  # Server + browser with live refresh / injection
  browserSync = require 'browser-sync'
  reload = browserSync.reload

  # Bower and Browserify
  bowerFiles = require 'main-bower-files'
  exists = (require 'fs').existsSync
  browserify = require 'browserify'
  through = (require 'through2').obj

  # Deployment via rsync ssh
  rsync = (require 'rsyncwrapper').rsync

  # Stylus libraries
  axis = require 'axis'
  rupture = require 'rupture'
  grid = require 'happy-grid'
  downbeat = require 'downbeat'
  lib = require 'stylus-lightning'

  # Date parsing
  moment = require 'moment'

  del = require 'del'
  jade = require 'jade'
  _ = require 'lodash'
  typography = require 'typogr'
  {dirname} = require 'path'
  yaml = require 'yamljs'

  # Enable markdown blocks in Jade
  marked = require 'marked'
  # Use proper quotes and apostrophes
  marked.setOptions
    smartypants: true
    breaks: true
  stylus = require 'stylus'
  jade.filters.stylus = stylus.render

  # My module to create site.json, a map of structured data for the site
  # Pages in Collections are sorted by date
  map = require './map'

  # Asset Paths
  config =
    server: ''
    source: 'source'
    development: 'development'
    production: 'production'
    assets:
      styles: 'source/styles'
      scripts: 'source/scripts'
      content: 'source/content'
      templates: 'source/templates'
      images: 'source/images'
      fonts: 'source/fonts'
      email: 'source/email'

  # Extend/overwrite the config defaults with options object passed in
  # TODO: Fix / Implement this
  # _.extend config, options

  # Build site's structured data map
  gulp.task 'map', (done) ->
    map config, done

  # Compile Jade source
  gulp.task 'jade', ->
    site = require "#{process.cwd()}/site.json"
    gulp.src ["#{config.assets.content}/**/*.jade", "!#{config.assets.content}/_includes/**/*"]
    .pipe plugins.plumber()
    # Add the file's front-matter to the file.data object
    .pipe plugins.frontMatter
      property: 'data'
    # Transform and extend the file.data object
    .pipe plugins.data (file) ->
      date = new Date(file.data.date)
      if file.data.date
        file.data.datetime = moment(date).format()
        file.data.date = moment(date).format('MMMM Do, YYYY')
      file.data.url = (file.path.slice (file.path.indexOf config.assets.content) + config.assets.content.length)
      .replace /\/?(index)?(\.jade$|\.md$|\.html$)/, '/'
      file.data.collection =  dirname file.data.url
      # Smartypants the meta (quotes, en/em dashes, apostrophes, ellipsis)
      for meta in ['title', 'description', 'og_title', 'og_description', 'twitter_title', 'twitter_description']
        if file.data[meta]
          file.data[meta] = typography(file.data[meta]).chain().smartypants().value()
      # Include lodash for Jade templates
      file.data._ = require 'lodash'
      data = _.extend {}, site, file.data
    .pipe plugins.jade
      pretty: true
    # Rename all files to filename/index.html
    .pipe plugins.prettyUrl()
    .pipe gulp.dest config.development

  # Compile Markdown source through Jade layout
  # TODO: DRY, some duplication of Jade task
  gulp.task 'markdown', ->
    site = require "#{process.cwd()}/site.json"
    gulp.src ["#{config.assets.content}/**/*.md", "!#{config.assets.content}/_includes/**/*"]
    .pipe plugins.plumber()
    .pipe plugins.frontMatter
      property: 'data'
    .pipe plugins.markdown
      smartypants: true
      breaks: true
    .pipe plugins.data (file) ->
      date = new Date(file.data.date)
      if file.data.date
        file.data.datetime = moment(date).format()
        file.data.date = moment(date).format('MMMM Do, YYYY')
      file.data.layout = "#{config.assets.templates}/#{file.data.layout}.jade"
      # Set Jade pretty html option
      file.data.pretty = true
      file.data.url = (file.path.slice (file.path.indexOf config.assets.content) + config.assets.content.length)
      .replace /\/?(index)?(\.jade$|\.md$|\.html$)/, '/'
      file.data.collection = (dirname file.data.url) + '/'
      for meta in ['title', 'description', 'og_title', 'og_description', 'twitter_title', 'twitter_description']
        if file.data[meta]
          file.data[meta] = typography(file.data[meta]).chain().smartypants().value()
      file.data._ = require 'lodash'
      file.data.typography = (require 'typogr').typogrify
      data = _.extend {}, site, file.data
    .pipe plugins.layout (file) ->
      file.data
    .pipe plugins.prettyUrl()
    .pipe gulp.dest config.development

  # Compile stylus to css with sourcemaps
  gulp.task 'stylus', ->
    gulp.src "#{config.assets.styles}/main.styl"
    .pipe plugins.plumber()
    .pipe plugins.sourcemaps.init()
    .pipe plugins.stylus
      use: [
        rupture
          implicit: false
        axis
          implicit: false
        lib()
        grid()
        downbeat()
      ]
    .pipe plugins.autoprefixer
      browsers: [
        '> 1%'
        'last 2 versions'
        'Firefox ESR'
        'Opera 12.1'
        'Explorer >= 9'
      ]
    .pipe plugins.sourcemaps.write()
    .pipe gulp.dest config.development
    .pipe reload stream: true

  # Compile coffeescript to js with sourcemaps
  gulp.task 'coffee', ->
    gulp.src "#{config.assets.scripts}/**/*.coffee"
    .pipe plugins.plumber()
    .pipe plugins.sourcemaps.init()
    .pipe plugins.coffee()
    # show coffeescript errors in the console
    .on 'error', plugins.util.log
    .pipe plugins.sourcemaps.write()
    .pipe gulp.dest config.development

  # Use browserify to compile any require statments
  gulp.task 'js', ['coffee', 'bower'], ->
    gulp.src "#{config.development}/main.js"
    .pipe plugins.plumber()
    .pipe through (file, enc, next) ->
      (browserify file.path).bundle (err, res) ->
        file.contents = res
        next null, file
    .pipe gulp.dest config.development

  # Install Bower dependencies and move to development lib folder
  # To use a library add it to build blocks in base.jade
  gulp.task 'installBower', ->
    gulp.src 'bower.json'
    .pipe plugins.install()

  gulp.task 'bower', ['installBower'], ->
    if exists './bower_components'
      gulp.src bowerFiles()
      .pipe gulp.dest "#{config.development}/lib"

  # Compile source files for development
  gulp.task 'compile', [
    'js'
    'jade'
    'markdown'
    'stylus'
  ]

  # Convert production files into development files
  # concat, minify, optimize
  gulp.task 'optimize', ->
    # parse the html files for build blocks
    # return the concatenated file for each block
    assets = plugins.useref.assets searchPath: config.development
    gulp.src "#{config.development}/**/*.html"
    .pipe assets
    # minify css and js
    .pipe plugins.if '*.css', plugins.csso()
    .pipe plugins.if '*.js', plugins.uglify()
    .pipe gulp.dest config.production
    # bring back just the html files
    .pipe assets.restore()
    # remove/replace the build blocks
    .pipe plugins.useref()
    # minify the html
    .pipe plugins.if '*.html', plugins.minifyHtml()
    .pipe gulp.dest config.production

  # cache bust asset file names
  bust = new plugins.cachebust()
  gulp.task 'cacheresources', ->
    gulp.src "#{config.production}/**/*.css"
    .pipe bust.resources()
    .pipe gulp.dest config.production

    gulp.src "#{config.production}/**/*.js"
    .pipe bust.resources()
    .pipe gulp.dest config.production

  # replace references to new cachebusted file names
  gulp.task 'cacheref', ['cacheresources'], ->
    gulp.src "#{config.production}/**/*.html"
    .pipe bust.references()
    .pipe gulp.dest config.production

  # cleanup cachebust assets
  gulp.task 'cachebust', ['cacheref'], (done) ->
    del [
      "#{config.production}/script.min.js"
      "#{config.production}/style.min.css"
      ], done()

  # Optimize and move images
  gulp.task 'images', ->
    gulp.src "#{config.assets.images}/*"
    .pipe plugins.plumber()
    .pipe plugins.cache plugins.imagemin
      progressive: true
      interlaced: true
    .pipe gulp.dest "#{config.production}/images"

  # Move other files for production
  gulp.task 'move', ->
    gulp.src [
      "#{config.assets.fonts}/**/*"
      "#{config.source}/robots.txt"
      "#{config.source}/.redirects.conf"
      "!#{config.source}/**/.keep"
    ], dot: true
    .pipe gulp.dest config.production

  # Clear Gulp cache
  gulp.task 'clear', (done) ->
    plugins.cache.clearAll done

  # Delete development and production build folders
  gulp.task 'clean', ['clear'], (done) ->
    del [
      config.development
      config.production
      "#{config.assets.email}/build"
      './bower_components'
      'site.json'
    ], done()

  # Open a web browser and watch for changes
  gulp.task 'browser', ->
    browserSync.init
      notify: false
      server:
        baseDir: [config.development, config.source]

    # Watch for changes
    gulp.watch "{#{config.assets.content},#{config.assets.templates}}/**/*", ['jade', 'markdown', reload]
    gulp.watch "#{config.assets.styles}/**/*", ['stylus']
    gulp.watch "#{config.assets.scripts}/**/*", ['js', reload]
    gulp.watch "#{config.assets.images}/**/*", reload

  # Open a web browser to test final production build
  gulp.task 'previewBrowser', ->
    browserSync
      server:
        baseDir: config.production

  # rsync the build directory to your server
  gulp.task 'rsync', (done) ->
    rsync
      ssh: true
      src: "#{config.production}/"
      dest: options.server
      recursive: true
      syncDest: true
      args: ['--verbose']
    , (erro, stdout, stderr, cmd) ->
      plugins.util.log(stdout)
      done()

  # Email Tasks
  gulp.task 'email:jade', ['map'], ->
    site = require "#{process.cwd()}/site.json"
    gulp.src "#{config.assets.email}/templates/*.jade"
    .pipe plugins.plumber()
    .pipe plugins.jade
      jade: jade
      pretty: true
      locals: site
    .pipe plugins.inlineCss
      preserveMediaQueries: true
      applyLinkTags: false
      removeLinkTags: false
    .pipe gulp.dest "#{config.assets.email}/build"

  gulp.task 'email:text', ['email:jade'], ->
    gulp.src "#{config.assets.email}/build/*.html"
    .pipe plugins.html2txt()
    .pipe gulp.dest "#{config.assets.email}/build"

  gulp.task 'email:images', ->
    gulp.src "#{config.assets.email}/images/*"
    .pipe gulp.dest "#{config.assets.email}/build/images"

  gulp.task 'email:browser', ->
    browserSync.init
      notify: false
      server:
        baseDir: "#{config.assets.email}/build"

    # Watch for changes
    gulp.watch ["#{config.assets.email}/styles/**/*", "#{config.assets.email}/templates/**/*"], ['email:reload']
    gulp.watch "#{config.assets.email}/images/*", reload

  gulp.task 'email:reload', ['email:text'], ->
    reload()

  gulp.task 'email', [
    'email:text'
    'email:images'
    'email:browser'
  ]

  #################
  # Main Gulp Tasks
  #################
  # Develop (the defualt task)
  gulp.task 'develop', (done) ->
    runSequence 'map', 'compile', 'browser', done

  gulp.task 'default', ['develop']

  # Build full site ready for production
  gulp.task 'build', (done) ->
    runSequence 'clean', 'map', 'compile', ['optimize', 'move', 'images'], 'cachebust', done

  # Preview server for production
  gulp.task 'preview', (done) ->
    runSequence 'build', 'previewBrowser', done

  # Deploy production site
  gulp.task 'deploy', ['build'], (done) ->
    runSequence 'rsync', done
