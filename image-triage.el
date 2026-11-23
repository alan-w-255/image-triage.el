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

(defvar image-triage-image-height 80
  "The height (in pixels) of image thumbnails.")
(defvar image-triage--data)
(defvar image-triage--file-name)
(defvar image-triage--last-process)
(defvar image-triage--parent-buffer)
(defvar image-triage--marked-files)
(defvar image-triage--sort-mode)

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
			 image-triage--data))
	  (old-marked (and (boundp 'image-triage--marked-files)
			   image-triage--marked-files))
	  (old-sort (and (boundp 'image-triage--sort-mode)
			 image-triage--sort-mode)))
      (erase-buffer)
      (image-triage-list-mode)
      (setq-local image-triage--data (or old-data image-triage--data)
		  image-triage--file-name directory
		  image-triage--last-process nil
		  image-triage--marked-files old-marked
		  image-triage--sort-mode old-sort)
      (unless image-triage--sort-mode
	(setq image-triage--sort-mode 'time))
      (setq default-directory directory)
      (add-hook 'window-scroll-functions #'image-triage--window-update
		nil t)
      (image-triage--insert
       (if (eq image-triage--sort-mode 'time)
	   (sort files (lambda (f1 f2)
			 ;; Sort newest first by default.
			 (time-less-p (file-attribute-modification-time
				       (file-attributes f2))
				      (file-attribute-modification-time
				       (file-attributes f1)))))
	 ;; Alphabeticalish.
	 (sort files #'string-version-lessp)))
      (or (and current
	       (image-triage--goto-file current))
	  (goto-char point))
      (beginning-of-line)
      (image-triage--fill-thumbnails))))

(defun image-triage--insert (files)
  (let* ((twidth (* image-triage-image-height 3))
	 (swidth (string-pixel-width
		  (propertize "9999G" 'face 'variable-pitch)))
	 (mwidth (string-pixel-width
		  (propertize "*" 'face 'variable-pitch)))
	 (dwidth (max (string-pixel-width
		       (propertize "WWW 30 2019" 'face 'variable-pitch))
		      (string-pixel-width
		       (propertize "99:99 2019" 'face 'variable-pitch))))
	 (new (- (time-convert nil 'integer)
		 (* 60 60 24 300)))
	 (seps
	  (list
	   (propertize " " 'display
		       `(space :align-to (,twidth)))
	   (propertize " " 'display
		       `(space :align-to (,(+ twidth mwidth 20))))
	   (propertize " " 'display
		       `(space :align-to (,(+ twidth mwidth 30 swidth))))
	   (propertize " " 'display
		       `(space :align-to (,(+ twidth mwidth 40 swidth dwidth)))))))
    (setq header-line-format
	  (propertize
	   (concat
	    "Thumb" (nth 0 seps)
	    "M" (nth 1 seps)
	    "Size" (nth 2 seps)
	    "Date" (nth 3 seps)
	    "File")
	   'face 'variable-pitch))
    (dolist (file files)
      (let ((atts (file-attributes file)))
	(insert (propertize (nth 0 seps)
			    'image-triage--file file)
		(propertize 
		 (if (member file image-triage--marked-files)
		     "*" " ")
		 'face 'variable-pitch 'toggle t)
		(nth 1 seps)
		(propertize
		 (file-size-human-readable (file-attribute-size atts))
		 'face 'variable-pitch)
		(nth 2 seps)
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
		(nth 3 seps)
		(propertize (file-name-nondirectory file) 'face 'variable-pitch)
		(propertize "\n" 'line-height
			    (+ image-triage-image-height 8)))))))

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
  "SPC" #'image-triage-list-toggle-mark
  "m" #'image-triage-list-mark
  "U" #'image-triage-list-unmark-all
  "u" #'image-triage-list-unmark
  "g" #'image-triage-list-reload
  "C" #'image-triage-list-copy
  "s" #'image-triage-list-toggle-sort)

(define-derived-mode image-triage-list-mode special-mode "Image Triage"
  :interactive nil
  (setq truncate-lines t)
  (setq-local image-triage--data (make-hash-table :test #'equal)) )

(defun image-triage-list-toggle-sort ()
  "Toggle sorting by time/alphabet."
  (interactive nil image-triage-list-mode)
  (setq image-triage--sort-mode
	(if (eq image-triage--sort-mode 'time)
	    'alpha 'time))
  (image-triage-list-reload))

(defun image-triage-list-reload ()
  "Reload the current list."
  (interactive nil image-triage-list-mode)
  (image-triage-directory image-triage--file-name))

(defun image-triage-list-copy (files to-directory)
  "Copy the marked files somewhere.
If none are marked, copy the file under point."
  (interactive (list (image-triage--current-files)
		     (read-directory-name "Copy to: "))
	       image-triage-list-mode)
  (unless files
    (user-error "No file under point"))
  (let ((done 0))
    (map-y-or-n-p
     (lambda (file)
       (let ((to (expand-file-name (file-name-nondirectory file) to-directory)))
	 (if (file-exists-p to)
	     (format "Overwrite %s?" to)
	   t)))
     (lambda (file)
       (copy-file file (expand-file-name (file-name-nondirectory file)
					 to-directory)
		  t t)
       (cl-incf done))
     files)
    (message "Copied %s file%s" done (if (= done 1) "" "s"))))

(defun image-triage-list-toggle-mark ()
  "Toggle the mark on the image under point."
  (interactive nil image-triage-list-mode)
  (let ((file (image-triage--file-name)))
    (unless file
      (user-error "No file under point"))
    (if (member file image-triage--marked-files)
	(image-triage-list-unmark)
      (image-triage-list-mark))))

(defun image-triage-list-mark ()
  "Set the mark on the image under point."
  (interactive nil image-triage-list-mode)
  (let ((file (image-triage--file-name))
	(inhibit-read-only t))
    (unless file
      (user-error "No file under point"))
    (save-excursion
      (beginning-of-line)
      (text-property-search-forward 'toggle)
      (setq image-triage--marked-files (delete file image-triage--marked-files))
      (push file image-triage--marked-files)
      (subst-char-in-region (point) (1- (point))
			    ?\s ?*)
      (message "Marked %s" file))))

(defun image-triage-list-unmark-all ()
  "Unset the mark on all images."
  (interactive nil image-triage-list-mode)
  (unless image-triage--marked-files
    (user-error "No files have been marked"))
  (let ((count 0))
    (save-excursion
      (dolist (file image-triage--marked-files)
	(image-triage--goto-file file)
	(image-triage-list-unmark t)
	(cl-incf count)))
    (message "Unmarked %s file%s" count (if (= count 1) "" "s"))))

(defun image-triage--current-files ()
  "Return the list of marked files, or if none, the file under point."
  (or image-triage--marked-files
      (when-let ((file (image-triage--file-name)))
	(list file))))

(defun image-triage-list-unmark (&optional silent)
  "Unset the mark on the image under point."
  (interactive nil image-triage-list-mode)
  (let ((file (image-triage--file-name))
	(inhibit-read-only t))
    (unless file
      (user-error "No file under point"))
    (save-excursion
      (beginning-of-line)
      (text-property-search-forward 'toggle)
      (setq image-triage--marked-files
	    (delete file image-triage--marked-files))
      (subst-char-in-region (point) (1- (point))
			    ?* ?\s)
      (unless silent
	(message "Removed mark from %s" file)))))

(defun image-triage-display-image (file)
  "Display the image under point."
  (interactive (list (image-triage--file-name)) image-triage-list-mode)
  (unless file
    (user-error "No file under point"))
  (unless (file-exists-p file)
    (user-error "File %s does not exist file"))
  (let ((parent (current-buffer)))
    (switch-to-buffer (image-triage--create-buffer file))
    (image-triage-display-mode)
    (setq-local image-triage--file-name file
		image-triage--parent-buffer parent)
    (image-triage--display-image file)))

(defun image-triage-display-next ()
  "View the next image in the buffer."
  (interactive nil image-triage-display-mode)
  (image-triage--move 'next))

(defun image-triage-display-previous ()
  "View the previous image in the buffer."
  (interactive nil image-triage-display-mode)
  (image-triage--move 'previous))

(defun image-triage--move (direction)
  (let ((parent image-triage--parent-buffer)
	(file image-triage--file-name)
	next-file)
    (unless (buffer-live-p parent)
      (user-error "The parent buffer has been killed"))
    (save-window-excursion
      (switch-to-buffer parent t t)
      (image-triage--goto-file file)
      (let ((point (point)))
	(if (equal direction 'next)
	    (progn
	      (forward-line 1)
	      (setq next-file (image-triage--file-name)))
	  (unless (bobp)
	    (forward-line -1)
	    (setq next-file (image-triage--file-name))))
	(unless next-file
	  (goto-char point)
	  (user-error "No next file"))))
    (image-triage--display-image next-file)
    (setq image-triage--file-name next-file
	  default-directory (file-name-directory next-file))
    (rename-buffer (generate-new-buffer-name
		    (concat (file-name-nondirectory (directory-file-name
						     next-file))
			    " Triage")))
    (message "Selected %s image" (if (eq direction 'next)
				     "next" "previous"))))

(defun image-triage-display-full ()
  "Display the full version of the current image.
(By default, this mode displays downscaled versions to speed
things up.)"
  (interactive nil image-triage-display-mode)
  (image-triage--display-image image-triage--file-name t)
  (message "Displaying full version of %s" image-triage--file-name))

(defun image-triage-display-toggle-mark ()
  "Toggle marking the current image in the buffer."
  (interactive nil image-triage-display-mode)
  (let ((parent image-triage--parent-buffer)
	(file image-triage--file-name))
    (unless (buffer-live-p parent)
      (user-error "The parent buffer has been killed"))
    (save-window-excursion
      (switch-to-buffer parent t t)
      (image-triage--goto-file file)
      (image-triage-list-toggle-mark))))

(defun image-triage-display-mark ()
  "Mark the current image in the parent buffer."
  (interactive nil image-triage-display-mode)
  (let ((parent image-triage--parent-buffer)
	(file image-triage--file-name))
    (unless (buffer-live-p parent)
      (user-error "The parent buffer has been killed"))
    (save-window-excursion
      (switch-to-buffer parent t t)
      (image-triage--goto-file file)
      (image-triage-list-mark))))

(defun image-triage-display-unmark ()
  "Unmark the current image in the parent buffer."
  (interactive nil image-triage-display-mode)
  (let ((parent image-triage--parent-buffer)
	(file image-triage--file-name))
    (unless (buffer-live-p parent)
      (user-error "The parent buffer has been killed"))
    (save-window-excursion
      (switch-to-buffer parent t t)
      (image-triage--goto-file file)
      (image-triage-list-unmark))))

(defun image-triage--display-image (file &optional inhibit-preview)
  (let ((inhibit-read-only t)
	(idata (and (not inhibit-preview) (image-triage--preview file))))
    (when (zerop (length idata))
      (setq idata nil))
    (erase-buffer)
    (insert (propertize
	     " " 'display
	     (create-image
	      (if idata idata file) nil idata
	      :width (truncate (* (frame-pixel-width) 0.95))
	      :max-height (truncate (* (frame-pixel-height) 0.9))
	      :scale 1)))
    (goto-char (point-min))))

(defun image-triage--preview (file)
  (let ((fast (expand-file-name "jpgpreview"
				(file-name-directory
				 (find-library-name "image-triage.el")))))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (cond
       ((file-exists-p fast)
	(call-process fast nil t nil "preview" file))
       (t
	(call-process "exiftool" nil t nil
		      "-json" "-a" "-G1" "-s"
		      "-preview:all" file)
	(goto-char (point-min))
	(let* ((json (elt (json-parse-buffer :object-type 'plist) 0))
	       (case-fold-search t)
	       (preview-name
		(cl-loop for (slot _value) on json by #'cddr
			 when (string-match-p "preview" (symbol-name slot))
			 return (substring (symbol-name slot) 1))))
	  (erase-buffer)
	  (call-process "exiftool" nil t nil
			"-b" (concat "-" preview-name) file))))
      (buffer-string))))

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

(defvar-keymap image-triage-display-mode-map
  "n" #'image-triage-display-next
  "p" #'image-triage-display-previous
  "g" #'image-triage-display-full
  "SPC" #'image-triage-display-toggle-mark
  "m" #'image-triage-display-mark
  "u" #'image-triage-display-unmark)

(define-derived-mode image-triage-display-mode special-mode "Triage Display"
  :interactive nil
  (setq cursor-type nil
	truncate-lines t))

(defun image-triage--window-update (_ _)
  ;; `window-end' isn't updated right away, apparently, so postpone
  ;; this slightly.
  (run-at-time 0.01 nil #'image-triage--fill-thumbnails))

(defun image-triage--fill-thumbnails ()
  (when (and (boundp 'image-triage--last-process)
	     (or (null image-triage--last-process)
		 ;; More than half a second since the last time, so it's
		 ;; probably done.
		 (time-less-p
		  '(0 0 100000 0)
		  (time-since image-triage--last-process))))
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
	    (end (window-end window))
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
	   (propertize " " 'image-triage--file
		       (get-text-property
			(point) 'image-triage--file)
		       'thumbnail t))
	(error nil)))))

(defun image-triage--fetch-thumbnail (file buffer next &optional inhibit-fast)
  ;;(message "Fetching thumb for %s" file)
  (when (buffer-live-p buffer)
    (let ((fast (expand-file-name "jpgpreview"
				  (file-name-directory
				   (find-library-name "image-triage.el")))))
		
      (cond
       ((not (file-exists-p file))
	(funcall next))
       ((and (not inhibit-fast)
	     (file-exists-p fast))
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
       (if (and fast
		(not (zerop (process-exit-status proc))))
	   ;; If we used the fast version, we may not have gotten
	   ;; a thumbnail (because there wasn't one).  If so,
	   ;; go back and do it that hard way.
	   (image-triage--fetch-thumbnail file buffer next t)
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
		 (funcall next))))))))))

;; "(Binary data 10499 bytes, use -b option to extract)"
(defun image-triage--exif-bytes (string)
  (and (string-match " \\([0-9]+\\) bytes" string)
       (string-to-number (match-string 1 string))))

(provide 'image-triage)

;;; image-triage.el ends here
