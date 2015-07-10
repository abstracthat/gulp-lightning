# Pass in local Gulp and options object

module.exports = (gulp, options) ->
  
  # Load all 'gulp-' plugins from package.json
  plugins = (require 'gulp-load-plugins')()
  lazypipe = require 'lazypipe'
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

  fs = require 'fs'
  path = require 'path'
  del = require 'del'
  jade = require 'jade'
  _ = require 'lodash'
  typography = require 'typogr'
  {dirname} = require 'path'
  yaml = require 'yamljs'
  glob = require 'globby'
  request = require 'request'
  toText = (require 'html-to-text').fromString

  # Enable markdown blocks in Jade
  marked = require 'marked'
  # Use proper quotes and apostrophes
  marked.setOptions
    smartypants: true
    breaks: true

  # Creates site.json, a map of structured data for the site's files
  map = require './map'

  # Creates email.json, a map of email files
  emailMap = require './email-map'

  # Asset Paths
  config =
    server: ''
    site:
      source: 'site'
      development: 'site/.development'
      production: 'site/.production'
      styles: 'site/styles'
      scripts: 'site/scripts'
      content: 'site/content'
      templates: 'site/templates'
      images: 'site/images'
      fonts: 'site/fonts'
      root: 'site/root'
    email:
      source: 'email'
      build: 'email/.build'
      content: 'email/content'
      campaigns: 'email/content/campaigns'
      autoresponders: 'email/content/autoresponders'
      rss: 'email/content/rss'
      splitTests: 'email/content/split-tests'
      images: 'email/images'
      styles: 'email/styles'
      templates: 'email/templates'

  # Extend/overwrite the config defaults with options object passed in
  config = _.merge config, options

  # Build site's structured data map
  gulp.task 'map', (done) ->
    map config, done

  # Compile Jade source
  gulp.task 'jade', ->
    gulp.src ["#{config.site.content}/**/*.{jade,md}", "!#{config.site.content}/_includes/**/*"]
    .pipe plugins.plumber()
    # Add the file's front-matter to the file.data object
    .pipe plugins.frontMatter
      property: 'data'
    # Transform and extend the file.data object
    .pipe getSiteData()
    # Compile Jade
    .pipe plugins.if '*.jade', plugins.jade
      pretty: true
    # Compile Markdown source through Jade layout
    .pipe plugins.if '*.md', markdownTemplate()
    # Rename all files to filename/index.html
    .pipe plugins.prettyUrl()
    .pipe gulp.dest config.site.development

  getSiteData = lazypipe()
  .pipe plugins.data, (file) ->
    site = require "#{process.cwd()}/#{config.site.source}/site.json"

    # get the url and collection (directory) paths
    file.data.url = (file.path.slice (file.path.indexOf config.site.content) + config.site.content.length)
    .replace /((\/)index)?(\.jade$|.\md$)/, '/'
    file.data.collection = (dirname file.data.url) + '/'

    # if there is a yml file that matches the slug update the content meta
    if file.data.url is '/'
      metaDataFile = "./#{config.site.content}#{file.data.collection}index.yml"
    else
      metaDataFile = "./#{config.site.content}#{file.data.url.slice(0, -1)}.yml"
    if exists metaDataFile
      file.data = _.merge (yaml.load metaDataFile), file.data

    # clean up the date
    date = new Date(file.data.date)
    if file.data.date
      file.data.datetime = moment(date).format()
      file.data.date = moment(date).format('MMMM Do, YYYY')

    # prepare markdown files for running through jade template layout
    if (path.extname file.path) is '.md'
      # if there is no layout defined use 'post'
      file.data.layout = 'post' unless file.data.layout
      # add the full path to the jade template
      file.data.layout = "#{config.site.templates}/#{file.data.layout}.jade"
      # set the jade pretty setting
      file.data.pretty = true

    # Typography / smartypants the meta
    for meta in ['title', 'description', 'og_title', 'og_description', 'twitter_title', 'twitter_description']
      if file.data[meta]
        file.data[meta] = typography(file.data[meta]).chain().smartypants().value()

    # Attach some libaries to use in jade templates
    file.data._ = require 'lodash'
    file.data.typography = (require 'typogr').typogrify
    data = _.extend {}, site, file.data

  markdownTemplate = lazypipe()
  .pipe plugins.markdown
  .pipe plugins.layout, (file) ->
    file.data

  # Atom and RSS XML Feeds
  gulp.task 'feed', ->
    site = require "#{process.cwd()}/#{config.site.source}/site.json"
    gulp.src "#{process.cwd()}/node_modules/gulp-lightning/templates/{atom,rss}.jade"
    .pipe plugins.jade
      locals: site
      jade: jade
    .pipe plugins.rename 
      dirname: ''
      extname: '.xml'
    .pipe gulp.dest config.site.development

  # Compile stylus to css with sourcemaps
  gulp.task 'stylus', ->
    gulp.src "#{config.site.styles}/main.styl"
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
    .pipe gulp.dest config.site.development
    .pipe reload stream: true

  # Compile coffeescript to js with sourcemaps
  gulp.task 'coffee', ->
    gulp.src "#{config.site.scripts}/**/*.coffee"
    .pipe plugins.plumber()
    .pipe plugins.sourcemaps.init()
    .pipe plugins.coffee()
    # show coffeescript errors in the console
    .on 'error', plugins.util.log
    .pipe plugins.sourcemaps.write()
    .pipe gulp.dest config.site.development

  # Use browserify to compile any require statments
  gulp.task 'js', ['coffee', 'bower'], ->
    gulp.src "#{config.site.development}/main.js"
    .pipe plugins.plumber()
    .pipe through (file, enc, next) ->
      (browserify file.path).bundle (err, res) ->
        file.contents = res
        next null, file
    .pipe gulp.dest config.site.development

  # Install Bower dependencies and move to development lib folder
  # To use a library add it to build blocks in base.jade
  gulp.task 'installBower', ->
    gulp.src 'bower.json'
    .pipe plugins.install()

  gulp.task 'bower', ['installBower'], ->
    if exists './bower_components'
      gulp.src bowerFiles()
      .pipe gulp.dest "#{config.site.development}/lib"

  # Compile source files for development
  gulp.task 'compile', [
    'js'
    'jade'
    'feed'
    'stylus'
  ]

  # Convert production files into development files
  # concat, minify, optimize
  gulp.task 'optimize', ->
    # parse the html files for build blocks
    # return the concatenated file for each block
    assets = plugins.useref.assets searchPath: config.site.development
    gulp.src "#{config.site.development}/**/*.html"
    .pipe assets
    # minify css and js
    .pipe plugins.if '*.css', plugins.csso()
    .pipe plugins.if '*.js', plugins.uglify()
    .pipe gulp.dest config.site.production
    # bring back just the html files
    .pipe assets.restore()
    # remove/replace the build blocks
    .pipe plugins.useref()
    # minify the html
    .pipe plugins.if '*.html', plugins.minifyHtml()
    .pipe gulp.dest config.site.production

  # cache bust asset file names
  bust = new plugins.cachebust()
  gulp.task 'cacheresources', ->
    gulp.src "#{config.site.production}/**/*.css"
    .pipe bust.resources()
    .pipe gulp.dest config.site.production

    gulp.src "#{config.site.production}/**/*.js"
    .pipe bust.resources()
    .pipe gulp.dest config.site.production

  # replace references to new cachebusted file names
  gulp.task 'cacheref', ['cacheresources'], ->
    gulp.src "#{config.site.production}/**/*.html"
    .pipe bust.references()
    .pipe gulp.dest config.site.production

  # cleanup cachebust assets
  gulp.task 'cachebust', ['cacheref'], (done) ->
    del [
      "#{config.site.production}/script.min.js"
      "#{config.site.production}/style.min.css"
      ], done()

  # Optimize and move images
  gulp.task 'images', ->
    gulp.src "#{config.site.images}/*"
    .pipe plugins.plumber()
    .pipe plugins.cache plugins.imagemin
      progressive: true
      interlaced: true
    .pipe gulp.dest "#{config.site.production}/images"

  # Move other files for production
  gulp.task 'move', ->
    gulp.src [
      "#{config.site.fonts}/**/*"
      "#{config.site.development}/*.xml"
      "#{config.site.root}/**/*"
      "!#{config.site.source}/**/.keep"
    ], dot: true
    .pipe gulp.dest config.site.production

  # Clear Gulp cache
  gulp.task 'clear', (done) ->
    plugins.cache.clearAll done

  # Delete development and production build folders
  gulp.task 'clean', ['clear'], (done) ->
    del [
      config.site.development
      config.site.production
      "#{config.site.source}/site.json"
      config.email.build
      "#{config.email.source}/email.json"
    ], done()

  # Open a web browser and watch for changes
  gulp.task 'browser', ->
    browserSync.init
      notify: false
      server:
        baseDir: [config.site.development, config.site.source]

    # Watch for changes
    gulp.watch "{#{config.site.content},#{config.site.templates}}/**/*", ['jade', reload]
    gulp.watch "#{config.site.styles}/**/*", ['stylus']
    gulp.watch "#{config.site.scripts}/**/*", ['js', reload]
    gulp.watch "#{config.site.images}/**/*", reload

  # Open a web browser to test final production build
  gulp.task 'previewBrowser', ->
    browserSync
      server:
        baseDir: config.site.production

  # rsync the build directory to your server
  gulp.task 'rsync', (done) ->
    rsync
      ssh: true
      src: "#{config.site.production}/"
      dest: config.server
      recursive: true
      delete: true
      exclude: ['images/email']
      args: ['--verbose']
    , (erro, stdout, stderr, cmd) ->
      plugins.util.log(stdout)
      done()

  # Email Tasks
  gulp.task 'email:map', (done) ->
    emailMap config, done

  gulp.task 'email:stylus', ->
    gulp.src "#{config.email.styles}/main.styl"
    .pipe plugins.stylus()
    .pipe gulp.dest config.email.build

  getEmailData = lazypipe()
  .pipe plugins.data, (file) ->

    # Load the config and each default metadata
    site = yaml.load "./#{config.site.source}/site.yml"
    email = require "#{process.cwd()}/#{config.email.source}/email.json"
    locals = _.extend email, site
    defaultEmailData =
      autoresponders: yaml.load "./#{config.email.autoresponders}/_default.yml"
      campaigns: yaml.load "./#{config.email.campaigns}/_default.yml"
      rss: yaml.load "./#{config.email.rss}/_default.yml"
      splitTest: yaml.load "./#{config.email.splitTests}/_default.yml"

    # Create data object to hold our data after we prepare it
    file.data = {}
    file.mailChimp =
      type: ''
      options: {}
      type_opts: {}
      content:
        html: ''
        text: ''

    # the slug is just the file name without the extension
    slug = path.basename file.path, (path.extname file.path)

    # is this file in the campaigns or autoresponders directory?
    dir = path.dirname file.path
    isCampaign = dir.match config.email.campaigns
    isAutoresponder = dir.match config.email.autoresponders
    isRSS = dir.match config.email.rss
    isSplitTest = dir.match config.email.splitTests

    if isCampaign
      file.data.collection = 'campaigns'
      # add in the default metadata based on collection's _default.yml
      file.mailChimp = _.merge file.mailChimp, defaultEmailData.campaigns

    if isAutoresponder
      # if it's an autoresponder what folder is it in?
      file.data.directory = dir.slice (dir.lastIndexOf '/') + 1
      file.data.collection = "autoresponders/#{file.data.directory}"
      # add in the default metadata based on collection's _default.yml
      file.mailChimp = _.merge file.mailChimp, defaultEmailData.autoresponders

    if isRSS
      file.data.collection = 'rss'
      # add in the default metadata based on collection's _default.yml
      file.mailChimp = _.merge file.mailChimp, defaultEmailData.rss
      file.mailChimp.type_opts.rss.url = "#{locals.site.url}/rss.xml"

    if isSplitTest
      file.data.collection = 'split-tests'
      # add in the default metadata based on collection's _default.yml
      file.mailChimp = _.merge file.mailChimp, defaultEmailData.splitTest
      # add in the subject_a/b from frontmatter if present
      if file.attributes.subject_a
        file.mailChimp.type_opts.absplit.subject_a = file.attributes.subject_a
      if file.attributes.subject_b
        file.mailChimp.type_opts.absplit.subject_b = file.attributes.subject_b

    # if there is a yml file that matches the slug update the content meta
    metaDataFile = "./#{config.email.content}/#{file.data.collection}/#{slug}.yml"
    if exists metaDataFile
      file.mailChimp = _.merge file.mailChimp, yaml.load metaDataFile

    # if it's not set yet, set the folder id from email.yml based the collection
    unless file.mailChimp.options.folder_id
      if file.data.collection.match 'autoresponders'
        file.mailChimp.options.folder_id = locals.folders.autoresponders
      else
        file.mailChimp.options.folder_id = locals.folders.campaigns

    # build options object for Mailchimp API
    file.mailChimp.options.title = "#{file.data.collection}/#{slug}"
    if file.mailChimp.subject
      file.mailChimp.options.subject = file.mailChimp.subject
    if file.attributes.subject
      file.mailChimp.options.subject = file.attributes.subject
    console.error 'You need to add an email address to site.yml' unless locals.author.email
    file.mailChimp.options.from_email = locals.author.email
    file.mailChimp.options.from_name = locals.site.name

    # The list_id is passed in email.yml
    # use default key unless in file's frontmatter
    file.attributes.list ?= 'default'
    file.mailChimp.options.list_id = locals.lists[file.attributes.list]
    delete file.attributes.list

    file.data.layout ?= file.mailChimp.layout
    # move front-matter attributes into file.data for Jade to use
    for key, value of file.attributes
      file.data[key] = value

    if (path.extname file.path) is '.md'
      file.data.layout = "#{config.email.templates}/#{file.data.layout}.jade"
      # Set Jade pretty html option
      file.data.pretty = true

    data = _.extend locals, file.data

  gulp.task 'email:index', ['email:stylus', 'email:map'], ->
    gulp.src ["#{config.email.templates}/index.jade"]
    .pipe plugins.plumber()
    .pipe plugins.jade
      pretty: true
      locals: require "#{process.cwd()}/#{config.email.source}/email.json"
    .pipe gulp.dest config.email.build
  
  gulp.task 'email:compile', ['email:index'], ->
    site = yaml.load "./#{config.site.source}/site.yml"
    gulp.src ["#{config.email.content}/**/*.{jade,md}", "#{config.email.content}/_includes/**/*"]
    .pipe plugins.plumber()
    .pipe plugins.frontMatter
      property: 'attributes'
    .pipe getEmailData()
    .pipe plugins.if '*.jade', plugins.jade
      pretty: true
    .pipe plugins.if '*.md', markdownTemplate()
    .pipe gulp.dest config.email.build
    .pipe plugins.assetpaths
      newDomain: site.site.url.replace /http(s)?:/, ''
      oldDomain: site.site.url.replace /http(s)?:/, ''
      docRoot: '/'
      filetypes: ['jpg','jpeg','png','ico','gif']
    .pipe gulp.dest "#{config.email.build}/tmp"
    .pipe plugins.data (file) ->
      file.mailChimp.content.html = fs.readFileSync "./#{config.email.build}/tmp/#{file.mailChimp.options.title}.html", 'utf-8'
      file.mailChimp.content.text = toText file.mailChimp.content.html
      # save json file keyed to filename in the collection's directory
      fs.writeFileSync "./#{config.email.build}/#{file.mailChimp.options.title}.json", JSON.stringify file.mailChimp

  gulp.task 'email:paths', ->
    site = yaml.load "./#{config.site.source}/site.yml"
    gulp.src "#{config.email.build}/**/*.html"
    .pipe plugins.assetpaths
      newDomain: site.site.url.replace /http(s)?:/, ''
      oldDomain: site.site.url.replace /http(s)?:/, ''
      docRoot: '/'
      filetypes: ['jpg','jpeg','png','ico','gif']
    .pipe gulp.dest config.email.build

  gulp.task 'email:inline', ['email:compile'], ->
    gulp.src "#{config.email.build}/**/*.html"
    .pipe plugins.inlineSource()
    .pipe plugins.inlineCss
      preserveMediaQueries: true
      applyLinkTags: false
      removeLinkTags: false
    .pipe gulp.dest config.email.build

  gulp.task 'email:images', ->
    gulp.src "#{config.email.images}/*"
    .pipe plugins.plumber()
    .pipe plugins.cache plugins.imagemin
      progressive: true
      interlaced: true
    .pipe gulp.dest "#{config.email.build}/images"

  gulp.task 'email:deploy', (done) ->
    rsync
      ssh: true
      src: "#{config.email.build}/images/"
      delete: true
      dest: "#{config.server}/images/email"
      recursive: true
      args: ['--verbose']
    , (erro, stdout, stderr, cmd) ->
      plugins.util.log(stdout)
      done()

  gulp.task 'email:browser', ->
    browserSync.init
      notify: false
      server:
        baseDir: config.email.build

    # Watch for changes
    gulp.watch [
      "#{config.email.styles}/**/*"
      "#{config.email.templates}/**/*"
      "#{config.email.content}/**/*"
      "#{config.email.images}/**/*"
    ], ['email:reload']

    gulp.watch "#{config.email.images}/**/*", reload

  gulp.task 'email:reload', ['email:inline', 'email:images'], ->
    reload()

  gulp.task 'email', ->
    runSequence 'email:reload', 'email:browser'

  # Mailchimp tasks
  mailChimp =
    body: {}
  emailConfig = {}
  
  gulp.task 'mailchimp:config', ->
    emailConfig = yaml.load "#{config.email.source}/email.yml"
    if exists './secrets.yml'
      secrets = yaml.load './secrets.yml'
    else
      console.error 'Error: You need to setup a secrets file\nmv secrets-copy.yml secrets.yml'
    mailChimp =
      baseUrl: "https://#{emailConfig.datacenter}.api.mailchimp.com/2.0/"
      method: 'POST'
      json: true
      body:
        apikey: secrets.mailChimpAPIKey

  gulp.task 'mailchimp:lists', ['mailchimp:config'], ->
    mailChimp.url = 'lists/list'
    request mailChimp, (err, message, res) ->
      console.log 'Your Lists (name: id)...'
      for list in res.data
        console.log "#{list.name}: #{list.id}"

  # TODO: this might have a bug.
  # List returns second object twice in else statment
  gulp.task 'mailchimp:segments', ['mailchimp:config'], ->
    mailChimp.url = 'lists/segments'
    for list, listID of emailConfig.lists
      mailChimp.body.id = listID
      request mailChimp, (err, message, res) ->
        if res.static.length
          console.log "Static Segments for #{list} (ID Name)"
          for segment in res.static
            console.log "#{segment.name}: #{segment.id}"
        if res.saved.length
          console.log "Saved Segments for #{list} (ID Name)"
          for segment in res.saved
            console.log "#{segment.name}: #{segment.id}"
        else console.log "No Segments for #{list}"

  gulp.task 'mailchimp:campaign_folders', ['mailchimp:config'], ->
    mailChimp.url = 'folders/list'
    mailChimp.body.type = 'campaign'
    request mailChimp, (err, message, res) ->
      console.log 'Campaign Folders:'
      for folder in res
        console.log "#{folder.name}, #{folder.folder_id}"

  gulp.task 'mailchimp:autoresponder_folders', ['mailchimp:config'], ->
    mailChimp.url = 'folders/list'
    mailChimp.body.type = 'autoresponder'
    request mailChimp, (err, message, res) ->
      console.log 'Autoresponder Folders:'
      for folder in res
        console.log "#{folder.name}, #{folder.folder_id}"

  gulp.task 'mailchimp:folders', ['mailchimp:campaign_folders', 'mailchimp:autoresponder_folders']

  # List the merge vars for all the lists
  gulp.task 'mailchimp:vars', ['mailchimp:config'], ->
    mailChimp.url = 'lists/merge-vars'
    mailChimp.body.id = emailConfig.lists
    request mailChimp, (err, message, res) ->
      for list in res.data
        console.log "\nThe list, #{list.name}, with id, #{list.id} has the following merge vars:"
        for mergeVar in list.merge_vars
          console.log "#{mergeVar.name}, #{mergeVar.tag}"

  gulp.task 'mailchimp:autoresponders', ['mailchimp:config'], ->
    mailChimp.url = 'automations/list'
    request mailChimp, (err, message, res) ->
      console.log res.data

  gulp.task 'mailchimp:campaigns', ['mailchimp:config'], ->
    mailChimp.url = 'campaigns/list'
    request mailChimp, (err, message, res) ->
      for campaign in res.data
        console.log campaign

  gulp.task 'mailchimp:campaigns', ['mailchimp:config'], (done) ->
    mailChimp.url = 'campaigns/create'
    glob "#{config.email.build}/**/*.json", nodir: true, (err, files) ->
      newFiles = []
      for file in files
        if exists "#{process.cwd()}/#{config.email.source}/mailchimpLog.json"
          log = require "#{process.cwd()}/#{config.email.source}/mailchimpLog.json"
        else log = []
        fileIndex = (file.indexOf "#{config.email.build}/") + "#{config.email.build}/".length
        collection = path.dirname (file.slice fileIndex)
        slug = path.basename file, '.json'
        title = "#{collection}/#{slug}"
        # if file is in log skip
        found = false
        if log
          for campaign in log
            found = true if title is campaign.title
        newFiles.push file unless found

      unless newFiles.length
        console.log 'All campaigns are already synced with MailChimp'
      # Call Mailchimp with each new campaign
      for newFile in newFiles
        mailChimp.body = _.merge mailChimp.body, require "#{process.cwd()}/#{newFile}"
        request mailChimp, (err, message, res) ->
          pro = newFile
          if res.id
            # push res into log object and write to mailChimpLog
            log.push res
            fs.writeFileSync "./#{config.email.source}/mailChimpLog.json", "#{JSON.stringify log}"
            console.log "Check and activate this campaign in Mailchimp:\nhttps://#{emailConfig.datacenter}.admin.mailchimp.com/campaigns/wizard/confirm?id=#{res.web_id}"
          else
            for key, value of res
              console.error "#{key}: #{value}"

  # Compile email, move images to ssh server, and sync with mailchimp
  gulp.task 'mailchimp', ['email:deploy', 'email:inline', 'mailchimp:campaigns']

  #################
  # Main Gulp Tasks
  #################
  # Develop (the defualt task)
  gulp.task 'develop', (done) ->
    runSequence 'map', 'compile', 'browser', done

  gulp.task 'default', ['develop']
  gulp.task 'site', ['develop']

  # Build full site ready for production
  gulp.task 'build', (done) ->
    runSequence 'clean', 'map', 'compile', ['optimize', 'move', 'images'], 'cachebust', done

  # Preview server for production
  gulp.task 'preview', (done) ->
    runSequence 'build', 'previewBrowser', done

  # Deploy production site
  gulp.task 'deploy', ['build'], (done) ->
    runSequence 'rsync', done
