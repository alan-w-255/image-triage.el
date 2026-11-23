;;; image-triage.el --- View and mark images quickly -*- lexical-binding: t -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>
;; Keywords: images

;; image-triage is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; image-triage is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;;; Commentary:


;;; Code:

(require 'cl-lib)

(defvar image-triage-file-name-regexps image-type-file-name-regexps
  "Alist of regexps for matching image file names.")

(defvar image-triage--data)

(defun image-triage-directory (directory)
  (interactive "DView directory: ")
  (let* ((regexp (mapconcat #'car image-triage-file-name-regexps "\\|"))
	 (files (let ((case-fold-search t))
		  (seq-filter (lambda (file)
				(string-match-p regexp file))
			      (directory-files directory t)))))
    (switch-to-buffer (create-file-buffer directory))
    (let ((inhibit-read-only t)
	  (current (image-triage--file-name))
	  (point (point)))
      (erase-buffer)
      (image-triage-list-mode)
      (image-triage--insert files)
      (or (and current
	       (image-triage--goto-file current))
	  (goto-char point))
      (beginning-of-line))))

(defun image-triage--insert (files)
  (let ((swidth (string-pixel-width (propertize "9999G" 'face 'variable-pitch)))
	(dwidth (max (string-pixel-width
		      (propertize "WWW 30 2019" 'face 'variable-pitch))
		     (string-pixel-width
		      (propertize "99:99 2019" 'face 'variable-pitch))))
	(new (- (time-convert nil 'integer)
		(* 60 60 24 300))))
    (dolist (file files)
      (let ((atts (file-attributes file)))
	(insert (propertize " " 'display '(space :align-to (100))
			    'image-triage--file file)
		(propertize
		 (file-size-human-readable (file-attribute-size atts))
		 'face 'variable-pitch)
		(propertize " " 'display
			    `(space :align-to (,(+ 100 10 swidth))))
		(propertize
		 (if (> (time-convert (file-attribute-modification-time atts)
				      'integer)
			new)
		     (format-time-string
		      "%b %d %H:%M"
		      (file-attribute-modification-time atts))
		   (format-time-string
		    "%b %d %Y"
		    (file-attribute-modification-time atts)))
		 'face 'variable-pitch)
		(propertize " " 'display `(space :align-to
						 (,(+ 100 20 swidth dwidth))))
		(file-name-nondirectory file)
		"\n")))))

(defun image-triage--goto-file (file)
  (let ((point (point)))
    (goto-char (point-min))
    (or (text-property-search-forward 'image-triage--file file)
	(progn
	  (goto-char point)
	  nil))))

(defun image-triage--file-name ()
  (get-text-property (pos-bol) 'image-triage--file))

(defvar-keymap image-triage-list-mode-map
  "RET" #'image-triage-display-image)

(define-derived-mode image-triage-list-mode special-mode "Image Triage"
  :interactive nil
  (setq truncate-lines t)
  (setq-local image-triage--data (make-hash-table :test #'equal))
  )

(defun image-triage-display-image (file)
  "Display the image under point."
  (interactive (list (image-triage--file-name)) image-triage-list-mode)
  (unless file
    (user-error "No file under point"))
  (unless (file-exists-p file)
    (user-error "File %s does not exist file"))
  (let ((elem (gethash file image-triage--data)))
    (switch-to-buffer (create-file-buffer file))
    (image-triage-display-mode)
    (let ((inhibit-read-only t)
	  (idata (plist-get elem 'display)))
      (erase-buffer)
      (insert (propertize
	       " " 'display
	       (create-image
		(if idata idata file) nil idata
		:max-width (truncate (* (frame-pixel-width) 0.9))
		:max-height (truncate (* (frame-pixel-height) 0.9)))))
      (goto-char (point-min)))))

(define-derived-mode image-triage-display-mode special-mode "Triage Display"
  :interactive nil
  (setq cursor-type nil
	truncate-lines t))
  
(provide 'image-triage)

;;; image-triage.el ends here
