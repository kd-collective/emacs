;;; pc-win.el --- setup support for `PC windows' (whatever that is)  -*- lexical-binding:t -*-

;; Copyright (C) 1994, 1996-1997, 1999, 2001-2025 Free Software
;; Foundation, Inc.

;; Author: Morten Welinder <terra@diku.dk>
;; Maintainer: emacs-devel@gnu.org

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

;; This file is preloaded into Emacs by loadup.el.  The functions in
;; this file are then called during startup from startup.el.  This
;; means that just loading this file should not have any side effects
;; besides defining functions and variables, and in particular should
;; NOT initialize any window systems.

;; The main entry points to this file's features are msdos-handle-args,
;; msdos-create-frame-with-faces, msdos-initialize-window-system,
;; terminal-init-internal.  The last one is not supposed to be called,
;; so it just errors out.

;;; Code:

(if (not (fboundp 'msdos-remember-default-colors))
    (error "%s: Loading pc-win.el but not compiled for MS-DOS"
	   invocation-name))

(declare-function msdos-remember-default-colors "msdos.c")
(declare-function w16-set-clipboard-data "w16select.c")
(declare-function w16-get-clipboard-data "w16select.c")
(declare-function msdos-setup-keyboard "internal" (frame))

;; This was copied from etc/rgb.txt, except that some values were changed
;; a bit to make them consistent with DOS console colors, and the RGB
;; values were scaled up to 16 bits, as `tty-color-define' requires.
;;;
;; The mapping between the 16 standard EGA/VGA colors and X color names
;; was done by running a Unix version of Emacs inside an X client and a
;; DJGPP-compiled Emacs on the same PC.  The names of X colors used to
;; define the pixel values are shown as comments to each color below.
;;;
;; If you want to change the RGB values, keep in mind that various pieces
;; of Emacs think that a color whose RGB values add up to less than 0.6 of
;; the values for WHITE (i.e. less than 117963) are ``dark'', otherwise the
;; color is ``light''; see `frame-set-background-mode' in lisp/faces.el for
;; an example.
(defvar msdos-color-values
  '(("black"          0     0     0     0)
    ("blue"           1     0     0 52480) ; MediumBlue
    ("green"          2  8704 35584  8704) ; ForestGreen
    ("cyan"           3     0 52736 53504) ; DarkTurquoise
    ("red"            4 45568  8704  8704) ; FireBrick
    ("magenta"        5 35584     0 35584) ; DarkMagenta
    ("brown"          6 40960 20992 11520) ; Sienna
    ("lightgray"      7 48640 48640 48640) ; Gray
    ("darkgray"       8 26112 26112 26112) ; Gray40
    ("lightblue"      9     0     0 65535) ; Blue
    ("lightgreen"    10     0 65535     0) ; Green
    ("lightcyan"     11     0 65535 65535) ; Cyan
    ("lightred"      12 65535     0     0) ; Red
    ("lightmagenta"  13 65535     0 65535) ; Magenta
    ("yellow"        14 65535 65535     0) ; Yellow
    ("white"         15 65535 65535 65535))
  "A list of MS-DOS console colors, their indices and 16-bit RGB values.")

;; ---------------------------------------------------------------------------
;; We want to delay setting frame parameters until the faces are setup
(defvar default-frame-alist nil)
;(modify-frame-parameters terminal-frame default-frame-alist)

(defun msdos-face-setup ()
  "Initial setup of faces for the MS-DOS display."
  (set-face-foreground 'bold "yellow")
  (set-face-foreground 'italic "red")
  (set-face-foreground 'bold-italic "lightred")
  (set-face-foreground 'underline "white")

  (make-face 'msdos-menu-active-face)
  (make-face 'msdos-menu-passive-face)
  (make-face 'msdos-menu-select-face)
  (set-face-foreground 'msdos-menu-active-face "white")
  (set-face-foreground 'msdos-menu-passive-face "lightgray")
  (set-face-background 'msdos-menu-active-face "blue")
  (set-face-background 'msdos-menu-passive-face "blue")
  (set-face-background 'msdos-menu-select-face "red"))

(defun msdos-handle-reverse-video (frame parameters)
  "Handle the reverse-video frame parameter on MS-DOS frames."
  (when (cdr (or (assq 'reverse parameters)
		 (assq 'reverse default-frame-alist)))
      (let* ((params (frame-parameters frame))
	     (fg (cdr (assq 'foreground-color params)))
	     (bg (cdr (assq 'background-color params))))
	(if (equal fg (cdr (assq 'mouse-color params)))
	    (modify-frame-parameters frame
				     (list (cons 'mouse-color bg))))
	(if (equal fg (cdr (assq 'cursor-color params)))
	    (modify-frame-parameters frame
				     (list (cons 'cursor-color bg)))))))

;; This must run after all the default colors are inserted into
;; tty-color-alist, since msdos-handle-reverse-video needs to know the
;; actual frame colors.
(defun msdos-setup-initial-frame ()
  (modify-frame-parameters terminal-frame default-frame-alist)
  ;; This remembers the screen colors after applying default-frame-alist,
  ;; so that all subsequent frames could begin with those colors.
  (msdos-remember-default-colors terminal-frame)
  (modify-frame-parameters terminal-frame initial-frame-alist)
  (msdos-handle-reverse-video terminal-frame
			      (frame-parameters terminal-frame))

  (frame-set-background-mode terminal-frame)
  (face-set-after-frame-default terminal-frame))

;; We create frames as if we were a terminal, but without invoking the
;; terminal-initialization function.  Also, our handling of reverse
;; video is slightly different.
(defun msdos-create-frame-with-faces (&optional parameters)
  "Create a frame on MS-DOS display.
Optional frame parameters PARAMETERS specify the frame parameters.
Parameters not specified by PARAMETERS are taken from
`default-frame-alist'.  If either PARAMETERS or `default-frame-alist'
contains a `reverse' parameter, handle that.  Value is the new frame
created."
  (let ((frame (make-terminal-frame parameters))
	success)
    (unwind-protect
	(with-selected-frame frame
	  (msdos-handle-reverse-video frame (frame-parameters frame))
          (unless (terminal-parameter frame 'terminal-initted)
            (set-terminal-parameter frame 'terminal-initted t))
	  (frame-set-background-mode frame)
	  (face-set-after-frame-default frame)
	  (setq success t))
      (unless success (delete-frame frame)))
    frame))

;; ---------------------------------------------------------------------------
;; More or less useful imitations of certain X-functions.  A lot of the
;; values returned are questionable, but usually only the form of the
;; returned value matters.  Also, by the way, recall that `ignore' is
;; a useful function for returning 'nil regardless of argument.

;; Note: Any re-definition in this file of a function that is defined
;; in C on other platforms, should either have a doc-string that
;; starts with "SKIP", or one that is identical to the C version,
;; but with the arglist signature at the end.  Otherwise
;; help-split-fundoc gets confused on other platforms.  (Bug#10783)

(defun x-list-fonts (_pattern &optional _face _frame _maximum width)
  "SKIP: real doc in xfaces.c."
  (if (or (null width) (and (numberp width) (= width 1)))
      (list "ms-dos")
    (list "no-such-font")))
(defun x-display-pixel-width (&optional frame)
  "SKIP: real doc in xfns.c."
  (frame-width frame))
(defun x-display-pixel-height (&optional frame)
  "SKIP: real doc in xfns.c."
  (frame-height frame))
(defun x-display-planes (&optional _frame)
  "SKIP: real doc in xfns.c."
  4) ;bg switched to 16 colors as well
(defun x-display-color-cells (&optional _frame)
  "SKIP: real doc in xfns.c."
  16)
(defun x-server-max-request-size (&optional _frame)
  "SKIP: real doc in xfns.c."
  1000000) ; ???
(defun x-server-vendor (&optional _frame)
  "SKIP: real doc in xfns.c."
  "GNU")
(defun x-server-version (&optional _frame)
  "SKIP: real doc in xfns.c."
  '(1 0 0))
(defun x-display-screens (&optional _frame)
  "SKIP: real doc in xfns.c."
  1)
(defun x-display-mm-height (&optional _frame)
  "SKIP: real doc in xfns.c."
  245) ; Guess the size of my...
(defun x-display-mm-width (&optional _frame)
  "SKIP: real doc in xfns.c."
  322)  ; ...monitor, EZ...
(defun x-display-backing-store (&optional _frame)
  "SKIP: real doc in xfns.c."
  'not-useful)
(defun x-display-visual-class (&optional _frame)
  "SKIP: real doc in xfns.c."
  'static-color)
(fset 'x-display-save-under 'ignore)
(fset 'x-get-resource 'ignore)

(defvar x-display-name "pc"
  "SKIP: real doc in common-win.el.")
(defvar x-colors (mapcar 'car msdos-color-values)
  "SKIP: real doc in common-win.el.")

;; From lisp/term/w32-win.el
;
;;;; Selections

;; gui-get-selection is used in select.el
(cl-defmethod gui-backend-get-selection (_selection-symbol _target-type
                                         &context (window-system pc))
  "Return the value of the current selection.
Consult the selection.  Treat empty strings as if they were unset."
  ;; Don't die if x-get-selection signals an error.
  (with-demoted-errors "w16-get-clipboard-data:%s"
    (w16-get-clipboard-data)))

(declare-function w16-selection-exists-p "w16select.c")
;; gui-selection-owner-p is used in simple.el.
(cl-defmethod gui-backend-selection-exists-p (selection
                                              &context (window-system pc))
  (w16-selection-exists-p selection))

(cl-defmethod gui-backend-selection-owner-p (selection
                                             &context (window-system pc))
  (w16-selection-owner-p selection))

(defun w16-selection-owner-p (_selection)
  ;; FIXME: Other systems don't obey select-enable-clipboard here.
  (if select-enable-clipboard
      (let ((text
             ;; Don't die if w16-get-clipboard-data signals an error.
             (with-demoted-errors "w16-get-clipboard-data: %S"
               (w16-get-clipboard-data))))
        ;; We consider ourselves the owner of the selection
        ;; if it does not exist, or exists and compares
        ;; equal with the last text we've put into the
        ;; Windows clipboard.
        ;; NOTE: that variable is actually the last text any program
        ;; (not just Emacs) has put into the windows clipboard (up
        ;; until the last time Emacs read or set the clipboard), so
        ;; it's not suitable for checking actual selection
        ;; ownership. This should not result in a bug for the current
        ;; uses of gui-backend-selection-owner however, since they
        ;; don't actually care about selection ownership, but about
        ;; the selected text having changed.
        (cond
         ((not text) t)
         ((equal text gui--last-selected-text-clipboard) text)
         (t nil)))))

;; gui-set-selection is used in gui-set-selection.
(declare-function w16-set-clipboard-data "w16select.c"
		  (string &optional ignored))
(cl-defmethod gui-backend-set-selection (selection value
                                         &context (window-system pc))
  (if (not value)
      (if (w16-selection-owner-p selection)
          t)
    ;; FIXME: Other systems don't obey
    ;; select-enable-clipboard here.
    (with-demoted-errors "w16-set-clipboard-data: %S"
      (w16-set-clipboard-data value))
    value))

;; From src/fontset.c:
(fset 'query-fontset 'ignore)

;; From lisp/term/x-win.el: make iconify-or-deiconify-frame a no-op.
(fset 'iconify-or-deiconify-frame 'ignore)

;; From lisp/frame.el
(fset 'set-frame-font 'ignore)
(fset 'set-mouse-color 'ignore)		; We cannot, I think.
(fset 'set-cursor-color 'ignore)	; Hardware determined by char under.
(fset 'set-border-color 'ignore)	; Not useful.

(defvar msdos-last-help-message nil
  "The last help message received via `show-help-function'.
This is used by `msdos-show-help'.")

(defvar msdos-previous-message nil
  "The content of the echo area before help echo was displayed.")

(defun msdos-show-help (help)
  "Function installed as `show-help-function' on MS-DOS frames."
  (when (and (not (window-minibuffer-p)) ;Don't overwrite minibuffer contents.
             (not cursor-in-echo-area)) ;Don't overwrite a prompt.
    (cond
     ((stringp help)
      (setq help (string-replace "\n" ", " help))
      (unless (or msdos-previous-message
		  (string-equal help (current-message))
		  (and (stringp msdos-last-help-message)
		       (string-equal msdos-last-help-message
				     (current-message))))
        (setq msdos-previous-message (current-message)))
      (setq msdos-last-help-message help)
      (let ((message-truncate-lines nil)
            (message-log-max nil))
        (message "%s" help)))
     ((stringp msdos-previous-message)
      (let ((message-log-max nil))
        (message "%s" msdos-previous-message)
        (setq msdos-previous-message nil)))
     (t
      (message nil)))))


;; Initialization.
;; ---------------------------------------------------------------------------
;; This function is run, by the tty method of `frame-creation-function'
;; (in faces.el), only for the initial frame (on each terminal, but we have
;; only one).
;; This works by setting the `terminal-initted' terminal parameter to
;; this function, the first time `frame-creation-function' is
;; called on that terminal.  `frame-creation-function' is called
;; directly from startup.el and also by `make-frame'.
;; `make-frame' should call our own `frame-creation-function' method instead
;; (see below) so if terminal-init-internal is called it means something is
;; _very_ wrong, because "internal" terminal emulator should not be
;; turned on if our window-system is not `pc'.  Therefore, the only
;; Right Thing for us to do here is scream bloody murder.
(defun terminal-init-internal ()
  "Terminal initialization function for the MS-DOS \"internal\" terminal.
Errors out because it is not supposed to be called, ever."
  (error "terminal-init-internal called for window-system `%s'"
	 (window-system)))

;; window-system-initialization is called by startup.el:command-line.
(cl-defmethod window-system-initialization (&context (window-system pc)
                                            &optional _display)
  "Initialization function for the `pc' \"window system\"."
  (or (eq (window-system) 'pc)
      (error
       "`msdos-initialize-window-system' called, but window-system is `%s'"
       (window-system)))
  ;; First, the keyboard.
  (msdos-setup-keyboard terminal-frame)	; see internal.el
  ;; Next, register the default colors.
  (let* ((colors msdos-color-values)
	 (color (car colors)))
    (tty-color-clear)
    (while colors
      (tty-color-define (car color) (cadr color) (cddr color))
      (setq colors (cdr colors) color (car colors))))
  ;; Modifying color mappings means realized faces don't
  ;; use the right colors, so clear them.
  (clear-face-cache)
  ;; Now set up some additional faces.
  (msdos-face-setup)
  ;; Set up the initial frame.
  (msdos-setup-initial-frame)
  ;; Help echo is displayed in the echo area.
  (setq show-help-function 'msdos-show-help)
  ;; We want to delay the codepage-related setup until after user's
  ;; .emacs is processed, because people might define their
  ;; `dos-codepage-setup-hook' there.
  (add-hook 'after-init-hook 'dos-codepage-setup)
  ;; In multibyte mode, we want unibyte buffers to be displayed
  ;; using the terminal coding system, so that they display
  ;; correctly on the DOS terminal; in unibyte mode we want to see
  ;; all 8-bit characters verbatim.  In both cases, we want the
  ;; entire range of 8-bit characters to arrive at our display code
  ;; verbatim.
  (standard-display-8bit 127 255)
  ;; We are fast enough to make this optimization unnecessary.
  (setq split-window-keep-point t)
  ;; Arrange for the kill and yank functions to set and check the
  ;; clipboard.
  (menu-bar-enable-clipboard)
  (run-hooks 'terminal-init-msdos-hook))

;; frame-creation-function is called by frame.el:make-frame.
(cl-defmethod frame-creation-function (params &context (window-system pc))
  (msdos-create-frame-with-faces params))

;; We don't need anything beyond tty-handle-args for handling
;; command-line argument; see startup.el.
(cl-defmethod handle-args-function (args &context (window-system pc))
  (tty-handle-args args))

;; ---------------------------------------------------------------------------

(provide 'pc-win)
(provide 'term/pc-win)

;;; pc-win.el ends here
