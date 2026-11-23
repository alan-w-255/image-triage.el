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

(defvar image-triage-image-height 60
  "The height (in pixels) of image thumbnails.")
(defvar image-triage--data)
(defvar image-triage--file-name)
(defvar image-triage--last-process)

(defun image-triage-directory (directory)
  (interactive "DView directory: ")
  (let* ((regexp (mapconcat #'car image-triage-file-name-regexps "\\|"))
	 (files (let ((case-fold-search t))
		  (seq-filter (lambda (file)
				(string-match-p regexp file))
			      (directory-files directory t)))))
    (setq directory (expand-file-name directory))
    (switch-to-buffer (image-triage--create-buffer directory))
    (let ((inhibit-read-only t)
	  (current (image-triage--file-name))
	  (point (point))
	  (old-data (and (boundp 'image-triage--data)
			 image-triage--data)))
      (erase-buffer)
      (image-triage-list-mode)
      (setq-local image-triage--data (or old-data image-triage--data)
		  image-triage--file-name directory
		  image-triage--last-process nil)
      (add-hook 'window-scroll-functions #'image-triage--window-update
		nil t)
      (image-triage--insert files)
      (or (and current
	       (image-triage--goto-file current))
	  (goto-char point))
      (beginning-of-line)
      (image-triage--fill-thumbnails))))

(defun image-triage--insert (files)
  (let* ((twidth (* image-triage-image-height 3))
	 (swidth (string-pixel-width
		  (propertize "9999G" 'face 'variable-pitch)))
	 (dwidth (max (string-pixel-width
		       (propertize "WWW 30 2019" 'face 'variable-pitch))
		      (string-pixel-width
		       (propertize "99:99 2019" 'face 'variable-pitch))))
	 (new (- (time-convert nil 'integer)
		 (* 60 60 24 300)))
	 (seps
	  (list
	   (propertize " " 'display `(space :align-to (,twidth)))
	   (propertize " " 'display
		       `(space :align-to (,(+ twidth 10 swidth))))
	   (propertize " " 'display `(space :align-to
					    (,(+ twidth 20 swidth dwidth)))))))
    (setq header-line-format
	  (propertize
	   (concat
	    "Thumb" (nth 0 seps)
	    "Size" (nth 1 seps)
	    "Date" (nth 2 seps)
	    "File")
	   'face 'variable-pitch))
    (dolist (file files)
      (let ((atts (file-attributes file)))
	(insert (propertize (nth 0 seps)
			    'image-triage--file file)
		(propertize
		 (file-size-human-readable (file-attribute-size atts))
		 'face 'variable-pitch)
		(nth 1 seps)
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
		(nth 2 seps)
		(propertize (file-name-nondirectory file) 'face 'variable-pitch)
		(propertize "\n" 'line-height
			    (+ image-triage-image-height 10)))))))

(defun image-triage--goto-file (file)
  (let ((point (point)))
    (goto-char (point-min))
    (or (text-property-search-forward 'image-triage--file file #'equal)
	(progn
	  (goto-char point)
	  nil))))

(defun image-triage--file-name ()
  (get-text-property (pos-bol) 'image-triage--file))

(defvar-keymap image-triage-list-mode-map
  "RET" #'image-triage-display-image
  "s" #'image-triage-toggle-sort
  )

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
    (switch-to-buffer (image-triage--create-buffer file))
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

(defun image-triage--create-buffer (file)
  "If a buffer for FILE exists, return it.
Otherwise, create a new buffer."
  (or
   (cl-loop for buffer in (buffer-list)
	    when (equal (with-current-buffer buffer
			  (and (boundp 'image-triage--file-name)
			       image-triage--file-name))
			file)
	    return buffer)
   (get-buffer-create
    (generate-new-buffer-name
     (concat (file-name-nondirectory (directory-file-name file))
	     " Triage")))))

(define-derived-mode image-triage-display-mode special-mode "Triage Display"
  :interactive nil
  (setq cursor-type nil
	truncate-lines t))

(defun image-triage--window-update (_ _)
  (image-triage--fill-thumbnails))

(defun image-triage--fill-thumbnails ()
  (when image-triage--last-process
    (message "Time since: %s %s" (time-since image-triage--last-process)
	     (time-less-p
	     '(0 0 100000 0)
	     (time-since image-triage--last-process))))
  (when (or (null image-triage--last-process)
	    ;; More than half a second since the last time, so it's
	    ;; probably done.
	    (time-less-p
	     '(0 0 100000 0)
	     (time-since image-triage--last-process)))
    ;; We want to fill thumbnails on files that's displayed in the
    ;; window, and then the next window-ful, and then the previous
    ;; window-ful.
    (let ((buffer (current-buffer))
	  function)
      (setq function
	    (lambda ()
	      (image-triage--fill-thumbnails-1 buffer function)))
      (funcall function))))

(defun image-triage--fill-thumbnails-1 (buffer next)
  ;; Only do something if the buffer is visible.
  (when-let ((window (get-buffer-window buffer t)))
    (with-current-buffer buffer
      (let ((start (window-start window))
	    (end (window-end))
	    (lines 0)
	    (done nil))
	(cl-flet ((check ()
		    (when-let ((file (image-triage--file-name)))
		      (unless (get-text-property (point) 'thumbnail)
			(let ((elem (gethash file image-triage--data)))
			  (if (plist-get elem 'thumbnail)
			      (image-triage--insert-thumbnail
			       (plist-get elem 'thumbnail))
			    (image-triage--fetch-thumbnail file buffer next)
			    (setq done t)))))))
	(save-excursion
	  (goto-char start)
	  (beginning-of-line)
	  ;; Do the displayed lines.
	  (while (and (< (point) end)
		      (not done))
	    (check)
	    (forward-line 1)
	    (cl-incf lines))
	  ;; Do the next screen and a half.
	  (setq lines (truncate (* lines 1.5)))
	  (unless done
	    (let ((checked-lines 0))
	      (while (and (< checked-lines lines)
			  (not done)
			  (not (eobp)))
		(check)
		(forward-line 1)
		(cl-incf checked-lines))))
	  ;; Do the previous screen and a half.
	  (unless done
	    (goto-char start)
	    (let ((checked-lines 0))
	      (while (and (< checked-lines lines)
			  (not done))
		(check)
		(if (bobp)
		    (setq done t)
		  (forward-line -1))
		(cl-incf checked-lines))))))))))

(defun image-triage--insert-thumbnail (data &optional dummy)
  (let ((inhibit-read-only t))
    (beginning-of-line)
    (if dummy
	;; We have no data, but mark the line.
	(put-text-property (point) (1+ (point)) 'thumbnail :error)
      (condition-case ()
	  (insert-image
	   (create-image data nil t
			 :height image-triage-image-height
			 :scale 1
			 :ascent 100)
	   (propertize " " 'image-triage--file-name
		       (get-text-property
			(point) 'image-triage--file-name)
		       'thumbnail t))
	(error (message "Unable to insert"))))))

(defun image-triage--fetch-thumbnail (file buffer next)
  ;;(message "Fetching thumb for %s" file)
  (when (buffer-live-p buffer)
    (let ((fast (expand-file-name "jpgpreview"
				  (file-name-directory
				   (find-library-name "image-triage.el")))))
		
      (cond
       ((not (file-exists-p file))
	(funcall next))
       (fast
	(image-triage--fetch-thumbnail-from-exif
	 file buffer next "thumb" fast))
       (t
	(with-current-buffer buffer
	  (setq image-triage--last-process (current-time)))
	(make-process
	 :name "exiftool"
	 :buffer (generate-new-buffer " *exiftool*")
	 :command (list "exiftool" "-json" "-a" "-G1" "-s"
			"-preview:all" file)
	 :sentinel
	 (lambda (proc _)
	   (with-current-buffer (process-buffer proc)
	     (let ((data nil))
	       (goto-char (point-min))
	       (unwind-protect
		   (let ((json (elt (json-parse-buffer :object-type 'plist) 0))
			 (case-fold-search t))
		     (cl-loop for (slot value) on json by #'cddr
			      do (cond
				  ((string-match-p "thumbnail" (symbol-name slot))
				   (push (list 'thumbnail
					       (substring (symbol-name slot) 1)
					       (image-triage--exif-bytes value))
					 data))
				  ((string-match-p "preview" (symbol-name slot))
				   (push (list 'preview
					       (substring (symbol-name slot) 1)
					       (image-triage--exif-bytes value))
					 data)))))
		 (kill-buffer (current-buffer)))
	       (when (buffer-live-p buffer)
		 (when data
		   (with-current-buffer buffer
		     (setf (gethash file image-triage--data)
			   (list 'exif data))))
		 (image-triage--fetch-thumbnail-from-exif
		  file buffer next (nth 1 (assq 'thumbnail data)))))))))))))

(defun image-triage--fetch-thumbnail-from-exif (file buffer next
						     thumbnail-name
						     &optional fast)
  (with-current-buffer (generate-new-buffer " *exif thumbnail*")
    (set-buffer-multibyte nil)
    (with-current-buffer buffer
      (setq image-triage--last-process (current-time)))
    (make-process
     :name "exiftool"
     :buffer (current-buffer)
     :command (cond
	       (fast
		(list fast thumbnail-name file))
	       (thumbnail-name
		(list "exiftool" "-b" (concat "-" thumbnail-name) file))
	       (t
		;; If we don't have a thumbnail, then extract from the
		;; file itself.
		(list "convert" "-resize"
		      (format "x%d" image-triage-image-height)
		      file "jpg:-")))
     :sentinel
     (lambda (proc _)
       (let ((thumbnail
	      (with-current-buffer (process-buffer proc)
		(prog1
		    (buffer-string)
		  (kill-buffer (current-buffer))))))
	 (when (buffer-live-p buffer)
	   (with-current-buffer buffer
	     (save-excursion
	       (let ((elem (gethash file image-triage--data)))
		 (setf (gethash file image-triage--data)
		       (plist-put elem 'thumbnail thumbnail)))
	       (when (image-triage--goto-file file)
		 (image-triage--insert-thumbnail
		  thumbnail (not (zerop (process-exit-status proc)))))
	       (funcall next)))))))))

;; "(Binary data 10499 bytes, use -b option to extract)"
(defun image-triage--exif-bytes (string)
  (and (string-match " \\([0-9]+\\) bytes" string)
       (string-to-number (match-string 1 string))))

(provide 'image-triage)

;;; image-triage.el ends here
