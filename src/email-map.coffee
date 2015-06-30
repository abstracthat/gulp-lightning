# TODO: DRY with map.coffee
fs = require 'fs'
path = require 'path'
exists = (require 'fs').existsSync

_ = require 'lodash'
directories = (require 'node-dir').subdirs
glob = require 'globby'
yaml = require 'yamljs'
frontMatter = require 'front-matter'
markdown = require 'marked'
markdown.setOptions
  smartypants: true

# scaffold the emailMap object
emailMap =
  campaigns: []
  rss: []
  splitTests: []
  autoresponders: {}

module.exports = (config, done) ->

  # pass in some email variables via email.yml
  _.extend emailMap, yaml.load "./#{config.email.source}/email.yml"

  # Read the files and add the metadata to the emailMap object
  createMap = (cb) ->

    # loop through the jade and md files
    glob ["./#{config.email.content}/**/*.{jade,md}", "!./#{config.email.content}/_includes/**/*"], nodir: true, (err, files) ->
      console.error if err

      for file in files
        # is this file in the campaigns or autoresponders directory?
        dir = path.dirname file
        isCampaign = dir.match config.email.campaigns
        isRSS = dir.match config.email.rss
        isSplitTest = dir.match config.email.splitTests
        isAutoresponder = dir.match config.email.autoresponders

        if isCampaign
          collection = 'campaigns'

        if isRSS
          collection = 'rss'

        if isSplitTest
          collection = 'splitTests'

        if isAutoresponder
          collection = "autoresponders"
          # if it's an autoresponder what folder is it in?
          directory = dir.slice (dir.lastIndexOf '/') + 1
          # if we haven't yet, create the array using the folder name
          unless emailMap.autoresponders[directory]
            emailMap.autoresponders[directory] = []

        # the slug is just the file name without the extension
        slug = path.basename file, (path.extname file)

        # Push content object to array
        if isAutoresponder
          emailMap.autoresponders[directory].push slug
        else
          emailMap[collection].push slug

      # Finished with createMap, callback
      cb()

  # Write the site object to email.json
  writeJSON = (done) ->
    fs.writeFileSync "./#{config.email.source}/email.json", JSON.stringify emailMap
    done()

  # Main Program
  createMap -> writeJSON -> done()
