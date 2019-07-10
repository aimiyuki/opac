const gulp = require('gulp');
const sass = require('gulp-sass');

gulp.task('sass', function(){
    gulp.src('/.stylesheets/style.scss')
        .pipe(sass({outputStyle: 'expanded'}))
        .pipe(gulp.dest('./css/'));
});

//自動監視
gulp.task('sass-watch', ['sass'], function(){
    var watcher = gulp.watch('./stylesheets/style.scss', ['sass']);
    watcher.on('change', function(event) {
    });
});

gulp.task('default', ['sass-watch']);
