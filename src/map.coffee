fs = require 'fs'
path = require 'path'
exists = (require 'fs').existsSync

_ = require 'lodash'
directories = (require 'node-dir').subdirs
glob = require 'globby'
yaml = require 'yamljs'
moment = require 'moment'
cheerio = require 'cheerio'
typography = require 'typogr'
frontMatter = require 'front-matter'
markdown = require 'marked'
markdown.setOptions
  smartypants: true

module.exports = (config, done) ->

  # scaffold the site object
  map =
    site:
      name: ''
      url: ''
      title: ''
      description: ''
    pages: {}
    collections: {}

  # pass in some site variables via site.yml
  _.extend map, yaml.load "./site/site.yml"

  # smartypants: convert apostrophes, en/em dash, quotes
  # TODO: DRY this out
  map.site.name = typography(map.site.name).chain().smartypants().value()
  if map.header
    for page in map.header
      page.title = typography(page.title).chain().smartypants().value()
  if map.footer
    for page in map.footer
      page.title = typography(page.title).chain().smartypants().value()

  # Get the collections (folders) first so we can sort our pages into them
  getCollections = (cb) -> 
    directories "./#{config.site.content}", (err, collections) ->
      for collection in collections
        url = "#{collection}/".replace config.site.content, ''
        unless url is '/_includes/'
          map.collections[url] =
            url: url
            pages: [] # array to push found pages into later
      cb()

  # Read the files and add the metadata to the site object
  createMap = (cb) ->
    glob ["./#{config.site.content}/**/*.{jade,md}", "!./#{config.site.content}/_includes/**/*"], nodir: true, (err, files) ->
      console.error if err
      for file in files
        data = fs.readFileSync file, 'utf8'
        content = frontMatter data
        meta = content.attributes or {}
        post = ''

        # Build the parsed page metadata
        page = {}
        page.url = file.slice (file.indexOf config.site.content) + config.site.content.length
        .replace /((\/)index)?(\.jade$|.\md$)/, '$2'

        # if there is a yml file that matches the slug update the content meta
        if page.url.match /\/$/
          metaDataFile = "./#{config.site.content}#{page.url}/index.yml"
        else
          metaDataFile = "./#{config.site.content}#{page.url}.yml"

        if exists metaDataFile
          meta = _.merge (yaml.load metaDataFile), meta

        page.title = typography(meta.title).chain().smartypants().value() if meta.title
        page.description = typography(meta.description).chain().smartypants().value() if meta.description
        page.tags = meta.tags if meta.tags

        # Parse the date
        if meta.date
          page.datetime = moment(new Date(meta.date)).format()
          page.date = moment(new Date meta.date).format('MMMM Do, YYYY')

        # Compile markdown and load html into cheerio
        if (path.extname file) is '.md'
          post = markdown content.body
          page.post = post
          $ = cheerio.load post

          # unless intro is given in meta, take the first paragraph of the post
          if meta.intro
            page.intro = meta.intro
          else
            # markdown wraps images in <p>, take the first <p> with no <img>
            intro = $('p:not(:has(img))').first().html()
            page.intro = intro if intro

          # unless image is given in meta, take the first image from the post
          if meta.image
            page.image = content.attributes.image
          else
            image = $('img').attr('src')
            page.image = image if image
        
        # if it's not markdown (i.e. jade) then look for intro and image meta
        else
          page.intro = meta.intro if meta.intro
          page.image = content.attributes.image if meta.image

        # the url is either the root, page, collection, or page in a collection
        # root is just '/'
        if page.url is '/'
          map.site.title = page.title
          map.site.description = page.description
        
        # it's a site level page if there is only 1 '/'
        # add the slash so that all url's end with '/' to match nginx server
        else if (page.url.match /\//g).length < 2
          page.url += '/'
          map.pages[page.url] = page
        
        # it's collection index page if the url ends in '/'
        else if page.url.match /\/$/
          _.extend map.collections[page.url], page
        
        # otherwise it's a page in a collection + add trailing '/' to match server
        else
          collection = (path.dirname page.url) + '/'
          page.url += '/'
          map.collections[collection].pages.push page
      
      # Finished with createMap, callback
      cb()

  # Sort the pages in each collection by date (newest first)
  sortCollectionPages = (done) ->
    for key, collection of map.collections
      collection.pages.sort (a, b) ->
        new Date(b.datetime) - new Date(a.datetime)
    done()

  # Write the site object to site.json
  writeJSON = (done) ->
    fs.writeFileSync "./#{config.site.source}/site.json", JSON.stringify map
    done()

  # Main Program
  getCollections -> createMap -> sortCollectionPages -> writeJSON -> done()
