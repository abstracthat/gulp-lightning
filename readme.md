My front-end development gulpfile. Used in the [Site Lightning](http://github.com/abstracthat/sitelightning) front-end development boilerplate.

This is pretty specific to my workflow for now. I may make it more modular in the future. If you want to use it, you have to use the folder structure in Site Lightning and use this in your project's `gulpfile.js`. You can pass an options object but it's a bit buggy still so it's best to just pass the server for rsync'ing.

```js
var gulp = require("gulp");
var lightning = require("gulp-lightning");

var config = {};
config.server = "projects:/var/www/sitelightning.co";

lightning(gulp, config);
```
