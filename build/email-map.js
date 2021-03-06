// Generated by CoffeeScript 1.7.1
(function() {
  var directories, emailMap, exists, frontMatter, fs, glob, markdown, path, yaml, _;

  fs = require('fs');

  path = require('path');

  exists = (require('fs')).existsSync;

  _ = require('lodash');

  directories = (require('node-dir')).subdirs;

  glob = require('globby');

  yaml = require('yamljs');

  frontMatter = require('front-matter');

  markdown = require('marked');

  markdown.setOptions({
    smartypants: true
  });

  emailMap = {
    campaigns: [],
    rss: [],
    splitTests: [],
    autoresponders: {}
  };

  module.exports = function(config, done) {
    var createMap, writeJSON;
    _.extend(emailMap, yaml.load("./" + config.email.source + "/email.yml"));
    createMap = function(cb) {
      return glob(["./" + config.email.content + "/**/*.{jade,md}", "!./" + config.email.content + "/_includes/**/*"], {
        nodir: true
      }, function(err, files) {
        var collection, dir, directory, file, isAutoresponder, isCampaign, isRSS, isSplitTest, slug, _i, _len;
        if (err) {
          console.error;
        }
        for (_i = 0, _len = files.length; _i < _len; _i++) {
          file = files[_i];
          dir = path.dirname(file);
          isCampaign = dir.match(config.email.campaigns);
          isRSS = dir.match(config.email.rss);
          isSplitTest = dir.match(config.email.splitTests);
          isAutoresponder = dir.match(config.email.autoresponders);
          if (isCampaign) {
            collection = 'campaigns';
          }
          if (isRSS) {
            collection = 'rss';
          }
          if (isSplitTest) {
            collection = 'splitTests';
          }
          if (isAutoresponder) {
            collection = "autoresponders";
            directory = dir.slice((dir.lastIndexOf('/')) + 1);
            if (!emailMap.autoresponders[directory]) {
              emailMap.autoresponders[directory] = [];
            }
          }
          slug = path.basename(file, path.extname(file));
          if (isAutoresponder) {
            emailMap.autoresponders[directory].push(slug);
          } else {
            emailMap[collection].push(slug);
          }
        }
        return cb();
      });
    };
    writeJSON = function(done) {
      fs.writeFileSync("./" + config.email.source + "/email.json", JSON.stringify(emailMap));
      return done();
    };
    return createMap(function() {
      return writeJSON(function() {
        return done();
      });
    });
  };

}).call(this);
