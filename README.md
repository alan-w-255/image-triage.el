image-triage is a package for quickly looking through large
collections of images.

It needs imagemagick and exiftool to work.  In addition, the
jpgpreview binary (source included in this package) should be compiled
to speed things up greatly.

So to use, do the following:

;; Adjust to your setup.
(push "~/src/image-triage.el/" load-path) 
(autoload 'image-triage-directory "image-triage" nil t)
(autoload 'image-triage-tree "image-triage" nil t)

And also say "make" in the source directory.
