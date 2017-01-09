gulp				= require 'gulp'
less				= require 'gulp-less'
stylus			= require 'gulp-stylus'
coffee			= require 'gulp-coffee'
gulpIgnore	= require 'gulp-ignore'


gulp.task 'dev-js', ->
	gulp.src '*.coffee'
		.pipe gulpIgnore.exclude ['gulpfile.coffee']
		.pipe coffee() 
		.pipe gulp.dest './'

gulp.task 'dev-css', ['less'], ->
	gulp.src 'styles.styl'
		.pipe stylus({
			compress: true
		})
		.pipe gulp.dest './'

gulp.task 'less', ->
	gulp.src '*.less'
		.pipe less()
		.pipe gulp.dest './'


