;;; jit-lock.el --- just-in-time fontification  -*- lexical-binding: t -*-

;; Copyright (C) 1998, 2000-2025 Free Software Foundation, Inc.

;; Author: Gerd Moellmann <gerd@gnu.org>
;; Keywords: faces files
;; Package: emacs

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

;; Just-in-time fontification, triggered by C redisplay code.

;;; Code:

;;; Customization.

(defgroup jit-lock nil
  "Font Lock support mode to fontify just-in-time."
  :version "21.1"
  :group 'font-lock)

(defcustom jit-lock-chunk-size 1500
  "Jit-lock asks to fontify chunks of at most this many characters at a time.

The actual size of the fontified chunk of text can be different,
depending on what the `fontification-functions' actually decide to do.

This variable controls both display-time and stealth fontifications.

The optimum value is a little over the typical number of buffer
characters which fit in a typical window."
  :type 'natnum)


(defcustom jit-lock-stealth-time nil
  "Time in seconds to wait before beginning stealth fontification.
Stealth fontification occurs if there is no input within this time.
If nil, stealth fontification is never performed.

The value of this variable is used when JIT Lock mode is turned on."
  :type '(choice (const :tag "never" nil)
		 (number :tag "seconds" :value 16)))


(defcustom jit-lock-stealth-nice 0.5
  "Time in seconds to pause between chunks of stealth fontification.
Each iteration of stealth fontification is separated by this amount of time,
thus reducing the demand that stealth fontification makes on the system.
If nil, means stealth fontification is never paused.
To reduce machine load during stealth fontification, at the cost of stealth
taking longer to fontify, you could increase the value of this variable.
See also `jit-lock-stealth-load'."
  :type '(choice (const :tag "never" nil)
		 (number :tag "seconds")))


(defcustom jit-lock-stealth-load
  (if (condition-case nil (load-average) (error)) 200)
  "Load in percentage above which stealth fontification is suspended.
Stealth fontification pauses when the system short-term load average (as
returned by the function `load-average' if supported) goes above this level,
thus reducing the demand that stealth fontification makes on the system.
If nil, means stealth fontification is never suspended.
To reduce machine load during stealth fontification, at the cost of stealth
taking longer to fontify, you could reduce the value of this variable.
See also `jit-lock-stealth-nice'."
  :type (if (condition-case nil (load-average) (error))
	    '(choice (const :tag "never" nil)
		     (integer :tag "load"))
	  '(const :format "%t: unsupported\n" nil)))


(defcustom jit-lock-stealth-verbose nil
  "If non-nil, means stealth fontification should show status messages."
  :type 'boolean)


(define-obsolete-variable-alias 'jit-lock-defer-contextually
  'jit-lock-contextually "30.1")
(defcustom jit-lock-contextually 'syntax-driven
  "If non-nil, fontification should be syntactically true.
If nil, refontification occurs only on lines that were modified.  This
means where modification on a line causes syntactic change on subsequent lines,
those subsequent lines are not refontified to reflect their new context.
If t, fontification occurs on those lines modified and all subsequent lines.
This means those subsequent lines are refontified to reflect their new
syntactic context, after `jit-lock-context-time' seconds.
If any other value, e.g., `syntax-driven', it means refontification of
subsequent lines to reflect their new syntactic context may or may not
occur after `jit-lock-context-time', depending on the font-lock
definitions of the buffer.  Specifically, if `font-lock-keywords-only'
is nil in a buffer, which generally means the syntactic fontification
is done using the buffer mode's syntax table, the syntactic
refontification will be triggered (because in that case font-lock
calls `jit-lock-register' to set up for syntactic refontification,
and sets the buffer-local value of `jit-lock-contextually' to t).

The value of this variable is used when JIT Lock mode is turned on."
  :type '(choice (const :tag "never" nil)
		 (const :tag "always" t)
		 (other :tag "syntax-driven" syntax-driven)))

(defcustom jit-lock-context-time 0.5
  "Idle time after which text is contextually refontified, if applicable."
  :type '(number :tag "seconds"))

(defcustom jit-lock-antiblink-grace 2
  "Delay after which to refontify unterminated strings and comments.
If nil, no grace period is given; unterminated strings and comments
are refontified immediately.  If a number, a newly created
unterminated string or comment is fontified only to the end of the
current line, after which fontification waits that many seconds of idle
time before refontifying the remaining lines.  When typing strings
and comments, the delay helps avoid unpleasant \"blinking\", between
string/comment and non-string/non-comment fontification."
  :type '(choice (const :tag "never" nil)
	         (number :tag "seconds"))
  :version "27.1")

(defcustom jit-lock-defer-time nil ;; 0.25
  "Idle time after which deferred fontification should take place.
If nil, fontification is not deferred.
If 0, then fontification is only deferred while there is input pending."
  :type '(choice (const :tag "never" nil)
	         (number :tag "seconds")))

;;; Variables that are not customizable.

(defvar-local jit-lock-mode nil
  "Non-nil means Just-in-time Lock mode is active.")

(defvar jit-lock-functions nil
  "Special hook run to do the actual fontification.
The functions are called with two arguments:
the START and END of the region to fontify.
Each function can return a list of the form (jit-lock-bounds BEG . END),
to indicate the bounds of the region it actually fontified;
JIT font-lock will use this information to optimize redisplay cycles.")

(defvar-local jit-lock-context-unfontify-pos nil
  "Consider text after this position as contextually unfontified.
If nil, contextual fontification is disabled.")

(defvar jit-lock-stealth-timer nil
  "Timer for stealth fontification in Just-in-time Lock mode.")
(defvar jit-lock-stealth-repeat-timer nil
  "Timer for repeated stealth fontification in Just-in-time Lock mode.")
(defvar jit-lock-context-timer nil
  "Timer for context fontification in Just-in-time Lock mode.")
(defvar jit-lock-defer-timer nil
  "Timer for deferred fontification in Just-in-time Lock mode.")

(defvar jit-lock-defer-buffers nil
  "List of buffers with pending deferred fontification.")
(defvar jit-lock-stealth-buffers nil
  "List of buffers that are being fontified stealthily.")

(defvar jit-lock--antiblink-grace-timer nil
  "Idle timer for fontifying unterminated string or comment, or nil.")
(defvar jit-lock--antiblink-line-beginning-position (make-marker)
  "Last line beginning position after last command (a marker).")
(defvar jit-lock--antiblink-string-or-comment nil
  "Non-nil if in string or comment after last command (a boolean).")

;;; JIT lock mode

(defun jit-lock-context--update ()
  (unless jit-lock--antiblink-grace-timer
    (jit-lock-context-fontify)))

(defun jit-lock-mode (arg)
  "Toggle Just-in-time Lock mode.
Turn Just-in-time Lock mode on if and only if ARG is non-nil.
Enable it automatically by customizing group `font-lock'.

When Just-in-time Lock mode is enabled, fontification is different in the
following ways:

- Demand-driven buffer fontification triggered by Emacs C code.
  This means initial fontification of the whole buffer does not occur.
  Instead, fontification occurs when necessary, such as when scrolling
  through the buffer would otherwise reveal unfontified areas.  This is
  useful if buffer fontification is too slow for large buffers.

- Stealthy buffer fontification if `jit-lock-stealth-time' is non-nil.
  This means remaining unfontified areas of buffers are fontified if Emacs has
  been idle for `jit-lock-stealth-time' seconds, while Emacs remains idle.
  This is useful if any buffer has any deferred fontification.

- Deferred context fontification if `jit-lock-contextually' is
  non-nil.  This means fontification updates the buffer corresponding to
  true syntactic context, after `jit-lock-context-time' seconds of Emacs
  idle time, while Emacs remains idle.  Otherwise, fontification occurs
  on modified lines only, and subsequent lines can remain fontified
  corresponding to previous syntactic contexts.  This is useful where
  strings or comments span lines.

Stealth fontification only occurs while the system remains unloaded.
If the system load rises above `jit-lock-stealth-load' percent, stealth
fontification is suspended.  Stealth fontification intensity is controlled via
the variable `jit-lock-stealth-nice'.

`jit-lock-mode' is not a regular minor mode, and it doesn't
follow the regular conventions to switch the functionality on or
off.  Instead, an ARG of nil will switch it off, and non-nil will
switch it on.

If you need to debug code run from jit-lock, see `jit-lock-debug-mode'."
  (setq jit-lock-mode arg)
  (cond
   ((and (buffer-base-buffer)
         jit-lock-mode)
    ;; We're in an indirect buffer, and we're turning the mode on.
    ;; This doesn't work because jit-lock relies on the `fontified'
    ;; text-property which is shared with the base buffer.
    (setq jit-lock-mode nil)
    (message "Not enabling jit-lock: it does not work in indirect buffer"))

   (jit-lock-mode ;; Turn Just-in-time Lock mode on.

    ;; Mark the buffer for refontification.
    (jit-lock-refontify)

    ;; Install an idle timer for stealth fontification.
    (when (and jit-lock-stealth-time (null jit-lock-stealth-timer))
      (setq jit-lock-stealth-timer
            (run-with-idle-timer jit-lock-stealth-time t
                                 #'jit-lock-stealth-fontify)))

    ;; Create, but do not activate, the idle timer for repeated
    ;; stealth fontification.
    (when (and jit-lock-stealth-time (null jit-lock-stealth-repeat-timer))
      (setq jit-lock-stealth-repeat-timer (timer-create))
      (timer-set-function jit-lock-stealth-repeat-timer
                          #'jit-lock-stealth-fontify '(t)))

    ;; Init deferred fontification timer.
    (when (and jit-lock-defer-time (null jit-lock-defer-timer))
      (setq jit-lock-defer-timer
            (run-with-idle-timer jit-lock-defer-time t
                                 #'jit-lock-deferred-fontify)))

    ;; Initialize contextual fontification if requested.
    (when (eq jit-lock-contextually t)
      (unless jit-lock-context-timer
        (setq jit-lock-context-timer
              (run-with-idle-timer jit-lock-context-time t #'jit-lock-context--update)))
      (add-hook 'post-command-hook #'jit-lock--antiblink-post-command nil t)
      (setq jit-lock-context-unfontify-pos
            (or jit-lock-context-unfontify-pos (point-max))))

    ;; Setup our hooks.
    (add-hook 'after-change-functions #'jit-lock-after-change nil t)
    (add-hook 'fontification-functions #'jit-lock-function nil t))

   ;; Turn Just-in-time Lock mode off.
   (t
    ;; Cancel our idle timers.
    (when (and (or jit-lock-stealth-timer jit-lock-defer-timer
                   jit-lock-context-timer)
               ;; Only if there's no other buffer using them.
               (not (catch 'found
                      (dolist (buf (buffer-list))
                        (with-current-buffer buf
                          (when jit-lock-mode (throw 'found t)))))))
      (when jit-lock-stealth-timer
        (cancel-timer jit-lock-stealth-timer)
        (setq jit-lock-stealth-timer nil))
      (when jit-lock-context-timer
        (cancel-timer jit-lock-context-timer)
        (setq jit-lock-context-timer nil))
      (when jit-lock-defer-timer
        (cancel-timer jit-lock-defer-timer)
        (setq jit-lock-defer-timer nil)))

    ;; Remove hooks.
    (remove-hook 'post-command-hook #'jit-lock--antiblink-post-command t)
    (remove-hook 'after-change-functions #'jit-lock-after-change t)
    (remove-hook 'fontification-functions #'jit-lock-function))))

(define-minor-mode jit-lock-debug-mode
  "Minor mode to help debug code run from jit-lock.

When this minor mode is enabled, jit-lock runs as little code as possible
during redisplay and moves the rest to a timer, where things
like `debug-on-error' and Edebug can be used."
  :global t
  (when jit-lock-defer-timer
    (cancel-timer jit-lock-defer-timer)
    (setq jit-lock-defer-timer nil))
  (when jit-lock-debug-mode
    (setq jit-lock-defer-timer
          (run-with-idle-timer 0 t #'jit-lock--debug-fontify))))

(defvar jit-lock--debug-fontifying nil)

(defun jit-lock--debug-fontify ()
  "Fontify what was deferred for debugging."
  (when (and (not jit-lock--debug-fontifying)
             jit-lock-defer-buffers (not memory-full))
    (let ((jit-lock--debug-fontifying t)
          (inhibit-debugger nil))       ;FIXME: Not sufficient!
      ;; Mark the deferred regions back to `fontified = nil'
      (dolist (buffer jit-lock-defer-buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            ;; (message "Jit-Debug %s" (buffer-name))
            (with-silent-modifications
                (let ((pos (point-min)))
                  (while
                      (progn
                        (when (eq (get-text-property pos 'fontified) 'defer)
                          (let ((beg pos)
                                (end (setq pos (next-single-property-change
                                                pos 'fontified
                                                nil (point-max)))))
                            (put-text-property beg end 'fontified nil)
                            (jit-lock-fontify-now beg end)))
                        (setq pos (next-single-property-change
                                   pos 'fontified)))))))))
      (setq jit-lock-defer-buffers nil))))

(defun jit-lock-register (fun &optional contextual)
  "Register FUN as a fontification function to be called in this buffer.
FUN will be called with two arguments START and END indicating the region
that needs to be (re)fontified.
If non-nil, CONTEXTUAL means that a contextual fontification would be useful.
FUN can return a list of the form (jit-lock-bounds BEG . END),
to indicate the bounds of the region it actually fontified; JIT
font-lock will use this information to optimize redisplay cycles."
  (add-hook 'jit-lock-functions fun nil t)
  (when (and contextual jit-lock-contextually)
    (setq-local jit-lock-contextually t))
  (jit-lock-mode t))

(defun jit-lock-unregister (fun)
  "Unregister FUN as a fontification function.
Only applies to the current buffer."
  (remove-hook 'jit-lock-functions fun t)
  (when (member jit-lock-functions '(nil '(t)))
    (jit-lock-mode nil)))

(defun jit-lock-refontify (&optional beg end)
  "Force refontification of the region BEG..END (default whole buffer)."
  (with-silent-modifications
   (save-restriction
     (widen)
     (put-text-property (or beg (point-min)) (or end (point-max))
			'fontified nil))))

;;; On demand fontification.

(defun jit-lock-function (start)
  "Fontify current buffer starting at position START.
This function is added to `fontification-functions' when `jit-lock-mode'
is active."
  (when (and jit-lock-mode (not memory-full))
    (if (not (and jit-lock-defer-timer
                  (or (not (eq jit-lock-defer-time 0))
                      (input-pending-p))))
	;; No deferral.
	(let* ((cend (min (point-max) (+ start jit-lock-chunk-size)))
	       (vend (next-single-property-change start 'invisible nil cend)))
	  ;; Presumably if we're called it means `start' is
	  ;; not at EOB (nor invisible) and hence (> vend start).
	  (jit-lock-fontify-now start vend))
      ;; Record the buffer for later fontification.
      (unless (memq (current-buffer) jit-lock-defer-buffers)
	(push (current-buffer) jit-lock-defer-buffers))
      ;; Mark the area as defer-fontified so that the redisplay engine
      ;; is happy and so that the idle timer can find the places to fontify.
      (with-silent-modifications
       (put-text-property start
			  (next-single-property-change
			   start 'fontified nil
			   (min (point-max) (+ start jit-lock-chunk-size)))
			  'fontified 'defer)))))

(defun jit-lock--run-functions (beg end)
  (let ((tight-beg nil) (tight-end nil)
        (loose-beg beg) (loose-end end))
    (run-hook-wrapped
     'jit-lock-functions
     (lambda (fun)
       (pcase-let*
           ((res (funcall fun beg end))
            (`(,this-beg . ,this-end)
             (if (eq (car-safe res) 'jit-lock-bounds)
                 (cdr res) (cons beg end))))
         ;; If all functions don't fontify the same region, we currently
         ;; just try to "still be correct".  But we could go further and for
         ;; the chunks of text that was fontified by some functions but not
         ;; all, we could add text-properties indicating which functions were
         ;; already run to avoid running them redundantly when we get to
         ;; those chunks.
         (setq tight-beg (max (or tight-beg (point-min)) this-beg))
         (setq tight-end (min (or tight-end (point-max)) this-end))
         (setq loose-beg (min loose-beg this-beg))
         (setq loose-end (max loose-end this-end))
         nil)))
    `(,(min tight-beg beg) ,(max tight-end end) ,loose-beg ,loose-end)))

(defun jit-lock-fontify-now (&optional start end)
  "Fontify current buffer from START to END.
Defaults to the whole buffer.  END can be out of bounds."
  (with-silent-modifications
   (save-excursion
     (unless start (setq start (point-min)))
     (setq end (if end (min end (point-max)) (point-max)))
     (let ((orig-start start) next)
       (save-match-data
	 ;; Fontify chunks beginning at START.  The end of a
	 ;; chunk is either `end', or the start of a region
	 ;; before `end' that has already been fontified.
	 (while (and start (< start end))
	   ;; Determine the end of this chunk.
	   (setq next (or (text-property-any start end 'fontified t)
			  end))

           ;; Avoid unnecessary work if the chunk is empty (bug#23278).
           (when (> next start)
             ;; Fontify the chunk, and mark it as fontified.
             ;; We mark it first, to make sure that we don't indefinitely
             ;; re-execute this fontification if an error occurs.
             (put-text-property start next 'fontified t)
             (pcase-let
                 ;; `tight' is the part we've fully refontified, and `loose'
                 ;; is the part we've partly refontified (some of the
                 ;; functions have refontified it but maybe not all).
                 ((`(,tight-beg ,tight-end ,loose-beg ,_loose-end)
                   (condition-case err
                       (jit-lock--run-functions start next)
                     ;; If the user quits (which shouldn't happen in normal
                     ;; on-the-fly jit-locking), make sure the fontification
                     ;; will be performed before displaying the block again.
                     (quit (put-text-property start next 'fontified nil)
                           (signal (car err) (cdr err))))))

               ;; In case we fontified more than requested, take
               ;; advantage of the good news.
               (when (or (< tight-beg start) (> tight-end next))
                 (put-text-property tight-beg tight-end 'fontified t))

               ;; Make sure the contextual refontification doesn't re-refontify
               ;; what's already been refontified.
               (when (and jit-lock-context-unfontify-pos
                          (< jit-lock-context-unfontify-pos tight-end)
                          (>= jit-lock-context-unfontify-pos tight-beg)
                          ;; Don't move boundary forward if we have to
                          ;; refontify previous text.  Otherwise, we risk moving
                          ;; it past the end of the multiline property and thus
                          ;; forget about this multiline region altogether.
                          (not (get-text-property tight-beg
                                                  'jit-lock-defer-multiline)))
                 (setq jit-lock-context-unfontify-pos tight-end))

               ;; The redisplay engine has already rendered the buffer up-to
               ;; `orig-start' and won't notice if the above jit-lock-functions
               ;; changed the appearance of any part of the buffer prior
               ;; to that.  So if `loose-beg' is before `orig-start', we need to
               ;; cause a new redisplay cycle after this one so that the changes
               ;; are properly reflected on screen.
               ;; To make such repeated redisplay happen less often, we can
               ;; eagerly extend the refontified region with
               ;; jit-lock-after-change-extend-region-functions.
               (when (< loose-beg orig-start)
                 (run-with-timer 0 nil #'jit-lock-force-redisplay
                                 (copy-marker loose-beg)
                                 (copy-marker orig-start)))

               ;; Skip to the end of the fully refontified part.
               (setq start tight-end)))
           ;; Find the start of the next chunk, if any.
           (setq start
                 (text-property-any start end 'fontified nil))))))))

(defun jit-lock-force-redisplay (start end)
  "Force the display engine to re-render START's buffer from START to END.
This applies to the buffer associated with marker START."
  (when (marker-buffer start)
    (with-current-buffer (marker-buffer start)
      (with-silent-modifications
       (when (> end (point-max))
         (setq end (point-max) start (min start end)))
       (when (< start (point-min))
         (setq start (point-min) end (max start end)))
       ;; Don't cause refontification (it's already been done), but just do
       ;; some random buffer change, so as to force redisplay.
       (put-text-property start end 'fontified nil)
       (put-text-property start end 'fontified t)))))

;;; Stealth fontification.

(defsubst jit-lock-stealth-chunk-start (around)
  "Return the start of the next chunk to fontify around position AROUND.
Value is nil if there is nothing more to fontify."
  (if (zerop (buffer-size))
      nil
    (let* ((next (text-property-not-all around (point-max) 'fontified t))
           (prev (previous-single-property-change around 'fontified))
           (prop (get-text-property (max (point-min) (1- around))
                                    'fontified))
           (start (cond
                   ((null prev)
                    ;; There is no property change between AROUND
                    ;; and the start of the buffer.  If PROP is
                    ;; non-nil, everything in front of AROUND is
                    ;; fontified, otherwise nothing is fontified.
                    (if (eq prop t)
                        nil
                      (max (point-min)
                           (- around (/ jit-lock-chunk-size 2)))))
                   ((eq prop t)
                    ;; PREV is the start of a region of fontified
                    ;; text containing AROUND.  Start fontifying a
                    ;; chunk size before the end of the unfontified
                    ;; region in front of that.
                    (max (or (previous-single-property-change prev 'fontified)
                             (point-min))
                         (- prev jit-lock-chunk-size)))
                   (t
                    ;; PREV is the start of a region of unfontified
                    ;; text containing AROUND.  Start at PREV or
                    ;; chunk size in front of AROUND, whichever is
                    ;; nearer.
                    (max prev (- around jit-lock-chunk-size)))))
           (result (cond ((null start) next)
                         ((null next) start)
                         ((< (- around start) (- next around)) start)
                         (t next))))
      result)))

(defun jit-lock-stealth-fontify (&optional repeat)
  "Fontify buffers stealthily.
This function is called repeatedly after Emacs has become idle for
`jit-lock-stealth-time' seconds.  Optional argument REPEAT is expected
non-nil in a repeated invocation of this function."
  ;; Cancel timer for repeated invocations.
  (unless repeat
    (cancel-timer jit-lock-stealth-repeat-timer))
  (unless (or executing-kbd-macro
	      memory-full
	      (window-minibuffer-p)
	      ;; For first invocation set up `jit-lock-stealth-buffers'.
	      ;; In repeated invocations it's already been set up.
	      (null (if repeat
			jit-lock-stealth-buffers
		      (setq jit-lock-stealth-buffers (buffer-list)))))
    (let ((buffer (car jit-lock-stealth-buffers))
	  (delay 0)
	  minibuffer-auto-raise
	  message-log-max
	  start)
      (if (and jit-lock-stealth-load
	       ;; load-average can return nil.  The w32 emulation does
	       ;; that during the first few dozens of seconds after
	       ;; startup.
	       (> (or (car (load-average)) 0) jit-lock-stealth-load))
	  ;; Wait a little if load is too high.
	  (setq delay jit-lock-stealth-time)
	(if (buffer-live-p buffer)
	    (with-current-buffer buffer
	      (if (and jit-lock-mode
		       (setq start (jit-lock-stealth-chunk-start (point))))
		  ;; Fontify one block of at most `jit-lock-chunk-size'
		  ;; characters.
		  (with-temp-message (if jit-lock-stealth-verbose
					 (concat "JIT stealth lock "
						 (buffer-name)))
		    (jit-lock-fontify-now start
					  (+ start jit-lock-chunk-size))
		    ;; Run again after `jit-lock-stealth-nice' seconds.
		    (setq delay (or jit-lock-stealth-nice 0)))
		;; Nothing to fontify here.  Remove this buffer from
		;; `jit-lock-stealth-buffers' and run again immediately.
		(setq jit-lock-stealth-buffers (cdr jit-lock-stealth-buffers))))
	  ;; Buffer is no longer live.  Remove it from
	  ;; `jit-lock-stealth-buffers' and run again immediately.
	  (setq jit-lock-stealth-buffers (cdr jit-lock-stealth-buffers))))
      ;; Call us again.
      (when jit-lock-stealth-buffers
	(timer-set-idle-time jit-lock-stealth-repeat-timer (current-idle-time))
	(timer-inc-time jit-lock-stealth-repeat-timer delay)
	(timer-activate-when-idle jit-lock-stealth-repeat-timer t)))))


;;; Deferred fontification.

(defun jit-lock-deferred-fontify ()
  "Fontify what was deferred."
  (when (and jit-lock-defer-buffers (not memory-full))
    ;; Mark the deferred regions back to `fontified = nil'
    (dolist (buffer jit-lock-defer-buffers)
      (when (buffer-live-p buffer)
	(with-current-buffer buffer
	  ;; (message "Jit-Defer %s" (buffer-name))
	  (with-silent-modifications
	   (let ((pos (point-min)))
	     (while
		 (progn
		   (when (eq (get-text-property pos 'fontified) 'defer)
		     (put-text-property
		      pos (setq pos (next-single-property-change
				     pos 'fontified nil (point-max)))
		      'fontified nil))
		   (setq pos (next-single-property-change
                              pos 'fontified)))))))))
    ;; Force fontification of the visible parts.
    (let ((buffers jit-lock-defer-buffers)
          (jit-lock-defer-timer nil))
      (setq jit-lock-defer-buffers nil)
      ;; (message "Jit-Defer Now")
      (unless (redisplay)                       ;FIXME: Should we `force'?
        (setq jit-lock-defer-buffers buffers))
      ;; (message "Jit-Defer Done")
      )))


(defun jit-lock-context-fontify ()
  "Refresh fontification to take new context into account."
  (unless memory-full
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
	(when jit-lock-context-unfontify-pos
	  ;; (message "Jit-Context %s" (buffer-name))
	  (save-restriction
            ;; Don't be blindsided by narrowing that starts in the middle
            ;; of a jit-lock-defer-multiline.
	    (widen)
	    (when (and (>= jit-lock-context-unfontify-pos (point-min))
		       (< jit-lock-context-unfontify-pos (point-max)))
	      ;; If we're in text that matches a complex multi-line
	      ;; font-lock pattern, make sure the whole text will be
	      ;; redisplayed eventually.
	      ;; Despite its name, we treat jit-lock-defer-multiline here
	      ;; rather than in jit-lock-defer since it has to do with multiple
	      ;; lines, i.e. with context.
	      (when (get-text-property jit-lock-context-unfontify-pos
				       'jit-lock-defer-multiline)
		(setq jit-lock-context-unfontify-pos
		      (or (previous-single-property-change
			   jit-lock-context-unfontify-pos
			   'jit-lock-defer-multiline)
			  (point-min))))
	      (with-silent-modifications
	       ;; Force contextual refontification.
	       (remove-text-properties
		jit-lock-context-unfontify-pos (point-max)
		'(fontified nil jit-lock-defer-multiline nil)))
	      (setq jit-lock-context-unfontify-pos (point-max)))))))))

(defvar jit-lock-start) (defvar jit-lock-end) ; Dynamically scoped variables.
(defvar jit-lock-after-change-extend-region-functions nil
  "Hook that can extend the text to refontify after a change.
This is run after every buffer change.  The functions are called with
the three arguments of `after-change-functions': START END OLD-LEN.
The extended region to refontify is returned indirectly by modifying
the variables `jit-lock-start' and `jit-lock-end'.

Note that extending the region this way is not strictly necessary, except
that the nature of the redisplay code tends to otherwise leave some of
the rehighlighted text displayed with the old highlight until the next
redisplay (see comment about repeated redisplay in `jit-lock-fontify-now').")

(defun jit-lock-after-change (start end old-len)
  "Mark the rest of the buffer as not fontified after a change.
Installed on `after-change-functions'.
START and END are the start and end of the changed text.  OLD-LEN
is the pre-change length.
This function ensures that lines following the change will be refontified
in case the syntax of those lines has changed.  Refontification
will take place when text is fontified stealthily."
  (when (and jit-lock-mode (not memory-full))
    (let ((jit-lock-start start)
          (jit-lock-end end))
      (with-silent-modifications
       (run-hook-with-args 'jit-lock-after-change-extend-region-functions
			   start end old-len)
       ;; Make sure we change at least one char (in case of deletions).
       (setq jit-lock-end (min (max jit-lock-end (1+ start)) (point-max)))
       ;; Request refontification.
       (save-restriction
	 (widen)
	 (put-text-property jit-lock-start jit-lock-end 'fontified nil)))
      ;; Mark the change for deferred contextual refontification.
      (when jit-lock-context-unfontify-pos
        (setq jit-lock-context-unfontify-pos
              ;; Here we use `start' because nothing guarantees that the
              ;; text between start and end will be otherwise refontified:
              ;; usually it will be refontified by virtue of being
              ;; displayed, but if it's outside of any displayed area in the
              ;; buffer, only jit-lock-context-* will re-fontify it.
              (min jit-lock-context-unfontify-pos jit-lock-start))))))

(defun jit-lock--antiblink-update ()
  (jit-lock-context-fontify)
  (setq jit-lock--antiblink-grace-timer nil))

(defun jit-lock--antiblink-post-command ()
  (let* ((new-l-b-p (copy-marker (syntax--lbp)))
         (l-b-p-2 (syntax--lbp 2))
         (same-line
          (and jit-lock-antiblink-grace
               (not (= new-l-b-p l-b-p-2))
               (eq (marker-buffer jit-lock--antiblink-line-beginning-position)
                   (current-buffer))
               (= new-l-b-p jit-lock--antiblink-line-beginning-position)))
         (new-s-o-c
          (and same-line
               (nth 8 (save-excursion (syntax-ppss l-b-p-2))))))
    (cond (;; Opened a new multiline string...
           (and same-line
                (null jit-lock--antiblink-string-or-comment) new-s-o-c)
           (setq jit-lock--antiblink-grace-timer
                 (run-with-idle-timer jit-lock-antiblink-grace nil #'jit-lock--antiblink-update)))
          (;; Closed an unterminated multiline string.
           (and same-line
                (null new-s-o-c) jit-lock--antiblink-string-or-comment)
           ;; Kill the grace timer, might already have run and died.
           ;; Don't refontify immediately: it adds an unreasonable
           ;; delay to a well-behaved operation.  Leave it for the
           ;; `jit-lock-context-timer' as usual.
           (when jit-lock--antiblink-grace-timer
             (cancel-timer jit-lock--antiblink-grace-timer)
             (setq jit-lock--antiblink-grace-timer nil)))
          (same-line
           ;; In same line, but no state change, leave everything as it was.
           )
          (t
           ;; Left the line somehow or customized feature away, etc.;
           ;; kill timer if running, resume normal operation.
           (when jit-lock--antiblink-grace-timer
             ;; Do refontify immediately, adding a small delay.  This
             ;; makes sense because it signals somehow that we are
             ;; leaving the unstable state.
             (jit-lock-context-fontify)
             (cancel-timer jit-lock--antiblink-grace-timer)
             (setq jit-lock--antiblink-grace-timer nil))))
    ;; Update variables (and release the marker).
    (set-marker jit-lock--antiblink-line-beginning-position nil)
    (setq jit-lock--antiblink-line-beginning-position new-l-b-p
          jit-lock--antiblink-string-or-comment new-s-o-c)))

(provide 'jit-lock)

;;; jit-lock.el ends here
