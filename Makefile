EMACS ?= emacs
CC ?= cc

all: jpgpreview autoloads

jpgpreview: jpgpreview.c
	$(CC) -O2 -Wall -o jpgpreview jpgpreview.c

image-triage-autoloads.el: image-triage.el
	$(EMACS) -Q --batch \
	  --eval '(loaddefs-generate "." "image-triage-autoloads.el")'

autoloads: image-triage-autoloads.el

clean:
	rm -f jpgpreview image-triage-autoloads.el *.elc

.PHONY: all autoloads clean
