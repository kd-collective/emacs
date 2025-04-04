;;; eudc-bob.el --- Binary Objects Support for EUDC  -*- lexical-binding: t; -*-

;; Copyright (C) 1999-2025 Free Software Foundation, Inc.

;; Author: Oscar Figueiredo <oscar@cpe.fr>
;;         Pavel Janík <Pavel@Janik.cz>
;; Maintainer: Thomas Fitzsimmons <fitzsim@fitzsim.org>
;; Keywords: comm
;; Package: eudc

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; eudc-bob.el presents binary entries in LDAP results in interactive
;; ways.  For example, it will display JPEG binary data as an inline
;; image in the results buffer.  See also
;; https://tools.ietf.org/html/rfc2798.

;;; Usage:

;; The eudc-bob interactive functions are invoked when the user
;; interacts with an `eudc-query-form' results buffer.

;;; Code:

(require 'eudc)

(defvar-keymap eudc-bob-generic-keymap
  :doc "Keymap for multimedia objects."
  "s" #'eudc-bob-save-object
  "!" #'eudc-bob-pipe-object-to-external-program
  "<down-mouse-3>" #'eudc-bob-popup-menu)

(defvar-keymap eudc-bob-image-keymap
  :doc "Keymap for inline images."
  :parent eudc-bob-generic-keymap
  "t" #'eudc-bob-toggle-inline-display)

(defvar-keymap eudc-bob-sound-keymap
  :doc "Keymap for inline sounds."
  :parent eudc-bob-generic-keymap
  "RET" #'eudc-bob-play-sound-at-point
  "<down-mouse-2>" #'eudc-bob-play-sound-at-mouse)

(defvar-keymap eudc-bob-url-keymap
  :doc "Keymap for inline urls."
  "RET" #'browse-url-at-point
  "<down-mouse-2>" #'browse-url-at-mouse)

(defvar-keymap eudc-bob-mail-keymap
  :doc "Keymap for inline e-mail addresses."
  "RET" #'goto-address-at-point
  "<down-mouse-2>" #'goto-address-at-point)

(defvar eudc-bob-generic-menu
  '("EUDC Binary Object Menu"
    ["---" nil nil]
    ["Pipe to external program" eudc-bob-pipe-object-to-external-program t]
    ["Save object" eudc-bob-save-object t]))

(defvar eudc-bob-image-menu
  `("EUDC Image Menu"
    ["---" nil nil]
    ["Toggle inline display" eudc-bob-toggle-inline-display
     (display-graphic-p)]
    ,@(cdr (cdr eudc-bob-generic-menu))))

(defvar eudc-bob-sound-menu
  `("EUDC Sound Menu"
    ["---" nil nil]
    ["Play sound" eudc-bob-play-sound-at-point
     (fboundp 'play-sound-internal)]
    ,@(cdr (cdr eudc-bob-generic-menu))))

(defun eudc-bob-get-overlay-prop (prop)
  "Get property PROP from one of the overlays around."
  (let ((overlays (append (overlays-at (1- (point)))
			  (overlays-at (point))))
	overlay value
	(notfound t))
    (while (and notfound
		(setq overlay (car overlays)))
      (if (setq value (overlay-get overlay prop))
	  (setq notfound nil))
      (setq overlays (cdr overlays)))
    value))

(defun eudc-bob-make-button (label keymap &optional menu plist)
  "Create a button with LABEL.
Attach KEYMAP, MENU and properties from PLIST to a new overlay covering
LABEL."
  (let (overlay
	(p (point))
	prop val)
    (insert (or label ""))
    (put-text-property p (point) 'face 'bold)
    (setq overlay (make-overlay p (point)))
    (overlay-put overlay 'mouse-face 'highlight)
    (overlay-put overlay 'keymap keymap)
    (overlay-put overlay 'local-map keymap)
    (overlay-put overlay 'menu menu)
    (while plist
      (setq prop (car plist)
	    plist (cdr plist)
	    val (car plist)
	    plist (cdr plist))
      (overlay-put overlay prop val))))

(defun eudc-bob-display-jpeg (data inline)
  "Display the JPEG DATA at point.
If INLINE is non-nil, try to inline the image otherwise simply
display a button."
  (cond ((fboundp 'create-image)
	 (let* ((image (create-image data nil t))
		(props (list 'object-data data 'eudc-image image)))
	   (when (and inline (image-type-available-p 'jpeg))
	     (setq props (nconc (list 'display image) props)))
	   (eudc-bob-make-button "[Picture]"
				 eudc-bob-image-keymap
				 eudc-bob-image-menu
				 props)))))

(defun eudc-bob-toggle-inline-display ()
  "Toggle inline display of an image."
  (interactive)
  (when (display-graphic-p)
    (let* ((overlays (append (overlays-at (1- (point)))
			     (overlays-at (point))))
	   image)
      ;; Search overlay with an image.
      (while (and overlays (null image))
	(let ((prop (overlay-get (car overlays) 'eudc-image)))
	  (if (eq 'image (car-safe prop))
	      (setq image prop)
	    (setq overlays (cdr overlays)))))
      ;; Toggle that overlay's image display.
      (when overlays
	(let ((overlay (car overlays)))
	  (overlay-put overlay 'display
		       (if (overlay-get overlay 'display)
			   nil image)))))))

(defun eudc-bob-display-audio (data)
  "Display a button for audio DATA."
  (eudc-bob-make-button "[Audio Sound]"
			eudc-bob-sound-keymap
			eudc-bob-sound-menu
			(list 'duplicable t
                              'object-data data)))

(defun eudc-bob-display-generic-binary (data)
  "Display a button for unidentified binary DATA."
  (eudc-bob-make-button "[Binary Data]"
			eudc-bob-generic-keymap
			eudc-bob-generic-menu
			(list 'duplicable t
                              'object-data data)))

(defun eudc-bob-play-sound-at-point ()
  "Play the sound data contained in the button at point."
  (interactive)
  (let (sound)
    (if (null (setq sound (eudc-bob-get-overlay-prop 'object-data)))
	(error "No sound data available here")
      (unless (fboundp 'play-sound-internal)
	(error "Playing sounds not supported on this system"))
      (play-sound (list 'sound :data sound)))))

(defun eudc-bob-play-sound-at-mouse (event)
  "Play the sound data contained in the button where EVENT occurred."
  (interactive "e")
  (save-excursion
    (mouse-set-point event)
    (eudc-bob-play-sound-at-point)))

(defun eudc-bob-save-object (filename)
  "Save the object data of the button at point."
  (interactive "fWrite file: ")
  (let ((data (eudc-bob-get-overlay-prop 'object-data))
	(coding-system-for-write 'binary)) ;Inhibit EOL conversion.
    (write-region data nil filename)))

(defun eudc-bob-pipe-object-to-external-program (program)
  "Pipe the object data of the button at point to an external program."
  (interactive (list (completing-read "Viewer: " eudc-external-viewers)))
  (let ((data (eudc-bob-get-overlay-prop 'object-data))
	(viewer (assoc program eudc-external-viewers)))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert data)
      (let ((coding-system-for-write 'binary)) ;Inhibit EOL conversion
	(if viewer
	    (call-process-region (point-min) (point-max)
			         (car (cdr viewer))
			         (cdr (cdr viewer)))
	  (call-process-region (point-min) (point-max) program))))))

(defun eudc-bob-menu ()
  "Retrieve the menu attached to a binary object."
  (eudc-bob-get-overlay-prop 'menu))

(defun eudc-bob-popup-menu (event)
  "Pop-up a menu of EUDC multimedia commands."
  (interactive "@e")
  (run-hooks 'activate-menubar-hook)
  (mouse-set-point event)
  (popup-menu (eudc-bob-menu) event))

;; If the first arguments can be nil here, then these 3 can be
;; defconsts once more.
(easy-menu-define eudc-bob-generic-menu eudc-bob-generic-keymap
  "EUDC Binary Object Menu."
  eudc-bob-generic-menu)
(easy-menu-define eudc-bob-image-menu eudc-bob-image-keymap
  "EUDC Image Menu."
  eudc-bob-image-menu)
(easy-menu-define eudc-bob-sound-menu eudc-bob-sound-keymap
  "EUDC Sound Menu."
  eudc-bob-sound-menu)

;;;###autoload
(defun eudc-display-generic-binary (data)
  "Display a button for unidentified binary DATA."
  (eudc-bob-display-generic-binary data))

;;;###autoload
(defun eudc-display-url (url)
  "Display URL and make it clickable."
  (require 'browse-url)
  (eudc-bob-make-button url eudc-bob-url-keymap))

;;;###autoload
(defun eudc-display-mail (mail)
  "Display e-mail address and make it clickable."
  (require 'goto-addr)
  (eudc-bob-make-button mail eudc-bob-mail-keymap))

;;;###autoload
(defun eudc-display-sound (data)
  "Display a button to play the sound DATA."
  (eudc-bob-display-audio data))

;;;###autoload
(defun eudc-display-jpeg-inline (data)
  "Display the JPEG DATA inline at point if possible."
  (eudc-bob-display-jpeg data (display-graphic-p)))

;;;###autoload
(defun eudc-display-jpeg-as-button (data)
  "Display a button for the JPEG DATA."
  (eudc-bob-display-jpeg data nil))

(define-obsolete-function-alias 'eudc-bob-can-display-inline-images #'display-graphic-p "29.1")

;;; eudc-bob.el ends here
