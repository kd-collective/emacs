;;; term.el --- general command interpreter in a window stuff -*- lexical-binding: t -*-

;; Copyright (C) 1988, 1990, 1992, 1994-1995, 2001-2025 Free Software
;; Foundation, Inc.

;; Author: Per Bothner <per@bothner.com>
;; Maintainer: Dan Nicolaescu <dann@ics.uci.edu>, Per Bothner <per@bothner.com>
;; Based on comint mode written by: Olin Shivers <shivers@cs.cmu.edu>
;; Keywords: processes

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

;; March 13 2001
;; Fixes for CJK support by Yong Lu <lyongu@yahoo.com>.

;; Dir/Hostname tracking and ANSI colorization by
;; Marco Melgazzi <marco@techie.com>.

;; To see what I've modified and where it came from search for '-mm'

;;; Commentary:

;; This file defines a general command-interpreter-in-a-buffer package
;; (term mode).  The idea is that you can build specific process-in-a-buffer
;; modes on top of term mode -- e.g., Lisp, shell, Scheme, T, soar, ....
;; This way, all these specific packages share a common base functionality,
;; and a common set of bindings, which makes them easier to use (and
;; saves code, implementation time, etc., etc.).

;; If, instead of `term', you call `ansi-term', you get multiple term
;; buffers, after every new call ansi-term opens a new
;; "*ansi-term*<xx>" window, where <xx> is, as usual, a number...

;; For hints on converting existing process modes (e.g., tex-mode,
;; background, dbx, gdb, kermit, prolog, telnet) to use term-mode
;; instead of shell-mode, see the notes at the end of this file.

;; Speed considerations and a few caveats
;; --------------------------------------
;;
;; While the message passing and the colorization surely introduce some
;; overhead this has became so small that IMHO it is surely outweighed by
;; the benefits you get but, as usual, YMMV.
;;
;; Important caveat, when deciding the cursor/'gray keys' keycodes I had to
;; make a choice: on my Linux box this choice allows me to run all the
;; ncurses applications without problems but make these keys
;; incomprehensible to all the cursesX programs.  Your mileage may vary so
;; you may consider changing the default 'emulation'.  Just search for this
;; piece of code and modify it as you like:
;;
;; ;; Which would be better:  "\e[A" or "\eOA"? readline accepts either.
;; ;; For my configuration it's definitely better \eOA but YMMV.  -mm
;; ;; For example: vi works with \eOA while elm wants \e[A ...
;; (defun term-send-up    () (interactive) (term-send-raw-string "\eOA"))
;; (defun term-send-down  () (interactive) (term-send-raw-string "\eOB"))
;; (defun term-send-right () (interactive) (term-send-raw-string "\eOC"))
;; (defun term-send-left  () (interactive) (term-send-raw-string "\eOD"))
;;
;;
;; IMPORTANT: additions & changes
;; ------------------------------
;;
;;  With this enhanced ansi-term.el you will get a reliable mechanism of
;; directory/username/host tracking: the only drawback is that you will
;; have to modify your shell start-up script.  It's worth it, believe me :).
;;
;; When you ssh/sudo/su and the account you access has a modified
;; startup script, you will be able to access the remote files as usual
;; with C-x C-f, if it's needed you will have to enter a password,
;; otherwise the file should get loaded straight away.
;;
;; This is useful even if you work only on one host: it often happens that,
;; for maintenance reasons, you have to edit files 'as root': before
;; patching term.el, I su-ed in a term.el buffer and used vi :), now I
;; simply do a C-x C-f and, via ange-ftp, the file is automatically loaded
;; 'as-root'.  (If you don't want to enter the root password every time you
;; can put it in your .netrc: note that this is -not- advisable if you're
;; connected to the internet or if somebody else works on your workstation!)
;;
;; If you use wu-ftpd you can use some of its features to avoid root ftp
;; access to the rest of the world: just put in /etc/ftphosts something like
;;
;; # Local access
;; allow	root		127.0.0.1
;;
;; # By default nobody can't do anything
;; deny	root		*
;;
;;             ----------------------------------------
;;
;;  With the variable term-buffer-maximum-size you can decide how many
;; scrollback lines to keep: its default is 8192.
;;
;;             ----------------------------------------
;;
;;
;;  ANSI colorization should work well.  Blink, is not supported.
;;  Currently it's mapped as bold.
;;
;;             ----------------------------------------
;;
;;  TODO:
;;
;;  - Add hooks to allow raw-mode keys to be configurable
;;  - Which keys are better ? \eOA or \e[A ?
;;
;;  ----------------------------------------------------------------
;;  You should/could have something like this in your .emacs to take
;;  full advantage of this package
;;
;;  (add-hook 'term-mode-hook
;;            (lambda ()
;;              (setq term-prompt-regexp "^[^#$%>\n]*[#$%>] *")
;;              (setq-local mouse-yank-at-point t)
;;              (setq-local transient-mark-mode nil)
;;              (auto-fill-mode -1)
;;              (setq tab-width 8)))
;;
;;             ----------------------------------------
;;
;;  If you want to use color ls the best setup is to have a different file
;; when you use eterm ( see above, mine is named .emacs_dircolors ).  This
;; is necessary because some terminals, rxvt for example, need non-ansi
;; hacks to work ( for example on my rxvt white is wired to fg, and to
;; obtain normal white I have to do bold-white :)
;;
;;             ----------------------------------------
;;
;;  # Configuration file for the color ls utility
;;  # This file goes in the /etc directory, and must be world readable.
;;  # You can copy this file to .dir_colors in your $HOME directory to
;;  # override the system defaults.
;;
;;  # COLOR needs one of these arguments: 'tty' colorizes output to ttys, but
;;  # not pipes.  'all' adds color characters to all output.  'none' shuts
;;  # colorization off.
;;  COLOR tty
;;  OPTIONS -F
;;
;;  # Below, there should be one TERM entry for each termtype that is
;;  # colorizable
;;  TERM eterm
;;
;;  # EIGHTBIT, followed by '1' for on, '0' for off.  (8-bit output)
;;  EIGHTBIT 1
;;
;;  # Below are the color init strings for the basic file types.  A color init
;;  # string consists of one or more of the following numeric codes:
;;  # Attribute codes:
;;  # 00=none 01=bold 04=underscore 05=blink 07=reverse 08=concealed
;;  # Text color codes:
;;  # 30=black 31=red 32=green 33=yellow 34=blue 35=magenta 36=cyan 37=white
;;  # Background color codes:
;;  # 40=black 41=red 42=green 43=yellow 44=blue 45=magenta 46=cyan 47=white
;;  NORMAL 00	# global default, although everything should be something.
;;  FILE 00 		# normal file
;;  DIR 00;37 	# directory
;;  LINK 00;36 	# symbolic link
;;  FIFO 00;37	# pipe
;;  SOCK 40;35	# socket
;;  BLK 33;01	# block device driver
;;  CHR 33;01 	# character device driver
;;
;;  # This is for files with execute permission:
;;  EXEC 00;32
;;
;;  # List any file extensions like '.gz' or '.tar' that you would like ls
;;  # to colorize below.  Put the extension, a space, and the color init
;;  # string.  (and any comments you want to add after a '#')
;;  .tar 01;33 # archives or compressed
;;  .tgz 01;33
;;  .arj 01;33
;;  .taz 01;33
;;  .lzh 01;33
;;  .zip 01;33
;;  .z   01;33
;;  .Z   01;33
;;  .gz  01;33
;;  .jpg 01;35 # image formats
;;  .gif 01;35
;;  .bmp 01;35
;;  .xbm 01;35
;;  .xpm 01;35
;;
;;             ----------------------------------------
;;
;; There are actually two methods for directory tracking, one
;; implemented in `term-command-hook' which sets the directory
;; according to an escape sequence of the form "\032/<directory>\n".
;; Some shells like bash will already send this escape sequence when
;; they detect they are running in Emacs.  This can be configured or
;; disabled on the Emacs side by setting `term-command-hook' to
;; a different function.
;;
;; The second method is in `term-handle-ansi-terminal-messages' which
;; sets user, host, and directory according to escape sequences of the
;; form "\033AnSiTc <directory>\n" (replace the "c" with "u" and "h"
;; for user and host, respectively).  If the user and host don't
;; match, it will set directory to a remote one, so it is important to
;; set user and host correctly first.  See the example bash
;; configuration below.
;;
;;             ----------------------------------------
;;
;;	# Set HOSTNAME if not already set.
;;	: ${HOSTNAME=$(uname -n)}
;;
;;	# su does not change this but I'd like it to
;;	USER=$(whoami)
;;
;;	# ...
;;
;;	case $TERM in
;;	    eterm*)
;;
;;		printf '%s\n' \
;;		 -------------------------------------------------------------- \
;;		 "Hello $USER" \
;;		 "Today is $(date)" \
;;		 "We are on $HOSTNAME running $(uname) under Emacs term mode" \
;;		 --------------------------------------------------------------
;;
;;		# The \033 stands for ESC.
;;		# There is a space between "AnSiT?" and $whatever.
;;		printf '\033AnSiTh %s\n' "$HOSTNAME"
;;		printf '\033AnSiTu %s\n' "$USER"
;;		printf '\033AnSiTc %s\n' "$PWD"
;;
;;		cd()    { command cd    "$@" && printf '\033AnSiTc %s\n' "$PWD"; }
;;		pushd() { command pushd "$@" && printf '\033AnSiTc %s\n' "$PWD"; }
;;		popd()  { command popd  "$@" && printf '\033AnSiTc %s\n' "$PWD"; }
;;
;;		# Use custom dircolors in term buffers.
;;		# eval $(dircolors $HOME/.emacs_dircolors)
;;	esac
;;
;;	# ...
;;
;; For troubleshooting in Bash, you can check the definition of the
;; custom functions with the "type" command.  e.g. "type cd".  If you
;; do not see the expected definition from the config below, then the
;; directory tracking will not work.


;; Brief Command Documentation:
;;============================================================================
;; Term Mode Commands: (common to all derived modes, like cmushell & cmulisp
;; mode)
;;
;; M-p     term-previous-input           Cycle backwards in input history
;; M-n     term-next-input               Cycle forwards
;; M-r     term-previous-matching-input  Previous input matching a regexp
;; M-s     term-next-matching-input      Next input that matches
;; return  term-send-input
;; C-c C-a term-bol                      Beginning of line; skip prompt.
;; C-d     term-delchar-or-maybe-eof     Delete char unless at end of buff.
;; C-c C-u term-kill-input               ^u
;; C-c C-w backward-kill-word            ^w
;; C-c C-c term-interrupt-subjob         ^c
;; C-c C-z term-stop-subjob              ^z
;; C-c C-\ term-quit-subjob              ^\
;; C-c C-o term-kill-output              Delete last batch of process output
;; C-c C-r term-show-output              Show last batch of process output
;; C-c C-h term-dynamic-list-input-ring  List input history
;;
;; Not bound by default in term-mode
;; term-send-invisible			Read a line without echo, and send to proc
;; (These are bound in shell-mode)
;; term-dynamic-complete		Complete filename at point.
;; term-dynamic-list-completions	List completions in help buffer.
;; term-replace-by-expanded-filename	Expand and complete filename at point;
;;					replace with expanded/completed name.
;; term-kill-subjob			No mercy.
;; term-show-maximum-output             Show as much output as possible.
;; term-continue-subjob                 Send CONT signal to buffer's process
;;					group.  Useful if you accidentally
;;					suspend your process (with C-c C-z).

;; term-mode-hook is the term mode hook.  Basically for your keybindings.
;; term-load-hook is run after loading in this package.

;;; Code:

;; This is passed to the inferior in the EMACS environment variable,
;; so it is important to increase it if there are protocol-relevant changes.
(defconst term-protocol-version "0.96")

(eval-when-compile
  (require 'ange-ftp)
  (require 'cl-lib))
(require 'comint) ; Password regexp.
(require 'ansi-color)
(require 'ansi-osc)
(require 'ehelp)
(require 'ring)
(require 'shell)

(defgroup term nil
  "General command interpreter in a window."
  :group 'processes)


;;; Buffer Local Variables:
;;============================================================================
;; Term mode buffer local variables:
;;     term-prompt-regexp    - string       term-bol uses to match prompt.
;;     term-delimiter-argument-list - list  For delimiters and arguments
;;     term-last-input-start - marker       Handy if inferior always echoes
;;     term-last-input-end   - marker       For term-kill-output command
;; For the input history mechanism:
(defvar term-input-ring-size 32 "Size of input history ring.")
;;     term-input-ring-size  - integer
;;     term-input-ring       - ring
;;     term-input-ring-index - number           ...
;;     term-input-autoexpand - symbol           ...
;;     term-input-ignoredups - boolean          ...
;;     term-last-input-match - string           ...
;;     term-dynamic-complete-functions - hook   For the completion mechanism
;;     term-completion-fignore - list           ...
;;     term-get-old-input    - function     Hooks for specific
;;     term-input-filter-functions - hook     process-in-a-buffer
;;     term-input-filter     - function         modes.
;;     term-input-send	- function
;;     term-scroll-to-bottom-on-output - symbol ...
;;     term-scroll-show-maximum-output - boolean...
(defvar term-height)                    ; Number of lines in window.
(defvar term-width)                     ; Number of columns in window.
(defvar term-home-marker) ; Marks the "home" position for cursor addressing.
(defvar term-saved-home-marker nil
  "When using alternate sub-buffer,
contains saved `term-home-marker' from original sub-buffer.")
(defvar term-start-line-column 0
  "(current-column) at start of screen line, or nil if unknown.")
(defvar term-current-column 0 "If non-nil, is cache for (current-column).")
(defvar term-current-row 0
  "Current vertical row (relative to home-marker) or nil if unknown.")
(defvar term-insert-mode nil)
(defvar term-vertical-motion)
(defvar term-auto-margins t
  "When non-nil, terminal will automatically wrap lines at the right margin.
This can be toggled by the application using DECAWM escape sequences.")

(defvar term-do-line-wrapping nil
  "Last character was a graphic in the last column.
If next char is graphic, first move one column right
\(and line warp) before displaying it.
This emulates (more or less) the behavior of xterm.")
(defvar term-kill-echo-list nil
  "A queue of strings whose echo we want suppressed.")
(defvar term-terminal-undecoded-bytes nil)
(defvar term-current-face 'term)
(defvar-local term-scroll-start 0
  "Top-most line (inclusive) of the scrolling region.
`term-scroll-start' must be in the range [0,term-height).  In addition, its
value has to be smaller than `term-scroll-end', i.e. one line scroll regions are
not allowed.")
(defvar-local term-scroll-end nil
  "Bottom-most line (inclusive) of the scrolling region.
`term-scroll-end' must be in the range [0,term-height).  In addition, its
value has to be greater than `term-scroll-start', i.e. one line scroll regions
are not allowed.")
(defvar term-pager-count nil
  "Number of lines before we need to page; if nil, paging is disabled.")
(defvar term-saved-cursor nil)
(define-obsolete-variable-alias 'term-command-hook
  'term-command-function "27.1")
(defvar term-command-function #'term-command-hook)
(defvar term-log-buffer nil)
(defvar term-scroll-with-delete nil
  "If t, forward scrolling should be implemented by delete to
top-most line(s); and if nil, scrolling should be implemented
by moving `term-home-marker'.  It is set to t if there is a
\(non-default) scroll-region OR the alternate buffer is used.")
(defvar term-pending-delete-marker) ; New user input in line mode
       ; needs to be deleted, because it gets echoed by the inferior.
       ; To reduce flicker, we defer the delete until the next output.
(defvar term-old-mode-map nil "Saves the old keymap when in char mode.")
(defvar term-old-mode-line-format) ; Saves old mode-line-format while paging.
(defvar term-pager-old-local-map nil "Saves old keymap while paging.")
(defvar term-pager-old-filter) ; Saved process-filter while paging.
(defvar-local term-line-mode-buffer-read-only nil
  "The `buffer-read-only' state to set in `term-line-mode'.")

(defvar term-prompt-regexp "^"
  "Regexp to recognize prompts in the inferior process.
Defaults to \"^\", the null string at BOL.

Good choices:
  Canonical Lisp: \"^[^> \\n]*>+:? *\" (Lucid, franz, kcl, T, cscheme, oaklisp)
  Lucid Common Lisp: \"^\\\\(>\\\\|\\\\(->\\\\)+\\\\) *\"
  franz: \"^\\\\(->\\\\|<[0-9]*>:\\\\) *\"
  kcl: \"^>+ *\"
  shell: \"^[^#$%>\\n]*[#$%>] *\"
  T: \"^>+ *\"

This is a good thing to set in mode hooks.")

(defvar term-delimiter-argument-list ()
  "List of characters to recognize as separate arguments in input.
Strings comprising a character in this list will separate the arguments
surrounding them, and also be regarded as arguments in their own right
\(unlike whitespace).  See `term-arguments'.
Defaults to the empty list.

For shells, a good value is (?\\| ?& ?< ?> ?\\( ?\\) ?\\;).

This is a good thing to set in mode hooks.")

(defcustom term-input-autoexpand nil
  "If non-nil, expand input command history references on completion.
This mirrors the optional behavior of tcsh (its autoexpand and histlit).

If the value is `input', then the expansion is seen on input.
If the value is `history', then the expansion is only when inserting
into the buffer's input ring.  See also `term-magic-space' and
`term-dynamic-complete'.

This variable is buffer-local."
  :type '(choice (const nil) (const t) (const input) (const history))
  :group 'term)

(defcustom term-input-ignoredups nil
  "If non-nil, don't add input matching the last on the input ring.
This mirrors the optional behavior of bash.

This variable is buffer-local."
  :type 'boolean
  :group 'term)

(defcustom term-input-ring-file-name nil
  "If non-nil, name of the file to read/write input history.
See also `term-read-input-ring' and `term-write-input-ring'.

This variable is buffer-local, and is a good thing to set in mode hooks."
  :type 'boolean
  :group 'term)

(defcustom term-char-mode-buffer-read-only t
  "If non-nil, only the process filter may modify the buffer in char mode.

A non-nil value makes the buffer read-only in `term-char-mode',
which prevents editing commands from making the buffer state
inconsistent with the state of the terminal understood by the
inferior process.  Only the process filter is allowed to make
changes to the buffer.

Customize this option to nil if you want the previous behavior."
  :version "26.1"
  :type 'boolean
  :group 'term)

(defcustom term-set-terminal-size nil
  "If non-nil, set the LINES and COLUMNS environment variables."
  :type 'boolean
  :version "28.1")

(defcustom term-char-mode-point-at-process-mark t
  "If non-nil, keep point at the process mark in char mode.

A non-nil value causes point to be moved to the current process
mark after each command in `term-char-mode' (provided that the
pre-command point position was also at the process mark).  This
prevents commands that move point from making the buffer state
inconsistent with the state of the terminal understood by the
inferior process.

Mouse events are not affected, so moving point and selecting text
is still possible in char mode via the mouse, after which other
commands can be invoked on the mouse-selected point or region,
until the process filter (or user) moves point to the process
mark once again.

Customize this option to nil if you want the previous behavior."
  :version "26.1"
  :type 'boolean
  :group 'term)

(defcustom term-scroll-to-bottom-on-output nil
  "Controls whether interpreter output causes window to scroll.
If nil, then do not scroll.  If t, scroll all windows showing buffer.
If `this', scroll only the selected window.
If `others', scroll only those that are not the selected window.

The default is nil.

See variable `term-scroll-show-maximum-output'.
This variable is buffer-local."
  :type '(choice (const :tag "Don't scroll" nil)
                 (const :tag "Scroll selected window only" this)
                 (const :tag "Scroll unselected windows" others)
                 ;; We also recognize `all', but we don't advertise it
                 ;; anymore.  (Bug#66071)
                 (other :tag "Scroll all windows" t))
  :group 'term)

(defcustom term-scroll-snap-to-bottom t
  "Control whether to keep the prompt at the bottom of the window.
If non-nil, when the prompt is visible within the window, then
scroll so that the prompt is on the bottom on any input or
output."
  :version "28.1"
  :type 'boolean)

(defcustom term-scroll-show-maximum-output nil
  "Controls how interpreter output causes window to scroll.
If non-nil, then show the maximum output when the window is scrolled.

See variable `term-scroll-to-bottom-on-output'.
This variable is buffer-local."
  :type 'boolean
  :group 'term)

(defcustom term-suppress-hard-newline nil
  "Non-nil means interpreter should not break long lines with newlines.
This means text can automatically reflow if the window is resized."
  :version "24.4"
  :type 'boolean
  :group 'term)
(make-obsolete-variable 'term-suppress-hard-newline nil
                        "27.1")

(defcustom term-clear-full-screen-programs t
  "Whether to clear contents of full-screen terminal programs after exit.
If non-nil, output of full-screen terminal programs is cleared after
exiting them.  Note however that a minority of such programs
don't send an appropriate escape sequence to the terminal before
exiting so their output isn't cleared regardless of this option."
  :version "29.1"
  :type 'boolean
  :group 'term)

;; Where gud-display-frame should put the debugging arrow.  This is
;; set by the marker-filter, which scans the debugger's output for
;; indications of the current pc.
(defvar term-pending-frame nil)

;;; Here are the per-interpreter hooks.
(defvar term-get-old-input (function term-get-old-input-default)
  "Function that submits old text in term mode.
This function is called when return is typed while the point is in old text.
It returns the text to be submitted as process input.  The default is
`term-get-old-input-default', which grabs the current line, and strips off
leading text matching `term-prompt-regexp'.")

(defvar term-dynamic-complete-functions
  '(term-replace-by-expanded-history term-dynamic-complete-filename)
  "List of functions called to perform completion.
Functions should return non-nil if completion was performed.
See also `term-dynamic-complete'.

This is a good thing to set in mode hooks.")

(defvar term-input-filter
  (lambda (str) (not (string-match "\\`\\s *\\'" str)))
  "Predicate for filtering additions to input history.
Only inputs answering true to this function are saved on the input
history list.  Default is to save anything that isn't all whitespace.")

(defvar term-input-filter-functions '()
  "Functions to call before input is sent to the process.
These functions get one argument, a string containing the text to send.

This variable is buffer-local.")

(defvar term-input-sender #'term-simple-send
  "Function to actually send to PROCESS the STRING submitted by user.
Usually this is just `term-simple-send', but if your mode needs to
massage the input string, this is your hook.  This is called from
the user command `term-send-input'.  `term-simple-send' just sends
the string plus a newline.")

(defcustom term-eol-on-send t
  "Non-nil means go to the end of the line before sending input.
See `term-send-input'."
  :type 'boolean
  :group 'term)

(defcustom term-mode-hook '()
  "Called upon entry into term mode.
This is run before the process is cranked up."
  :type 'hook
  :group 'term)

(defcustom term-exec-hook '()
  "Called each time a process is exec'd by `term-exec'.
This is called after the process is cranked up.  It is useful for things that
must be done each time a process is executed in a term mode buffer (e.g.,
`set-process-query-on-exit-flag').  In contrast, `term-mode-hook' is only
executed once, when the buffer is created."
  :type 'hook
  :group 'term)

(defvar term-osc-handlers nil
  "Terminal-specific OSC sequence handler function alist.

OSC (Operating System Command) is a category of ANSI escape sequence
used in terminal application to introduce custom commands.  Terminals
ignore unknown OSC sequences by default.  Handlers can be registered here
to add support for new OSC sequences to `term'.

Functions in this alist are passed matching valid OSC sequences as
they're sent to the terminal.

Valid OSC sequences are of the form
  ESC ] code ; text BEL
  ESC ] code ; text ESC \

Each entry has the form (CODE . FUNCTION), where CODE is the string that
appears before the semicolon.

FUNCTION is called with two arguments CODE and TEXT, with TEXT being the
content of the OSC sequence after the semicolon.  When the function is
called, the term buffer is active and with point and content valid at
the time the OSC sequence appears in the stream.

Any code not on this alist is further looked up in `ansi-osc-handlers',
which collects OSC handlers that can also work outside of a terminal
context.  For details, see `ansi-osc-apply-on-region'.")

(defvar term-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\ep" 'term-previous-input)
    (define-key map "\en" 'term-next-input)
    (define-key map "\er" 'term-previous-matching-input)
    (define-key map "\es" 'term-next-matching-input)
    (define-key map [?\A-\M-r]
      'term-previous-matching-input-from-input)
    (define-key map [?\A-\M-s] 'term-next-matching-input-from-input)
    (define-key map "\e\C-l" 'term-show-output)
    (define-key map "\C-m" 'term-send-input)
    (define-key map "\C-d" 'term-delchar-or-maybe-eof)
    (define-key map "\C-c\C-a" 'term-bol)
    (define-key map "\C-c\C-u" 'term-kill-input)
    (define-key map "\C-c\C-w" 'backward-kill-word)
    (define-key map "\C-c\C-c" 'term-interrupt-subjob)
    (define-key map "\C-c\C-z" 'term-stop-subjob)
    (define-key map "\C-c\C-\\" 'term-quit-subjob)
    (define-key map "\C-c\C-m" 'term-copy-old-input)
    (define-key map "\C-c\C-o" 'term-kill-output)
    (define-key map "\C-c\C-r" 'term-show-output)
    (define-key map "\C-c\C-e" 'term-show-maximum-output)
    (define-key map "\C-c\C-l" 'term-dynamic-list-input-ring)
    (define-key map "\C-c\C-n" 'term-next-prompt)
    (define-key map "\C-c\C-p" 'term-previous-prompt)
    (define-key map "\C-c\C-d" 'term-send-eof)
    (define-key map "\C-c\C-k" 'term-char-mode)
    (define-key map "\C-c\C-j" 'term-line-mode)
    (define-key map "\C-c\C-q" 'term-pager-toggle)
    ;; completion: (line mode only)
    (easy-menu-define nil map "Complete menu for Term mode."
      '("Complete"
        ["Complete Before Point" term-dynamic-complete t]
        ["Complete File Name" term-dynamic-complete-filename t]
        ["File Completion Listing" term-dynamic-list-filename-completions t]
        ["Expand File Name" term-replace-by-expanded-filename t]))
    ;; Input history: (line mode only)
    (easy-menu-define nil map "In/Out menu for Term mode."
      '("In/Out"
        ["Expand History Before Point" term-replace-by-expanded-history
         term-input-autoexpand]
        ["List Input History" term-dynamic-list-input-ring t]
        ["Previous Input" term-previous-input t]
        ["Next Input" term-next-input t]
        ["Previous Matching Current Input"
          term-previous-matching-input-from-input t]
        ["Next Matching Current Input" term-next-matching-input-from-input t]
        ["Previous Matching Input..." term-previous-matching-input t]
        ["Next Matching Input..." term-next-matching-input t]
        ["Backward Matching Input..." term-backward-matching-input t]
        ["Forward Matching Input..." term-forward-matching-input t]
        ["Copy Old Input" term-copy-old-input t]
        ["Kill Current Input" term-kill-input t]
        ["Show Current Output Group" term-show-output t]
        ["Show Maximum Output" term-show-maximum-output t]
        ["Backward Output Group" term-previous-prompt t]
        ["Forward Output Group" term-next-prompt t]
        ["Kill Current Output Group" term-kill-output t]))
    map)
  "Keymap for \"line mode\" in Term mode.
For custom keybindings purposes please note there is also `term-raw-map'")

(defvar term-escape-char nil
  "Escape character for char sub-mode of term mode.
Do not change it directly; use `term-set-escape-char' instead.")

(defvar term-pager-break-map
  (let ((map (make-keymap)))
    ;; (dotimes (i 128)
    ;;   (define-key map (make-string 1 i) 'term-send-raw))
    (define-key map "\e" (lookup-key (current-global-map) "\e"))
    (define-key map "\C-x" (lookup-key (current-global-map) "\C-x"))
    (define-key map "\C-u" (lookup-key (current-global-map) "\C-u"))
    (define-key map " " 'term-pager-page)
    (define-key map "\r" 'term-pager-line)
    (define-key map "?" 'term-pager-help)
    (define-key map "h" 'term-pager-help)
    (define-key map "b" 'term-pager-back-page)
    (define-key map "\177" 'term-pager-back-line)
    (define-key map "q" 'term-pager-discard)
    (define-key map "D" 'term-pager-disable)
    (define-key map "<" 'term-pager-bob)
    (define-key map ">" 'term-pager-eob)
    map)
  "Keymap used in Term pager mode.")

(defvar term-ptyp t
  "Non-nil if communications via pty; false if by pipe.  Buffer local.
This is to work around a bug in Emacs process signaling.")

(defvar term-last-input-match ""
  "Last string searched for by term input history search, for defaulting.
Buffer local variable.")

(defvar term-input-ring nil)
(defvar term-last-input-start)
(defvar term-last-input-end)
(defvar term-input-ring-index nil
  "Index of last matched history element.")
(defvar term-matching-input-from-input-string ""
  "Input previously used to match input history.")
; This argument to set-process-filter disables reading from the process.
(defvar term-pager-filter t)

(put 'term-input-ring 'permanent-local t)
(put 'term-input-ring-index 'permanent-local t)
(put 'term-input-autoexpand 'permanent-local t)
(put 'term-input-filter-functions 'permanent-local t)
(put 'term-scroll-to-bottom-on-output 'permanent-local t)
(put 'term-scroll-show-maximum-output 'permanent-local t)
(put 'term-ptyp 'permanent-local t)

(defmacro term-in-char-mode () '(eq (current-local-map) term-raw-map))
(defmacro term-in-line-mode () '(not (term-in-char-mode)))
;; True if currently doing PAGER handling.
(defmacro term-pager-enabled () 'term-pager-count)
(defmacro term-handling-pager () 'term-pager-old-local-map)
(defmacro term-using-alternate-sub-buffer () 'term-saved-home-marker)

;; Let's silence the byte-compiler -mm
(defvar term-ansi-at-host nil)
(defvar term-ansi-at-dir nil)
(defvar term-ansi-at-user nil)
(defvar term-ansi-at-message nil)
(defvar term-ansi-at-save-user nil)
(defvar term-ansi-at-save-pwd nil)
(defvar term-ansi-at-save-anon nil)
(defvar term-ansi-current-bold nil)
(defvar term-ansi-current-faint nil)
(defvar term-ansi-current-italic nil)
(defvar term-ansi-current-underline nil)
(defvar term-ansi-current-slow-blink nil)
(defvar term-ansi-current-fast-blink nil)
(defvar term-ansi-current-color nil)
(defvar term-ansi-face-already-done nil)
(defvar term-ansi-current-bg-color nil)
(defvar term-ansi-current-reverse nil)
(defvar term-ansi-current-invisible nil)

(make-obsolete-variable 'term-ansi-face-already-done
                        "it doesn't have any effect." "29.1")

;;; Faces
(defvar ansi-term-color-vector
  [term
   term-color-black
   term-color-red
   term-color-green
   term-color-yellow
   term-color-blue
   term-color-magenta
   term-color-cyan
   term-color-white
   term-color-bright-black
   term-color-bright-red
   term-color-bright-green
   term-color-bright-yellow
   term-color-bright-blue
   term-color-bright-magenta
   term-color-bright-cyan
   term-color-bright-white])

(defface term
  `((t :inherit default))
  "Default face to use in Term mode."
  :group 'term)

(defface term-bold
  '((t :inherit ansi-color-bold))
  "Default face to use for bold text."
  :group 'term
  :version "28.1")

(defface term-faint
  '((t :inherit ansi-color-faint))
  "Default face to use for faint text."
  :group 'term
  :version "29.1")

(defface term-italic
  '((t :inherit ansi-color-italic))
  "Default face to use for italic text."
  :group 'term
  :version "29.1")

(defface term-underline
  '((t :inherit ansi-color-underline))
  "Default face to use for underlined text."
  :group 'term
  :version "28.1")

(defface term-slow-blink
  '((t :inherit ansi-color-slow-blink))
  "Default face to use for slowly blinking text."
  :group 'term
  :version "29.1")

(defface term-fast-blink
  '((t :inherit ansi-color-fast-blink))
  "Default face to use for rapidly blinking text."
  :group 'term
  :version "29.1")

(defface term-color-black
  '((t :inherit ansi-color-black))
  "Face used to render black color code."
  :group 'term
  :version "28.1")

(defface term-color-red
  '((t :inherit ansi-color-red))
  "Face used to render red color code."
  :group 'term
  :version "28.1")

(defface term-color-green
  '((t :inherit ansi-color-green))
  "Face used to render green color code."
  :group 'term
  :version "28.1")

(defface term-color-yellow
  '((t :inherit ansi-color-yellow))
  "Face used to render yellow color code."
  :group 'term
  :version "28.1")

(defface term-color-blue
  '((t :inherit ansi-color-blue))
  "Face used to render blue color code."
  :group 'term
  :version "28.1")

(defface term-color-magenta
  '((t :inherit ansi-color-magenta))
  "Face used to render magenta color code."
  :group 'term
  :version "28.1")

(defface term-color-cyan
  '((t :inherit ansi-color-cyan))
  "Face used to render cyan color code."
  :group 'term
  :version "28.1")

(defface term-color-white
  '((t :inherit ansi-color-white))
  "Face used to render white color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-black
  '((t :inherit ansi-color-bright-black))
  "Face used to render bright black color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-red
  '((t :inherit ansi-color-bright-red))
  "Face used to render bright red color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-green
  '((t :inherit ansi-color-bright-green))
  "Face used to render bright green color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-yellow
  '((t :inherit ansi-color-bright-yellow))
  "Face used to render bright yellow color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-blue
  '((t :inherit ansi-color-bright-blue))
  "Face used to render bright blue color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-magenta
  '((t :inherit ansi-color-bright-magenta))
  "Face used to render bright magenta color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-cyan
  '((t :inherit ansi-color-bright-cyan))
  "Face used to render bright cyan color code."
  :group 'term
  :version "28.1")

(defface term-color-bright-white
  '((t :inherit ansi-color-bright-white))
  "Face used to render bright white color code."
  :group 'term
  :version "28.1")

(defcustom term-buffer-maximum-size 8192
  "The maximum size in lines for term buffers.
Term buffers are truncated from the top to be no greater than this number.
Notice that a setting of 0 means \"don't truncate anything\".  This variable
is buffer-local."
  :group 'term
  :type 'natnum
  :version "27.1")

(defcustom term-bind-function-keys nil
  "If nil, don't alter <f1>, <f2> and so on.
If non-nil, bind these keys in `term-mode' and send them to the
underlying shell."
  :type 'boolean
  :version "29.1")


;; Set up term-raw-map, etc.

(defvar term-raw-map
  (let* ((map (make-keymap))
         (esc-map (make-keymap))
         (i 0))
    (while (< i 128)
      (define-key map (make-string 1 i) 'term-send-raw)
      ;; Avoid O and [. They are used in escape sequences for various keys.
      (unless (or (eq i ?O) (eq i 91))
        (define-key esc-map (make-string 1 i) 'term-send-raw-meta))
      (setq i (1+ i)))
    (define-key map [remap self-insert-command] 'term-send-raw)
    (define-key map "\e" esc-map)

    ;; Added nearly all the 'gray keys' -mm

    (define-key map [mouse-2] 'term-mouse-paste)
    (define-key map [up] 'term-send-up)
    (define-key map [down] 'term-send-down)
    (define-key map [right] 'term-send-right)
    (define-key map [left] 'term-send-left)
    (define-key map [C-up] 'term-send-ctrl-up)
    (define-key map [C-down] 'term-send-ctrl-down)
    (define-key map [C-right] 'term-send-ctrl-right)
    (define-key map [C-left] 'term-send-ctrl-left)
    (define-key map [delete] 'term-send-del)
    (define-key map [deletechar] 'term-send-del)
    (define-key map [backspace] 'term-send-backspace)
    (define-key map [home] 'term-send-home)
    (define-key map [end] 'term-send-end)
    (define-key map [insert] 'term-send-insert)
    (define-key map [S-prior] 'scroll-down)
    (define-key map [S-next] 'scroll-up)
    (define-key map [S-insert] 'term-paste)
    (define-key map [prior] 'term-send-prior)
    (define-key map [next] 'term-send-next)
    (define-key map [xterm-paste] #'term--xterm-paste)
    (define-key map [?\C-/] #'term-send-C-_)
    (define-key map [?\C- ] #'term-send-C-@)
    (define-key map [?\C-\M-/] #'term-send-C-M-_)
    (define-key map [?\C-\M- ] #'term-send-C-M-@)

    (when term-bind-function-keys
      (dotimes (key 21)
        (keymap-set map (format "<f%d>" key) #'term-send-function-key)))
    map)
  "Keyboard map for sending characters directly to the inferior process.
For custom keybindings purposes please note there is also
`term-mode-map'")

(easy-menu-define term-terminal-menu
  (list term-mode-map term-raw-map term-pager-break-map)
  "Terminal menu for Term mode."
  '("Terminal"
    ["Line mode" term-line-mode :active (term-in-char-mode)
     :help "Switch to line (cooked) sub-mode of term mode"]
    ["Character mode" term-char-mode :active (term-in-line-mode)
     :help "Switch to char (raw) sub-mode of term mode"]
    ["Paging" term-pager-toggle :style toggle :selected term-pager-count
     :help "Toggle paging feature"]))

(defun term--update-term-menu (&optional force)
  (when (and (lookup-key term-mode-map [menu-bar terminal])
             (or force (frame-or-buffer-changed-p)))
    (let ((buffer-list (match-buffers '(derived-mode . term-mode))))
      (easy-menu-change
       nil
       "Terminal Buffers"
       (mapcar
        (lambda (buffer)
          (vector (format "%s (%s)" (buffer-name buffer)
                          (abbreviate-file-name
                           (buffer-local-value 'default-directory buffer)))
                  (lambda ()
                    (interactive)
                    (switch-to-buffer buffer))))
        buffer-list)
       nil
       term-terminal-menu))))

(easy-menu-define term-signals-menu
 (list term-mode-map term-raw-map term-pager-break-map)
  "Signals menu for Term mode."
  '("Signals"
    ["BREAK" term-interrupt-subjob :active t
     :help "Interrupt the current subjob"]
    ["STOP" term-stop-subjob :active t :help "Stop the current subjob"]
    ["CONT" term-continue-subjob :active t
     :help "Send CONT signal to process buffer's process group"]
    ["QUIT" term-quit-subjob :active t
     :help "Send quit signal to the current subjob"]
    ["KILL" term-kill-subjob :active t
     :help "Send kill signal to the current subjob"]
    ["EOF" term-send-eof :active t
     :help "Send an EOF to the current buffer's process"]))

(easy-menu-define term-pager-menu term-pager-break-map
  "Menu for Term pager mode."
  '("More pages?"
    ["1 page forwards" term-pager-page t]
    ["1 page backwards" term-pager-back-page t]
    ["1 line backwards" term-pager-back-line t]
    ["1 line forwards" term-pager-line t]
    ["Goto to beginning" term-pager-bob t]
    ["Goto to end" term-pager-eob t]
    ["Discard remaining output" term-pager-discard t]
    ["Disable paging" term-pager-toggle t]
    ["Help" term-pager-help t]))

(defvar term-raw-escape-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map 'Control-X-prefix)
    ;; Define standard bindings in term-raw-escape-map.
    (define-key map "\C-v" (lookup-key (current-global-map) "\C-v"))
    (define-key map "\C-u" (lookup-key (current-global-map) "\C-u"))
    (define-key map "\C-q" 'term-pager-toggle)
    ;; The keybinding for term-char-mode is needed by the menubar code.
    (define-key map "\C-k" 'term-char-mode)
    (define-key map "\C-j" 'term-line-mode)
    ;; It's convenient to have execute-extended-command here.
    (define-key map [?\M-x] 'execute-extended-command)
    map))

(defun term-set-escape-char (key)
  "Change `term-escape-char' and keymaps that depend on it."
  (when term-escape-char
    ;; Undo previous term-set-escape-char.
    (define-key term-raw-map term-escape-char 'term-send-raw)
    (define-key term-raw-escape-map term-escape-char nil t))
  (setq term-escape-char (if (vectorp key) key (vector key)))
  (define-key term-raw-map term-escape-char term-raw-escape-map)
  (define-key term-raw-escape-map term-escape-char 'term-send-raw))

(term-set-escape-char (or term-escape-char ?\C-c))


(put 'term-mode 'mode-class 'special)


;; Use this variable as a display table for `term-mode'.
(defvar term-display-table
  (let ((dt (or (copy-sequence standard-display-table)
		(make-display-table)))
        i)
    ;; avoid changing the display table for ^J
    (setq i 0)
    (while (< i 10)
      (aset dt i (vector i))
      (setq i (1+ i)))
    (setq i 11)
    (while (< i 32)
      (aset dt i (vector i))
      (setq i (1+ i)))
    (setq i 128)
    (while (< i 256)
      (aset dt i (vector i))
      (setq i (1+ i)))
    dt))

(defun term-ansi-reset ()
  (setq term-current-face 'term)
  (setq term-ansi-current-bold nil)
  (setq term-ansi-current-faint nil)
  (setq term-ansi-current-italic nil)
  (setq term-ansi-current-underline nil)
  (setq term-ansi-current-slow-blink nil)
  (setq term-ansi-current-fast-blink nil)
  (setq term-ansi-current-reverse nil)
  (setq term-ansi-current-color nil)
  (setq term-ansi-current-invisible nil)
  (setq term-ansi-current-bg-color nil))

(defvar touch-screen-display-keyboard)

(define-derived-mode term-mode fundamental-mode "Term"
  "Major mode for interacting with an inferior interpreter.
The interpreter name is same as buffer name, sans the asterisks.

There are two submodes: line mode and char mode.  By default, you are
in char mode.  In char sub-mode, each character (except
`term-escape-char') is sent immediately to the subprocess.
The escape character is equivalent to the usual meaning of \\`C-x'.

In line mode, you send a line of input at a time; use
\\[term-send-input] to send.

In line mode, this maintains an input history of size
`term-input-ring-size', and you can access it with the commands
\\[term-next-input], \\[term-previous-input], and
\\[term-dynamic-list-input-ring].  Input ring history expansion can be
achieved with the commands \\[term-replace-by-expanded-history] or
\\[term-magic-space].  Input ring expansion is controlled by the
variable `term-input-autoexpand', and addition is controlled by the
variable `term-input-ignoredups'.

Input to, and output from, the subprocess can cause the window to scroll to
the end of the buffer.  See variables `term-scroll-snap-to-bottom',
and `term-scroll-to-bottom-on-output'.

If you accidentally suspend your process, use \\[term-continue-subjob]
to continue it.

This mode can be customized to create specific modes for running
particular subprocesses.  This can be done by setting the hooks
`term-input-filter-functions', `term-input-filter',
`term-input-sender' and `term-get-old-input' to appropriate functions,
and the variable `term-prompt-regexp' to the appropriate regular
expression.

If you define custom keybindings, make sure to assign them to the
correct keymap (or to both): use `term-raw-map' in raw mode and
`term-mode-map' in line mode.

Commands in raw mode:

\\{term-raw-map}

Commands in line mode:

\\{term-mode-map}

Entry to this mode runs the hooks on `term-mode-hook'."
  :interactive nil
  ;; we do not want indent to sneak in any tabs
  (setq indent-tabs-mode nil)
  (setq buffer-display-table term-display-table)
  (setq-local term-home-marker (copy-marker 0))
  (setq-local term-height (floor (window-screen-lines)))
  (setq-local term-width (window-max-chars-per-line))
  (setq-local term-last-input-start (make-marker))
  (setq-local term-last-input-end (make-marker))
  (setq-local term-last-input-match "")
  (setq-local term-auto-margins t)

  ;; Always display the onscreen keyboard.
  (setq-local touch-screen-display-keyboard t)

  ;; These local variables are set to their local values:
  (make-local-variable 'term-saved-home-marker)
  (make-local-variable 'term-saved-cursor)
  (make-local-variable 'term-prompt-regexp)
  (make-local-variable 'term-input-ring-size)
  (make-local-variable 'term-input-ring)
  (make-local-variable 'term-input-ring-file-name)
  (make-local-variable 'term-input-ring-index)
  (unless term-input-ring
    (setq term-input-ring (make-ring term-input-ring-size)))

  ;; I'm not sure these saves are necessary but, since I
  ;; haven't tested the whole thing on a net connected machine with
  ;; a properly configured ange-ftp, I've decided to be conservative
  ;; and put them in. -mm

  (setq-local term-ansi-at-host (system-name))
  (setq-local term-ansi-at-dir default-directory)
  (setq-local term-ansi-at-message nil)

  ;; For user tracking purposes -mm
  (make-local-variable 'ange-ftp-default-user)
  (make-local-variable 'ange-ftp-default-password)
  (make-local-variable 'ange-ftp-generate-anonymous-password)

  ;; You may want to have different scroll-back sizes -mm
  (make-local-variable 'term-buffer-maximum-size)

  ;; Of course these have to be buffer-local -mm
  (make-local-variable 'term-ansi-current-bold)
  (make-local-variable 'term-ansi-current-color)
  (make-local-variable 'term-ansi-face-already-done)
  (make-local-variable 'term-ansi-current-bg-color)
  (make-local-variable 'term-ansi-current-underline)
  (make-local-variable 'term-ansi-current-reverse)
  (make-local-variable 'term-ansi-current-invisible)

  (make-local-variable 'term-terminal-undecoded-bytes)

  (make-local-variable 'term-do-line-wrapping)
  (make-local-variable 'term-kill-echo-list)
  (make-local-variable 'term-start-line-column)
  (make-local-variable 'term-current-column)
  (make-local-variable 'term-current-row)
  (make-local-variable 'term-log-buffer)
  (make-local-variable 'term-pager-count)
  (make-local-variable 'term-pager-old-local-map)
  (make-local-variable 'term-old-mode-map)
  (make-local-variable 'term-insert-mode)
  (make-local-variable 'term-completion-fignore)
  (make-local-variable 'term-get-old-input)
  (make-local-variable 'term-matching-input-from-input-string)
  (make-local-variable 'term-input-autoexpand)
  (make-local-variable 'term-input-ignoredups)
  (make-local-variable 'term-delimiter-argument-list)
  (make-local-variable 'term-input-filter)
  (make-local-variable 'term-input-sender)
  (make-local-variable 'term-eol-on-send)
  (make-local-variable 'term-scroll-to-bottom-on-output)
  (make-local-variable 'term-scroll-show-maximum-output)
  (make-local-variable 'term-ptyp)
  (setq-local term-vertical-motion 'vertical-motion)
  (setq-local term-pending-delete-marker (make-marker))
  (make-local-variable 'term-current-face)
  (term-ansi-reset)
  (add-hook 'menu-bar-update-hook 'term--update-term-menu)
  (setq-local term-pending-frame nil)
  ;; Cua-mode's keybindings interfere with the term keybindings, disable it.
  (setq-local cua-mode nil)

  (setq-local font-lock-defaults '(nil t))

  (add-function :filter-return
                (local 'filter-buffer-substring-function)
                #'term--filter-buffer-substring)
  (add-function :filter-return
                (local 'window-adjust-process-window-size-function)
                (lambda (size)
                  (when size
                    (term-reset-size (cdr size) (car size)))
                  size)
                '((name . term-maybe-reset-size)))

  (add-hook 'read-only-mode-hook #'term-line-mode-buffer-read-only-update nil t)

  (term--reset-scroll-region)

  (or term-input-ring
      (setq term-input-ring (make-ring term-input-ring-size)))
  (term-update-mode-line))

(defun term--remove-fake-newlines ()
  (goto-char (point-min))
  (let (fake-newline)
    (while (setq fake-newline (next-single-property-change (point)
                                                           'term-line-wrap))
      (goto-char fake-newline)
      (cl-assert (eq ?\n (char-after)))
      (let ((inhibit-read-only t))
        (delete-char 1)))))

(defun term--last-line ()
  (1- term-height))

(defun term--filter-buffer-substring (content)
  (with-temp-buffer
    (insert content)
    (term--remove-fake-newlines)
    (buffer-string)))

(defun term--unwrap-visible-long-lines (width)
  ;; Unwrap lines longer than width using fake newlines.  Only do it
  ;; for lines that are currently visible (i.e. following the home
  ;; marker).  Invisible lines don't have to be unwrapped since they
  ;; are unreachable using the cursor movement anyway.  Not having to
  ;; unwrap the entire buffer means the runtime of this function is
  ;; bounded by the size of the screen instead of the buffer size.

  (save-excursion
    ;; We will just assume that our accounting for the home marker is
    ;; correct, i.e. programs will not try to reach any position
    ;; earlier than this marker.
    (goto-char term-home-marker)

    (move-to-column width)
    (while (not (eobp))
      (if (eolp)
          (forward-char)
        (let ((inhibit-read-only t))
          (term-unwrap-line)))
      (move-to-column width))))

(defun term-reset-size (height width)
  (when (or (/= height term-height)
            (/= width term-width))
    ;; Delete all newlines used for wrapping
    (when (/= width term-width)
      (save-excursion
        (term--remove-fake-newlines)))
    (let ((point (point))
          (home-marker (marker-position term-home-marker)))
      (setq term-height height)
      (setq term-width width)
      (setq term-start-line-column nil)
      (setq term-current-row nil)
      (setq term-current-column nil)
      (term--reset-scroll-region)
      ;; `term-set-scroll-region' causes these to be set, we have to
      ;; clear them again since we're changing point (Bug#30544).
      (term--unwrap-visible-long-lines width)
      (setq term-start-line-column nil)
      (setq term-current-row nil)
      (setq term-current-column nil)
      (goto-char point)

      (when (term-using-alternate-sub-buffer)
        (term-handle-deferred-scroll)
        ;; When using an alternative sub-buffer, the home marker should
        ;; not move forward.  Bring it back by deleting text in front of
        ;; it.
        (when (> term-home-marker home-marker)
          (let ((inhibit-read-only t))
            (delete-region home-marker term-home-marker)))))))

;; Recursive routine used to check if any string in term-kill-echo-list
;; matches part of the buffer before point.
;; If so, delete that matched part of the buffer - this suppresses echo.
;; Also, remove that string from the term-kill-echo-list.
;; We *also* remove any older string on the list, as a sanity measure,
;; in case something gets out of sync.  (Except for type-ahead, there
;; should only be one element in the list.)

(defun term-check-kill-echo-list ()
  (let ((cur term-kill-echo-list) (found nil) (save-point (point)))
    (unwind-protect
	(progn
	  (end-of-line)
	  (while cur
	    (let* ((str (car cur)) (len (length str)) (start (- (point) len)))
	      (if (and (>= start (point-min))
		       (string= str (buffer-substring start (point))))
		  (progn (delete-char (- len))
			 (setq term-kill-echo-list (cdr cur))
			 (setq term-current-column nil)
			 (setq term-current-row nil)
			 (setq term-start-line-column nil)
			 (setq cur nil found t))
		(setq cur (cdr cur))))))
      (when (not found)
	(goto-char save-point)))
    found))

(defun term-send-raw-string (chars)
  (deactivate-mark)
  (let ((proc (get-buffer-process (current-buffer))))
    (if (not proc)
	(error "Current buffer has no process")
      ;; Note that (term-current-row) must be called *after*
      ;; (point) has been updated to (process-mark proc).
      (goto-char (process-mark proc))
      (when (term-pager-enabled)
	(setq term-pager-count (term-current-row)))
      (process-send-string proc chars))))

(defun term-send-raw ()
  "Send last typed character to the terminal-emulator without any interpretation."
  (interactive)
  (let ((keys (this-command-keys)))
    (term-send-raw-string (string (aref keys (1- (length keys)))))))

(defun term-send-raw-meta ()
  (interactive)
  (let ((char last-input-event))
    (when (symbolp char)
      ;; Convert `return' to C-m, etc.
      (let ((tmp (get char 'event-symbol-elements)))
	(if tmp (setq char (car tmp)))
	(and (symbolp char)
	     (setq tmp (get char 'ascii-character))
	     (setq char tmp))))
    (when (numberp char)
      (let ((base (event-basic-type char))
	    (mods (delq 'meta (event-modifiers char))))
	(if (memq 'control mods)
	    (setq mods (delq 'shift mods)))
	(term-send-raw-string
	 (format "\e%c"
		 (event-convert-list (append mods (list base)))))))))

(defun term-mouse-paste (click)
  "Insert the primary selection at the position clicked on."
  (interactive "e")
  ;; Give temporary modes such as isearch a chance to turn off.
  (run-hooks 'mouse-leave-buffer-hook)
  (mouse-set-point click)
  ;; As we have moved point, bind `select-active-regions' to prevent
  ;; the `deactivate-mark' call in `term-send-raw-string' from
  ;; changing the primary selection (resulting in consecutive calls to
  ;; `term-mouse-paste' each sending different text). (bug#58608).
  ;; FIXME: Why does this command change point at all?
  (let ((select-active-regions nil))
    (term-send-raw-string (gui-get-primary-selection))))

(defun term-paste ()
  "Insert the last stretch of killed text at point."
  (interactive)
   (term-send-raw-string (current-kill 0)))

(defun term--xterm-paste (event)
  "Insert the text pasted in an XTerm bracketed paste operation."
  (interactive "e")
  (unless (eq (car-safe event) 'xterm-paste)
    (error "term--xterm-paste must be found to xterm-paste event"))
  (let ((str (nth 1 event)))
    (unless (stringp str)
      (error "term--xterm-paste provided event does not contain paste text"))
    (term-send-raw-string str)))

(declare-function xterm--pasted-text "term/xterm" ())

;; Which would be better:  "\e[A" or "\eOA"? readline accepts either.
;; For my configuration it's definitely better \eOA but YMMV. -mm
;; For example: vi works with \eOA while elm wants \e[A ...
;; (terminfo: kcuu1, kcud1, kcuf1, kcub1, khome, kend, kpp, knp, kdch1, kbs)
(defun term-send-up    () (interactive) (term-send-raw-string "\eOA"))
(defun term-send-down  () (interactive) (term-send-raw-string "\eOB"))
(defun term-send-right () (interactive) (term-send-raw-string "\eOC"))
(defun term-send-left  () (interactive) (term-send-raw-string "\eOD"))
(defun term-send-ctrl-up    () (interactive) (term-send-raw-string "\e[1;5A"))
(defun term-send-ctrl-down  () (interactive) (term-send-raw-string "\e[1;5B"))
(defun term-send-ctrl-right () (interactive) (term-send-raw-string "\e[1;5C"))
(defun term-send-ctrl-left  () (interactive) (term-send-raw-string "\e[1;5D"))
(defun term-send-home  () (interactive) (term-send-raw-string "\e[1~"))
(defun term-send-insert() (interactive) (term-send-raw-string "\e[2~"))
(defun term-send-end   () (interactive) (term-send-raw-string "\e[4~"))
(defun term-send-prior () (interactive) (term-send-raw-string "\e[5~"))
(defun term-send-next  () (interactive) (term-send-raw-string "\e[6~"))
(defun term-send-del   () (interactive) (term-send-raw-string "\e[3~"))
(defun term-send-backspace  () (interactive) (term-send-raw-string "\C-?"))
(defun term-send-C-_  () (interactive) (term-send-raw-string "\C-_"))
(defun term-send-C-@  () (interactive) (term-send-raw-string "\C-@"))
(defun term-send-C-M-_  () (interactive) (term-send-raw-string "\e\C-_"))
(defun term-send-C-M-@  () (interactive) (term-send-raw-string "\e\C-@"))

(defun term-send-function-key ()
  "If bound to a function key, this will send that key to the underlying shell."
  (interactive)
  (let ((key (this-command-keys-vector)))
    (when (and (= (length key) 1)
               (symbolp (elt key 0)))
      (let ((name (symbol-name (elt key 0))))
        (when (string-match "\\`f\\([0-9]+\\)\\'" name)
          (let* ((num (string-to-number (match-string 1 name)))
                 (ansi
                  (cond
                   ((<= num 5) (+ num 10))
                   ((<= num 10) (+ num 11))
                   ((<= num 14) (+ num 12))
                   ((<= num 16) (+ num 13))
                   ((<= num 20) (+ num 14)))))
            (when ansi
              (term-send-raw-string (format "\e[%d~" ansi)))))))))


(defun term-char-mode ()
  "Switch to char (\"raw\") sub-mode of term mode.
Each character you type is sent directly to the inferior without
intervention from Emacs, except for the escape character (usually \\`C-c')."
  (interactive)
  ;; FIXME: Emit message? Cfr ilisp-raw-message
  (when (term-in-line-mode)
    (setq term-old-mode-map (current-local-map))
    (use-local-map term-raw-map)

    ;; Don't allow changes to the buffer or to point which are not
    ;; caused by the process filter.
    (when term-char-mode-buffer-read-only
      (setq buffer-read-only t))
    (add-hook 'pre-command-hook #'term-set-goto-process-mark nil t)
    (add-hook 'post-command-hook #'term-goto-process-mark-maybe nil t)

    ;; Send existing partial line to inferior (without newline).
    (let ((pmark (process-mark (get-buffer-process (current-buffer)))))
      (when (> (point) pmark)
	(unwind-protect
	    (progn
	      (add-function :override (local 'term-input-sender) #'term-send-string)
	      (end-of-line)
	      (term-send-input))
	  (remove-function (local 'term-input-sender) #'term-send-string))))
    (term-update-mode-line)))

(defun term-line-mode  ()
  "Switch to line (\"cooked\") sub-mode of term mode.
This means that Emacs editing commands work as normally, until
you type \\[term-send-input] which sends the current line to the inferior."
  (interactive)
  (when (term-in-char-mode)
    (when term-char-mode-buffer-read-only
      (setq buffer-read-only term-line-mode-buffer-read-only))
    (remove-hook 'pre-command-hook #'term-set-goto-process-mark t)
    (remove-hook 'post-command-hook #'term-goto-process-mark-maybe t)
    (use-local-map term-old-mode-map)
    (term-update-mode-line)))

(defun term-line-mode-buffer-read-only-update ()
  "Update the user-set state of `buffer-read-only' in `term-line-mode'.

Called as a buffer-local `read-only-mode-hook' function."
  (when (term-in-line-mode)
    (setq term-line-mode-buffer-read-only buffer-read-only)))

(defun term-update-mode-line ()
  (let ((term-mode
         (if (term-in-char-mode)
             (propertize "char"
                         'help-echo "mouse-1: Switch to line mode"
                         'mouse-face 'mode-line-highlight
                         'local-map
                         '(keymap
                           (mode-line keymap (down-mouse-1 . term-line-mode))))
           (propertize "line"
                       'help-echo "mouse-1: Switch to char mode"
                       'mouse-face 'mode-line-highlight
                       'local-map
                       '(keymap
                         (mode-line keymap (down-mouse-1 . term-char-mode))))))
        (term-page
         (when (term-pager-enabled)
           (concat " "
                   (propertize
                    "page"
                    'help-echo "mouse-1: Disable paging"
                    'mouse-face 'mode-line-highlight
                    'local-map
                    '(keymap
                      (mode-line keymap (down-mouse-1 .
                                                      term-pager-toggle)))))))
        (serial-item-speed)
        (serial-item-config)
        (proc (get-buffer-process (current-buffer))))
    (when (and (term-check-proc (current-buffer))
               (equal (process-type nil) 'serial))
      (let ((temp (serial-speed)))
        (setq serial-item-speed
            `(:propertize
              ,(or (and temp (format " %d" temp)) "")
              help-echo "mouse-1: Change the speed of the serial port"
              mouse-face mode-line-highlight
              local-map (keymap (mode-line keymap
                                (down-mouse-1 . serial-mode-line-speed-menu-1))))))
      (let ((temp (process-contact proc :summary)))
        (setq serial-item-config
              `(:propertize
                ,(or (and temp (format " %s" temp)) "")
                help-echo "mouse-1: Change the configuration of the serial port"
                mouse-face mode-line-highlight
                local-map (keymap (mode-line keymap
                           (down-mouse-1 . serial-mode-line-config-menu-1)))))))
    (setq mode-line-process
          (list ": " term-mode term-page
                serial-item-speed
                serial-item-config
                " %s")))
  (force-mode-line-update))

(defun term-check-proc (buffer)
  "Non-nil if there is a process associated w/buffer BUFFER, and it is alive.
BUFFER can be either a buffer or the name of one."
  (let ((proc (get-buffer-process buffer)))
    (and proc (memq (process-status proc) '(run stop open listen connect)))))

;;;###autoload
(defun make-term (name program &optional startfile &rest switches)
"Make a term process NAME in a buffer, running PROGRAM.
The name of the buffer is made by surrounding NAME with `*'s.
If there is already a running process in that buffer, it is not restarted.
Optional third arg STARTFILE is the name of a file to send the contents of to
the process.  Any more args are arguments to PROGRAM."
  (let ((buffer (get-buffer-create (concat "*" name "*"))))
    ;; If no process, or nuked process, crank up a new one and put buffer in
    ;; term mode.  Otherwise, leave buffer and existing process alone.
    (cond ((not (term-check-proc buffer))
	   (with-current-buffer buffer
	     (term-mode)) ; Install local vars, mode, keymap, ...
	   (term-exec buffer name program startfile switches)))
    buffer))

;;;###autoload
(defun term (program)
  "Start a terminal-emulator in a new buffer.
The buffer is in Term mode; see `term-mode' for the
commands to use in that buffer.

\\<term-raw-map>Type \\[switch-to-buffer] to switch to another buffer."
  (interactive (list (read-shell-command "Run program: "
					 (or explicit-shell-file-name
					     (getenv "ESHELL")
					     shell-file-name))))
  (let ((prog (split-string-shell-command program)))
    (set-buffer (apply #'make-term "terminal" (car prog) nil (cdr prog))))
  (term-char-mode)
  (pop-to-buffer-same-window "*terminal*"))

(defun term-exec (buffer name command startfile switches)
  "Start up a process in buffer for term modes.
Blasts any old process running in the buffer.  Doesn't set the buffer mode.
You can use this to cheaply run a series of processes in the same term
buffer.  The hook `term-exec-hook' is run after each exec."
  (with-current-buffer buffer
    (let ((proc (get-buffer-process buffer))) ; Blast any old process.
      (when proc (delete-process proc)))
    ;; Crank up a new process
    (let ((proc (term-exec-1 name buffer command switches)))
      (setq-local term-ptyp process-connection-type) ; t if pty, nil if pipe.
      ;; Jump to the end, and set the process mark.
      (goto-char (point-max))
      (set-marker (process-mark proc) (point))
      (set-process-filter proc #'term-emulate-terminal)
      (set-process-sentinel proc #'term-sentinel)
      ;; Feed it the startfile.
      (when startfile
        ;;This is guaranteed to wait long enough
        ;;but has bad results if the term does not prompt at all
        ;;	     (while (= size (buffer-size))
        ;;	       (sleep-for 1))
        ;;I hope 1 second is enough!
        (sleep-for 1)
        (goto-char (point-max))
        (insert-file-contents startfile)
	(term-send-string
	 proc (delete-and-extract-region (point) (point-max)))))
    (run-hooks 'term-exec-hook)
    buffer))

(defun term-sentinel (proc msg)
  "Sentinel for term buffers.
The main purpose is to get rid of the local keymap."
  (let ((buffer (process-buffer proc)))
    (when (memq (process-status proc) '(signal exit))
      (if (null (buffer-name buffer))
	  ;; buffer killed
	  (set-process-buffer proc nil)
	(with-current-buffer buffer
          ;; Write something in the compilation buffer
          ;; and hack its mode line.
          ;; Get rid of local keymap.
          (use-local-map nil)
          (term-handle-exit (process-name proc) msg)
          ;; Since the buffer and mode line will show that the
          ;; process is dead, we can delete it now.  Otherwise it
          ;; will stay around until M-x list-processes.
          (delete-process proc))))))

(defun term-handle-exit (process-name msg)
  "Write process exit (or other change) message MSG in the current buffer."
  (let ((buffer-read-only nil)
	(omax (point-max))
	(opoint (point)))
    ;; Remove hooks to avoid errors due to dead process.
    (remove-hook 'pre-command-hook #'term-set-goto-process-mark t)
    (remove-hook 'post-command-hook #'term-goto-process-mark-maybe t)
    ;; Record where we put the message, so we can ignore it
    ;; later on.
    (goto-char omax)
    (insert ?\n "Process " process-name " " msg)
    ;; Force mode line redisplay soon.
    (force-mode-line-update)
    (when (and opoint (< opoint omax))
      (goto-char opoint))))


(defvar term-term-name "eterm-color"
  "Name to use for TERM.
Using \"emacs\" loses, because bash disables editing if $TERM == emacs.")
;; Format string, usage:
;; (format term-termcap-string emacs-term-name "TERMCAP=" 24 80)
(defvar term-termcap-format
  "%s%s:li#%d:co#%d:cl=\\E[H\\E[J:cd=\\E[J:bs:am:xn:cm=\\E[%%i%%d;%%dH\
:nd=\\E[C:up=\\E[A:ce=\\E[K:ho=\\E[H:pt\
:al=\\E[L:dl=\\E[M:DL=\\E[%%dM:AL=\\E[%%dL:cs=\\E[%%i%%d;%%dr:sf=^J\
:NR:te=\\E[47l:ti=\\E[47h\
:dc=\\E[P:DC=\\E[%%dP:IC=\\E[%%d@:im=\\E[4h:ei=\\E[4l:mi:\
:mb=\\E[5m:mh=\\E[2m:ZR=\\E[23m:ZH=\\E[3m\
:so=\\E[7m:se=\\E[m:us=\\E[4m:ue=\\E[m:md=\\E[1m:mr=\\E[7m:me=\\E[m\
:UP=\\E[%%dA:DO=\\E[%%dB:LE=\\E[%%dD:RI=\\E[%%dC\
:kl=\\EOD:kd=\\EOB:kr=\\EOC:ku=\\EOA:kN=\\E[6~:kP=\\E[5~:@7=\\E[4~:kh=\\E[1~\
:mk=\\E[8m:cb=\\E[1K:op=\\E[39;49m:Co#256:pa#32767\
:AB=\\E[48;5;%%dm:AF=\\E[38;5;%%dm:cr=^M\
:bl=^G:do=^J:le=^H:ta=^I:se=\\E[27m:ue=\\E[24m\
:kb=^?:kD=^[[3~:sc=\\E7:rc=\\E8:r1=\\Ec:RA=\\E[?7l:SA=\\E[?7h:"
  ;; : -undefine ic
  ;; don't define :te=\\E[2J\\E[?47l\\E8:ti=\\E7\\E[?47h\
  "Termcap capabilities supported.")

;; This private hack is for backwards compatibility with Bash 4.3 and earlier.
;; It can be useful even when running a program other than Bash, as the
;; program might invoke Bash as an interactive subshell.  See this thread:
;; https://lists.gnu.org/r/emacs-devel/2018-05/msg00670.html
;; Remove this hack and its uses once Bash 4.4-or-later is reasonably
;; universal, because it slows down execution slightly when
;; term--bash-needs-EMACSp is first called.
(defvar term--bash-needs-EMACS-status nil
  "43 if Bash is so old that it needs EMACS set.
Some other integer if Bash is new or not in use.
Nil if unknown.")
(defun term--bash-needs-EMACSp ()
  "Return t if Bash is old, nil if it is new or not in use."
  (eq 43
      (or term--bash-needs-EMACS-status
          (setf
           term--bash-needs-EMACS-status
           (let ((process-environment
                  (cons "BASH_ENV" process-environment)))
             (condition-case nil
                 (call-process
                  "bash" nil nil nil "-c"
                  "case $BASH_VERSION in [0123].*|4.[0123].*) exit 43;; esac")
               (error 0)))))))

(defun term-generate-db-directory ()
  "Return the name of a directory holding Emacs's terminfo files.
If `data-directory' is accessible to subprocesses, as on systems besides
Android, return the same and no more.  Otherwise, copy terminfo files
from the same directory to a temporary location, and return the latter."
  (if (not (featurep 'android))
      data-directory
    (progn
      (let* ((dst-directory (expand-file-name "eterm-db/e"
                                              temporary-file-directory))
             (parent (directory-file-name
                      (file-name-directory dst-directory)))
             (src-directory (expand-file-name "e" data-directory)))
        (when (file-newer-than-file-p src-directory dst-directory)
          (message "Generating Terminfo database...")
          (with-demoted-errors "Generating Terminfo database: %s"
            (when (file-exists-p dst-directory)
              ;; Arrange that the directory be writable.
              (dolist (x (directory-files-recursively parent "" t t))
                (set-file-modes x #o700))
              (delete-directory dst-directory t))
            (copy-directory src-directory dst-directory nil t t)))
        parent))))

;; This auxiliary function cranks up the process for term-exec in
;; the appropriate environment.

(defun term-exec-1 (name buffer command switches)
  ;; We need to do an extra (fork-less) exec to run stty.
  ;; (This would not be needed if we had suitable Emacs primitives.)
  ;; The 'if ...; then shift; fi' hack is because Bourne shell
  ;; loses one arg when called with -c, and newer shells (bash,  ksh) don't.
  ;; Thus we add an extra dummy argument "..", and then remove it.
  (let ((process-environment
	 (nconc
	  (list
	   (format "TERM=%s" term-term-name)
	   (format "TERMINFO=%s"
                   (term-generate-db-directory))
	   (format term-termcap-format "TERMCAP="
		   term-term-name term-height term-width)

	   (format "INSIDE_EMACS=%s,term:%s"
                   emacs-version term-protocol-version))
          (when term-set-terminal-size
            (list
             (format "LINES=%d" term-height)
	     (format "COLUMNS=%d" term-width)))
	  process-environment))
	(process-connection-type t)
	;; We should suppress conversion of end-of-line format.
	(inhibit-eol-conversion t)
	;; The process's output contains not just chars but also binary
	;; escape codes, so we need to see the raw output.  We will have to
	;; do the decoding by hand on the parts that are made of chars.
	(coding-system-for-read 'binary))
    (when (term--bash-needs-EMACSp)
      (push (format "EMACS=%s (term:%s)" emacs-version term-protocol-version)
            process-environment))
    (apply #'start-process name buffer
           ;; On Android, /bin doesn't exist, and the default shell is
           ;; found as /system/bin/sh.
	   (if (eq system-type 'android)
               "/system/bin/sh"
             "/bin/sh")
           "-c"
	   (format "stty -nl echo rows %d columns %d sane 2>%s;\
if [ $1 = .. ]; then shift; fi; exec \"$@\""
		   term-height term-width null-device)
	   ".."
	   command switches)))


;;; Input history processing in a buffer
;; ===========================================================================
;; Useful input history functions, courtesy of the Ergo group.

;; Eleven commands:
;; term-dynamic-list-input-ring	List history in help buffer.
;; term-previous-input			Previous input...
;; term-previous-matching-input		...matching a string.
;; term-previous-matching-input-from-input ... matching the current input.
;; term-next-input			Next input...
;; term-next-matching-input		...matching a string.
;; term-next-matching-input-from-input     ... matching the current input.
;; term-backward-matching-input		Backwards input...
;; term-forward-matching-input       ...matching a string.
;; term-replace-by-expanded-history	Expand history at point;
;;					replace with expanded history.
;; term-magic-space			Expand history and insert space.
;;
;; Three functions:
;; term-read-input-ring              Read into term-input-ring...
;; term-write-input-ring             Write to term-input-ring-file-name.
;; term-replace-by-expanded-history-before-point Workhorse function.

(defun term-read-input-ring (&optional silent)
  "Set the buffer's `term-input-ring' from a history file.
The name of the file is given by the variable `term-input-ring-file-name'.
The history ring is of size `term-input-ring-size', regardless of file size.
If `term-input-ring-file-name' is nil this function does nothing.

If the optional argument SILENT is non-nil, we say nothing about a
failure to read the history file.

This function is useful for major mode commands and mode hooks.

The structure of the history file should be one input command per line,
with the most recent command last.
See also `term-input-ignoredups' and `term-write-input-ring'."
  (cond ((or (null term-input-ring-file-name)
	     (equal term-input-ring-file-name ""))
	 nil)
	((not (file-readable-p term-input-ring-file-name))
	 (or silent
	     (message "Cannot read history file %s"
		      term-input-ring-file-name)))
	(t
	 (let ((file term-input-ring-file-name)
	       (count 0)
	       (ring (make-ring term-input-ring-size)))
           (with-temp-buffer
             (insert-file-contents file)
             ;; Save restriction in case file is already visited...
             ;; Watch for those date stamps in history files!
             (goto-char (point-max))
             (while (and (< count term-input-ring-size)
                         (re-search-backward "^[ \t]*\\([^#\n].*\\)[ \t]*$"
                                             nil t))
               (let ((history (buffer-substring (match-beginning 1)
                                                (match-end 1))))
                 (when (or (null term-input-ignoredups)
                           (ring-empty-p ring)
                           (not (string-equal (ring-ref ring 0) history)))
                   (ring-insert-at-beginning ring history)))
               (setq count (1+ count))))
	   (setq term-input-ring ring
		 term-input-ring-index nil)))))

(defun term-write-input-ring ()
  "Write the buffer's `term-input-ring' to a history file.
The name of the file is given by the variable `term-input-ring-file-name'.
The original contents of the file are lost if `term-input-ring' is not empty.
If `term-input-ring-file-name' is nil this function does nothing.

Useful within process sentinels.

See also `term-read-input-ring'."
  (cond ((or (null term-input-ring-file-name)
	     (equal term-input-ring-file-name "")
	     (null term-input-ring) (ring-empty-p term-input-ring))
	 nil)
	((not (file-writable-p term-input-ring-file-name))
	 (message "Cannot write history file %s" term-input-ring-file-name))
	(t
	 (let* ((history-buf (get-buffer-create " *Temp Input History*"))
		(ring term-input-ring)
		(file term-input-ring-file-name)
		(index (ring-length ring)))
	   ;; Write it all out into a buffer first.  Much faster, but messier,
	   ;; than writing it one line at a time.
	   (with-current-buffer history-buf
	     (erase-buffer)
	     (while (> index 0)
	       (setq index (1- index))
	       (insert (ring-ref ring index) ?\n))
	     (write-region (buffer-string) nil file nil 'no-message)
	     (kill-buffer nil))))))


(defun term-dynamic-list-input-ring ()
  "List in help buffer the buffer's input history."
  (interactive)
  (if (or (not (ring-p term-input-ring))
	  (ring-empty-p term-input-ring))
      (message "No history")
    (let ((history nil)
	  (history-buffer " *Input History*")
	  (index (1- (ring-length term-input-ring)))
	  (conf (current-window-configuration)))
      ;; We have to build up a list ourselves from the ring vector.
      (while (>= index 0)
	(setq history (cons (ring-ref term-input-ring index) history)
	      index (1- index)))
      ;; Change "completion" to "history reference"
      ;; to make the display accurate.
      (with-output-to-temp-buffer history-buffer
	(display-completion-list history)
	(set-buffer history-buffer)
	(forward-line 3)
	(while (search-backward "completion" nil 'move)
	  (replace-match "history reference")))
      (sit-for 0)
      (message "Hit space to flush")
      (let ((ch (read-event)))
	(if (eq ch ?\s)
	    (set-window-configuration conf)
	  (push ch unread-command-events))))))


(defun term-regexp-arg (prompt)
  ;; Return list of regexp and prefix arg using PROMPT.
  (let* (;; Don't clobber this.
	 (last-command last-command)
	 (regexp (read-from-minibuffer prompt nil nil nil
				       'minibuffer-history-search-history)))
    (list (if (string-equal regexp "")
	      (setcar minibuffer-history-search-history
		      (nth 1 minibuffer-history-search-history))
	    regexp)
	  (prefix-numeric-value current-prefix-arg))))

(defun term-search-arg (arg)
  ;; First make sure there is a ring and that we are after the process mark
  (cond ((not (term-after-pmark-p))
	 (error "Not at command line"))
	((or (null term-input-ring)
	     (ring-empty-p term-input-ring))
	 (error "Empty input ring"))
	((zerop arg)
	 ;; arg of zero resets search from beginning, and uses arg of 1
	 (setq term-input-ring-index nil)
	 1)
	(t
	 arg)))

(defun term-search-start (arg)
  ;; Index to start a directional search, starting at term-input-ring-index
  (if term-input-ring-index
      ;; If a search is running, offset by 1 in direction of arg
      (mod (+ term-input-ring-index (if (> arg 0) 1 -1))
	   (ring-length term-input-ring))
    ;; For a new search, start from beginning or end, as appropriate
    (if (>= arg 0)
	0				       ; First elt for forward search
      (1- (ring-length term-input-ring)))))  ; Last elt for backward search

(defun term-previous-input-string (arg)
  "Return the string ARG places along the input ring.
Moves relative to `term-input-ring-index'."
  (ring-ref term-input-ring (if term-input-ring-index
				  (mod (+ arg term-input-ring-index)
				       (ring-length term-input-ring))
				arg)))

(defun term-previous-input (arg)
  "Cycle backwards through input history."
  (interactive "*p")
  (term-previous-matching-input "." arg))

(defun term-next-input (arg)
  "Cycle forwards through input history."
  (interactive "*p")
  (term-previous-input (- arg)))

(defun term-previous-matching-input-string (regexp arg)
  "Return the string matching REGEXP ARG places along the input ring.
Moves relative to `term-input-ring-index'."
  (let* ((pos (term-previous-matching-input-string-position regexp arg)))
    (when pos (ring-ref term-input-ring pos))))

(defun term-previous-matching-input-string-position
  (regexp arg &optional start)
  "Return the index matching REGEXP ARG places along the input ring.
Moves relative to START, or `term-input-ring-index'."
  (when (or (not (ring-p term-input-ring))
	    (ring-empty-p term-input-ring))
    (error "No history"))
  (let* ((len (ring-length term-input-ring))
	 (motion (if (> arg 0) 1 -1))
	 (n (mod (- (or start (term-search-start arg)) motion) len))
	 (tried-each-ring-item nil)
	 (prev nil))
    ;; Do the whole search as many times as the argument says.
    (while (and (/= arg 0) (not tried-each-ring-item))
      ;; Step once.
      (setq prev n
	    n (mod (+ n motion) len))
      ;; If we haven't reached a match, step some more.
      (while (and (< n len) (not tried-each-ring-item)
		  (not (string-match regexp (ring-ref term-input-ring n))))
	(setq n (mod (+ n motion) len)
	      ;; If we have gone all the way around in this search.
	      tried-each-ring-item (= n prev)))
      (setq arg (if (> arg 0) (1- arg) (1+ arg))))
    ;; Now that we know which ring element to use, if we found it, return that.
    (when (string-match regexp (ring-ref term-input-ring n))
      n)))

(defun term-previous-matching-input (regexp n)
  "Search backwards through input history for match for REGEXP.
\(Previous history elements are earlier commands.)
With prefix argument N, search for Nth previous match.
If N is negative, find the next or Nth next match."
  (interactive (term-regexp-arg "Previous input matching (regexp): "))
  (setq n (term-search-arg n))
  (let ((pos (term-previous-matching-input-string-position regexp n)))
    ;; Has a match been found?
    (if (null pos)
	(error "Not found")
      (setq term-input-ring-index pos)
      (message "History item: %d" (1+ pos))
      (delete-region
       ;; Can't use kill-region as it sets this-command
       (process-mark (get-buffer-process (current-buffer))) (point))
      (insert (ring-ref term-input-ring pos)))))

(defun term-next-matching-input (regexp n)
  "Search forwards through input history for match for REGEXP.
\(Later history elements are more recent commands.)
With prefix argument N, search for Nth following match.
If N is negative, find the previous or Nth previous match."
  (interactive (term-regexp-arg "Next input matching (regexp): "))
  (term-previous-matching-input regexp (- n)))

(defun term-previous-matching-input-from-input (n)
  "Search backwards through input history for match for current input.
\(Previous history elements are earlier commands.)
With prefix argument N, search for Nth previous match.
If N is negative, search forwards for the -Nth following match."
  (interactive "p")
  (when (not (memq last-command '(term-previous-matching-input-from-input
				term-next-matching-input-from-input)))
    ;; Starting a new search
    (setq term-matching-input-from-input-string
	  (buffer-substring
	   (process-mark (get-buffer-process (current-buffer)))
	   (point))
	  term-input-ring-index nil))
  (term-previous-matching-input
   (concat "^" (regexp-quote term-matching-input-from-input-string))
   n))

(defun term-next-matching-input-from-input (n)
  "Search forwards through input history for match for current input.
\(Following history elements are more recent commands.)
With prefix argument N, search for Nth following match.
If N is negative, search backwards for the -Nth previous match."
  (interactive "p")
  (term-previous-matching-input-from-input (- n)))


(defun term-replace-by-expanded-history (&optional silent)
  "Expand input command history references before point.
Expansion is dependent on the value of `term-input-autoexpand'.

This function depends on the buffer's idea of the input history, which may not
match the command interpreter's idea, assuming it has one.

Assumes history syntax is like typical Un*x shells'.  However, since Emacs
cannot know the interpreter's idea of input line numbers, assuming it has one,
it cannot expand absolute input line number references.

If the optional argument SILENT is non-nil, never complain
even if history reference seems erroneous.

See `term-magic-space' and `term-replace-by-expanded-history-before-point'.

Returns t if successful."
  (interactive)
  (when (and term-input-autoexpand
	     (string-match "[!^]" (funcall term-get-old-input))
	     (save-excursion (beginning-of-line)
			     (looking-at term-prompt-regexp)))
    ;; Looks like there might be history references in the command.
    (let ((previous-modified-tick (buffer-modified-tick)))
      (message "Expanding history references...")
      (term-replace-by-expanded-history-before-point silent)
      (/= previous-modified-tick (buffer-modified-tick)))))


(defun term-replace-by-expanded-history-before-point (silent)
  "Expand directory stack reference before point.
See `term-replace-by-expanded-history'.  Returns t if successful."
  (save-excursion
    (let ((toend (- (line-end-position) (point)))
	  (start (progn (term-bol nil) (point))))
      (while (progn
	       (skip-chars-forward "^!^" (- (line-end-position) toend))
	       (< (point) (- (line-end-position) toend)))
	;; This seems a bit complex.  We look for references such as !!, !-num,
	;; !foo, !?foo, !{bar}, !?{bar}, ^oh, ^my^, ^god^it, ^never^ends^.
	;; If that wasn't enough, the plings can be suffixed with argument
	;; range specifiers.
	;; Argument ranges are complex too, so we hive off the input line,
	;; referenced with plings, with the range string to `term-args'.
	(setq term-input-ring-index nil)
	(cond ((or (= (preceding-char) ?\\)
		   (term-within-quotes start (point)))
	       ;; The history is quoted, or we're in quotes.
	       (goto-char (1+ (point))))
	      ((looking-at "![0-9]+\\($\\|[^-]\\)")
	       ;; We cannot know the interpreter's idea of input line numbers.
	       (goto-char (match-end 0))
	       (message "Absolute reference cannot be expanded"))
	      ((looking-at "!-\\([0-9]+\\):?\\([0-9^$*-]+\\)?")
	       ;; Just a number of args from `number' lines backward.
	       (let ((number (1- (string-to-number
				  (buffer-substring (match-beginning 1)
						    (match-end 1))))))
		 (if (<= number (ring-length term-input-ring))
		     (progn
		       (replace-match
			(term-args (term-previous-input-string number)
				     (match-beginning 2) (match-end 2))
			t t)
		       (setq term-input-ring-index number)
		       (message "History item: %d" (1+ number)))
		   (goto-char (match-end 0))
		   (message "Relative reference exceeds input history size"))))
	      ((or (looking-at "!!?:?\\([0-9^$*-]+\\)") (looking-at "!!"))
	       ;; Just a number of args from the previous input line.
	       (replace-match
		(term-args (term-previous-input-string 0)
			     (match-beginning 1) (match-end 1))
		t t)
	       (message "History item: previous"))
	      ((looking-at
		"!\\??\\({\\(.+\\)}\\|\\(\\sw+\\)\\):?\\([0-9^$*-]+\\)?")
	       ;; Most recent input starting with or containing (possibly
	       ;; protected) string, maybe just a number of args.  Phew.
	       (let* ((mb1 (match-beginning 1)) (me1 (match-end 1))
		      (mb2 (match-beginning 2)) (me2 (match-end 2))
		      (exp (buffer-substring (or mb2 mb1) (or me2 me1)))
		      (pref (if (save-match-data (looking-at "!\\?")) "" "^"))
		      (pos (save-match-data
			     (term-previous-matching-input-string-position
			      (concat pref (regexp-quote exp)) 1))))
		 (if (null pos)
		     (progn
		       (goto-char (match-end 0))
		       (or silent
			   (progn (message "Not found")
				  (ding))))
		   (setq term-input-ring-index pos)
		   (replace-match
		    (term-args (ring-ref term-input-ring pos)
				 (match-beginning 4) (match-end 4))
		    t t)
		   (message "History item: %d" (1+ pos)))))
	      ((looking-at "\\^\\([^^]+\\)\\^?\\([^^]*\\)\\^?")
	       ;; Quick substitution on the previous input line.
	       (let ((old (buffer-substring (match-beginning 1) (match-end 1)))
		     (new (buffer-substring (match-beginning 2) (match-end 2)))
		     (pos nil))
		 (replace-match (term-previous-input-string 0) t t)
		 (setq pos (point))
		 (goto-char (match-beginning 0))
		 (if (not (search-forward old pos t))
		     (or silent
			 (error "Not found"))
		   (replace-match new t t)
		   (message "History item: substituted"))))
	      (t
	       (goto-char (match-end 0))))))))


(defun term-magic-space (arg)
  "Expand input history references before point and insert ARG spaces.
A useful command to bind to SPC.  See `term-replace-by-expanded-history'."
  (interactive "p")
  (term-replace-by-expanded-history)
  (self-insert-command arg))

(defun term-within-quotes (beg end)
  "Return t if the number of quotes between BEG and END is odd.
Quotes are single and double."
  (let ((countsq (term-how-many-region "\\(^\\|[^\\]\\)'" beg end))
	(countdq (term-how-many-region "\\(^\\|[^\\]\\)\"" beg end)))
    (or (oddp countsq) (oddp countdq))))

(defun term-how-many-region (regexp beg end)
  "Return number of matches for REGEXP from BEG to END."
  (let ((count 0))
    (save-excursion
      (save-match-data
	(goto-char beg)
	(while (re-search-forward regexp end t)
	  (setq count (1+ count)))))
    count))

(defun term-args (string begin end)
  ;; From STRING, return the args depending on the range specified in the text
  ;; from BEGIN to END.  If BEGIN is nil, assume all args.  Ignore leading `:'.
  ;; Range can be x-y, x-, -y, where x/y can be [0-9], *, ^, $.
  (save-match-data
    (if (null begin)
	(term-arguments string 0 nil)
      (let* ((range (buffer-substring
		     (if (eq (char-after begin) ?:) (1+ begin) begin) end))
	     (nth (cond ((string-match "^[*^]" range) 1)
			((string-match "^-" range) 0)
			((string-equal range "$") nil)
			(t (string-to-number range))))
	     (mth (cond ((string-match "[-*$]$" range) nil)
			((string-match "-" range)
			 (string-to-number (substring range (match-end 0))))
			(t nth))))
	(term-arguments string nth mth)))))

;; Return a list of arguments from ARG.  Break it up at the
;; delimiters in term-delimiter-argument-list.  Returned list is backwards.
(defun term-delim-arg (arg)
  (if (null term-delimiter-argument-list)
      (list arg)
    (let ((args nil)
	  (pos 0)
	  (len (length arg)))
      (while (< pos len)
	(let ((char (aref arg pos))
	      (start pos))
	  (if (memq char term-delimiter-argument-list)
	      (while (and (< pos len) (eq (aref arg pos) char))
		(setq pos (1+ pos)))
	    (while (and (< pos len)
			(not (memq (aref arg pos)
				   term-delimiter-argument-list)))
	      (setq pos (1+ pos))))
	  (setq args (cons (substring arg start pos) args))))
      args)))

(defun term-arguments (string nth mth)
  "Return from STRING the NTH to MTH arguments.
NTH and/or MTH can be nil, which means the last argument.
Returned arguments are separated by single spaces.
We assume whitespace separates arguments, except within quotes.
Also, a run of one or more of a single character
in `term-delimiter-argument-list' is a separate argument.
Argument 0 is the command name."
  (let ((argpart "[^ \n\t\"'`]+\\|\\(\"[^\"]*\"\\|'[^']*'\\|`[^`]*`\\)")
	(args ()) (pos 0)
	(count 0)
	beg str quotes)
    ;; Build a list of all the args until we have as many as we want.
    (while (and (or (null mth) (<= count mth))
		(string-match argpart string pos))
      (if (and beg (= pos (match-beginning 0)))
	  ;; It's contiguous, part of the same arg.
	  (setq pos (match-end 0)
		quotes (or quotes (match-beginning 1)))
	;; It's a new separate arg.
	(if beg
	    ;; Put the previous arg, if there was one, onto ARGS.
	    (setq str (substring string beg pos)
		  args (if quotes (cons str args)
			 (nconc (term-delim-arg str) args))
		  count (1+ count)))
	(setq quotes (match-beginning 1))
	(setq beg (match-beginning 0))
	(setq pos (match-end 0))))
    (if beg
	(setq str (substring string beg pos)
	      args (if quotes (cons str args)
		     (nconc (term-delim-arg str) args))
	      count (1+ count)))
    (let ((n (or nth (1- count)))
	  (m (if mth (1- (- count mth)) 0)))
      (mapconcat
       #'identity (nthcdr n (nreverse (nthcdr m args))) " "))))

;;;
;;; Input processing stuff [line mode]
;;;

(defun term-send-input ()
  "Send input to process.
After the process output mark, sends all text from the process mark to
point as input to the process.  Before the process output mark, calls value
of variable `term-get-old-input' to retrieve old input, copies it to the
process mark, and sends it.  A terminal newline is also inserted into the
buffer and sent to the process.  The functions in `term-input-filter-functions'
are called on the input before sending it.

The input is entered into the input history ring, if the value of variable
`term-input-filter' returns non-nil when called on the input.  Any history
reference may be expanded depending on the value of the variable
`term-input-autoexpand'.

If variable `term-eol-on-send' is non-nil, then point is moved to the
end of line before sending the input.

The values of `term-get-old-input', `term-input-filter-functions', and
`term-input-filter' are chosen according to the command interpreter running
in the buffer.  E.g.,

If the interpreter is the csh,
    `term-get-old-input' is the default: take the current line, discard any
        initial string matching regexp `term-prompt-regexp'.
    `term-input-filter-functions' monitors input for \"cd\", \"pushd\", and
	\"popd\" commands.  When it sees one, it cd's the buffer.
    `term-input-filter' is the default: returns t if the input isn't all white
	space.

If the term is Lucid Common Lisp,
    `term-get-old-input' snarfs the sexp ending at point.
    `term-input-filter-functions' does nothing.
    `term-input-filter' returns nil if the input matches input-filter-regexp,
        which matches (1) all whitespace (2) :a, :c, etc.

Similarly for Soar, Scheme, etc."
  (interactive)
  ;; Note that the input string does not include its terminal newline.
  (let ((proc (get-buffer-process (current-buffer))))
    (if (not proc) (error "Current buffer has no process")
      (let* ((pmark (process-mark proc))
	     (pmark-val (marker-position pmark))
	     (input-is-new (>= (point) pmark-val))
	     (intxt (if input-is-new
			(progn (if term-eol-on-send (end-of-line))
			       (buffer-substring pmark (point)))
		      (funcall term-get-old-input)))
	     (input (if (not (eq term-input-autoexpand 'input))
			;; Just whatever's already there
			intxt
		      ;; Expand and leave it visible in buffer
		      (term-replace-by-expanded-history t)
		      (buffer-substring pmark (point))))
	     (history (if (not (eq term-input-autoexpand 'history))
			  input
			;; This is messy 'cos ultimately the original
			;; functions used do insertion, rather than return
			;; strings.  We have to expand, then insert back.
			(term-replace-by-expanded-history t)
			(let ((copy (buffer-substring pmark (point))))
			  (delete-region pmark (point))
			  (insert input)
			  copy))))
	(when (term-pager-enabled)
	  (save-excursion
	    (goto-char (process-mark proc))
	    (setq term-pager-count (term-current-row))))
	(when (and (funcall term-input-filter history)
		   (or (null term-input-ignoredups)
		       (not (ring-p term-input-ring))
		       (ring-empty-p term-input-ring)
		       (not (string-equal (ring-ref term-input-ring 0)
					  history))))
	  (ring-insert term-input-ring history))
        (run-hook-with-args 'term-input-filter-functions (concat input "\n"))
	(setq term-input-ring-index nil)

	;; Update the markers before we send the input
	;; in case we get output amidst sending the input.
	(set-marker term-last-input-start pmark)
	(set-marker term-last-input-end (point))
	(when input-is-new
	  ;; Set up to delete, because inferior should echo.
	  (when (marker-buffer term-pending-delete-marker)
	    (delete-region term-pending-delete-marker pmark))
	  (set-marker term-pending-delete-marker pmark-val)
	  (set-marker (process-mark proc) (point)))
	(goto-char pmark)
	(funcall term-input-sender proc input)))))

(defun term-get-old-input-default ()
  "Default for `term-get-old-input'.
Take the current line, and discard any initial text matching
`term-prompt-regexp'."
  (save-excursion
    (beginning-of-line)
    (term-skip-prompt)
    (let ((beg (point)))
      (end-of-line)
      (buffer-substring beg (point)))))

(defun term-copy-old-input ()
  "Insert after prompt old input at point as new input to be edited.
Calls `term-get-old-input' to get old input."
  (interactive)
  (let ((input (funcall term-get-old-input))
 	(process (get-buffer-process (current-buffer))))
    (if (not process)
	(error "Current buffer has no process")
      (goto-char (process-mark process))
      (insert input))))

(defun term-skip-prompt ()
  "Skip past the text matching regexp `term-prompt-regexp'.
If this takes us past the end of the current line, don't skip at all."
  (let ((eol (line-end-position)))
    (when (and (looking-at term-prompt-regexp)
	       (<= (match-end 0) eol))
      (goto-char (match-end 0)))))


(defun term-after-pmark-p ()
  "Is point after the process output marker?"
  ;; Since output could come into the buffer after we looked at the point
  ;; but before we looked at the process marker's value, we explicitly
  ;; serialize.  This is just because I don't know whether or not Emacs
  ;; services input during execution of lisp commands.
  (let ((proc-pos (marker-position
		   (process-mark (get-buffer-process (current-buffer))))))
    (<= proc-pos (point))))

(defun term-simple-send (proc string)
  "Default function for sending to PROC input STRING.
This just sends STRING plus a newline.  To override this,
set the hook `term-input-sender'."
  (term-send-string proc string)
  (term-send-string proc "\n"))

(defun term-bol (arg)
  "Go to the beginning of line, then skip past the prompt, if any.
If a prefix argument is given (\\[universal-argument]), then no prompt skip
-- go straight to column 0.

The prompt skip is done by skipping text matching the regular expression
`term-prompt-regexp', a buffer local variable."
  (interactive "P")
  (beginning-of-line)
  (when (null arg) (term-skip-prompt)))

;; These two functions are for entering text you don't want echoed or
;; saved -- typically passwords to ftp, telnet, or somesuch.
;; Just enter m-x term-send-invisible and type in your line.

(defun term-read-noecho (prompt &optional stars)
  "Read a single line of text from user without echoing, and return it.
Prompt with argument PROMPT, a string.  Optional argument STARS causes
input to be echoed with `*' characters on the prompt line.  Input ends with
RET, LFD, or ESC.  DEL or C-h rubs out.  C-u kills line.  C-g aborts (if
`inhibit-quit' is set because e.g. this function was called from a process
filter and C-g is pressed, this function returns nil rather than a string).

Note that the keystrokes comprising the text can still be recovered
\(temporarily) with \\[view-lossage].  This may be a security bug for some
applications."
  (declare (obsolete read-passwd "27.1"))
  (let ((ans "")
	(c 0)
	(echo-keystrokes 0)
	(cursor-in-echo-area t)
        (done nil))
    (while (not done)
      (if stars
          (message "%s%s" prompt (make-string (length ans) ?*))
        (message "%s" prompt))
      (setq c (read-char))
      (cond ((= c ?\C-g)
             ;; This function may get called from a process filter, where
             ;; inhibit-quit is set.  In later versions of Emacs read-char
             ;; may clear quit-flag itself and return C-g.  That would make
             ;; it impossible to quit this loop in a simple way, so
             ;; re-enable it here (for backward-compatibility the check for
             ;; quit-flag below would still be necessary, so this seems
             ;; like the simplest way to do things).
             (setq quit-flag t
                   done t))
            ((or (= c ?\r) (= c ?\n) (= c ?\e))
             (setq done t))
            ((= c ?\C-u)
             (setq ans ""))
            ((and (/= c ?\b) (/= c ?\177))
             (setq ans (concat ans (char-to-string c))))
            ((> (length ans) 0)
             (setq ans (substring ans 0 -1)))))
    (if quit-flag
        ;; Emulate a true quit, except that we have to return a value.
        (prog1
            (setq quit-flag nil)
          (message "Quit")
          (beep t))
      (message "")
      ans)))

(defun term-send-invisible (str &optional proc)
  "Read a string without echoing.
Then send it to the process running in the current buffer.  A new-line
is additionally sent.  String is not saved on term input history list."
  (interactive "P") ; Defeat snooping via C-x esc
  (when (not (stringp str))
    (setq str (read-passwd "Non-echoed text: ")))
  (when (not proc)
    (setq proc (get-buffer-process (current-buffer))))
  (if (not proc) (error "Current buffer has no process")
    (setq term-kill-echo-list (nconc term-kill-echo-list
				     (cons str nil)))
    (term-send-string proc str)
    (term-send-string proc "\n")))

;; TODO: Maybe combine this with `comint-watch-for-password-prompt'.
(defun term-watch-for-password-prompt (string)
  "Prompt in the minibuffer for password and send without echoing.
Checks if STRING contains a password prompt as defined by
`comint-password-prompt-regexp'."
  (when (term-in-line-mode)
    (when (let ((case-fold-search t))
            (string-match comint-password-prompt-regexp string))
      ;; Use `run-at-time' in order not to pause execution of the
      ;; process filter with a minibuffer
      (run-at-time
       0 nil
       (lambda (current-buf)
         (with-current-buffer current-buf
           (term-send-invisible (read-passwd string))))
       (current-buffer)))))


;;; Low-level process communication

(defcustom term-input-chunk-size 512
  "Long inputs send to term processes are broken up into chunks of this size.
If your process is choking on big inputs, try lowering the value."
  :group 'term
  :type 'natnum)

(defun term-send-string (proc str)
  "Send to PROC the contents of STR as input.
This is equivalent to `process-send-string', except that long input strings
are broken up into chunks of size `term-input-chunk-size'.  Processes
are given a chance to output between chunks.  This can help prevent processes
from hanging when you send them long inputs on some OS's."
  (let* ((len (length str))
	 (i (min len term-input-chunk-size)))
    (process-send-string proc (substring str 0 i))
    (while (< i len)
      (let ((next-i (+ i term-input-chunk-size)))
	(accept-process-output)
	(process-send-string proc (substring str i (min len next-i)))
	(setq i next-i)))))

(defun term-send-region (proc start end)
  "Send to PROC the region delimited by START and END.
This is a replacement for `process-send-region' that tries to keep
your process from hanging on long inputs.  See `term-send-string'."
  (term-send-string proc (buffer-substring start end)))


;;; Random input hackage

(defun term-kill-output ()
  "Kill all output from interpreter since last input."
  (interactive)
  (let ((pmark (process-mark (get-buffer-process (current-buffer)))))
    (kill-region term-last-input-end pmark)
    (goto-char pmark)
    (insert "*** output flushed ***\n")
    (set-marker pmark (point))))

(defun term-show-output ()
  "Display start of this batch of interpreter output at top of window.
Sets mark to the value of point when this command is run."
  (interactive)
  (goto-char term-last-input-end)
  (backward-char)
  (beginning-of-line)
  (set-window-start (selected-window) (point))
  (end-of-line))

(defun term-interrupt-subjob ()
  "Interrupt the current subjob."
  (interactive)
  (interrupt-process nil term-ptyp))

(defun term-kill-subjob ()
  "Send kill signal to the current subjob."
  (interactive)
  (kill-process nil term-ptyp))

(defun term-quit-subjob ()
  "Send quit signal to the current subjob."
  (interactive)
  (quit-process nil term-ptyp))

(defun term-stop-subjob ()
  "Stop the current subjob.
WARNING: if there is no current subjob, you can end up suspending
the top-level process running in the buffer.  If you accidentally do
this, use \\[term-continue-subjob] to resume the process.  (This
is not a problem with most shells, since they ignore this signal.)"
  (interactive)
  (stop-process nil term-ptyp))

(defun term-continue-subjob ()
  "Send CONT signal to process buffer's process group.
Useful if you accidentally suspend the top-level process."
  (interactive)
  (continue-process nil term-ptyp))

(defun term-kill-input ()
  "Kill all text from last stuff output by interpreter to point."
  (interactive)
  (let* ((pmark (process-mark (get-buffer-process (current-buffer))))
	 (p-pos (marker-position pmark)))
    (when (> (point) p-pos)
      (kill-region pmark (point)))))

(defun term-delchar-or-maybe-eof (arg)
  "Delete ARG characters forward, or send an EOF to process if at end of buffer."
  (interactive "p")
  (if (eobp)
      (process-send-eof)
    (delete-char arg)))

(defun term-send-eof ()
  "Send an EOF to the current buffer's process."
  (interactive)
  (process-send-eof))

(defun term-backward-matching-input (regexp n)
  "Search backward through buffer for match for REGEXP.
Matches are searched for on lines that match `term-prompt-regexp'.
With prefix argument N, search for Nth previous match.
If N is negative, find the next or Nth next match."
  (interactive (term-regexp-arg "Backward input matching (regexp): "))
  (let* ((re (concat term-prompt-regexp ".*" regexp))
	 (pos (save-excursion (end-of-line (if (> n 0) 0 1))
			      (when (re-search-backward re nil t n)
				(point)))))
    (if (null pos)
	(progn (message "Not found")
	       (ding))
      (goto-char pos)
      (term-bol nil))))

(defun term-forward-matching-input (regexp n)
  "Search forward through buffer for match for REGEXP.
Matches are searched for on lines that match `term-prompt-regexp'.
With prefix argument N, search for Nth following match.
If N is negative, find the previous or Nth previous match."
  (interactive (term-regexp-arg "Forward input matching (regexp): "))
  (term-backward-matching-input regexp (- n)))


(defun term-next-prompt (n)
  "Move to end of Nth next prompt in the buffer.
See `term-prompt-regexp'."
  (interactive "p")
  (let ((paragraph-start term-prompt-regexp))
    (end-of-line (if (> n 0) 1 0))
    (forward-paragraph n)
    (term-skip-prompt)))

(defun term-previous-prompt (n)
  "Move to end of Nth previous prompt in the buffer.
See `term-prompt-regexp'."
  (interactive "p")
  (term-next-prompt (- n)))

;;; Support for source-file processing commands.
;;============================================================================
;; Many command-interpreters (e.g., Lisp, Scheme, Soar) have
;; commands that process files of source text (e.g. loading or compiling
;; files).  So the corresponding process-in-a-buffer modes have commands
;; for doing this (e.g., lisp-load-file).  The functions below are useful
;; for defining these commands.
;;
;; Alas, these guys don't do exactly the right thing for Lisp, Scheme
;; and Soar, in that they don't know anything about file extensions.
;; So the compile/load interface gets the wrong default occasionally.
;; The load-file/compile-file default mechanism could be smarter -- it
;; doesn't know about the relationship between filename extensions and
;; whether the file is source or executable.  If you compile foo.lisp
;; with compile-file, then the next load-file should use foo.bin for
;; the default, not foo.lisp.  This is tricky to do right, particularly
;; because the extension for executable files varies so much (.o, .bin,
;; .lbin, .mo, .vo, .ao, ...).


;; TERM-SOURCE-DEFAULT -- determines defaults for source-file processing
;; commands.
;;
;; TERM-CHECK-SOURCE -- if FNAME is in a modified buffer, asks you if you
;; want to save the buffer before issuing any process requests to the command
;; interpreter.
;;
;; TERM-GET-SOURCE -- used by the source-file processing commands to prompt
;; for the file to process.

;; (TERM-SOURCE-DEFAULT previous-dir/file source-modes)
;;============================================================================
;; This function computes the defaults for the load-file and compile-file
;; commands for tea, soar, cmulisp, and cmuscheme modes.
;;
;; - PREVIOUS-DIR/FILE is a pair (directory . filename) from the last
;; source-file processing command, or nil if there hasn't been one yet.
;; - SOURCE-MODES is a list used to determine what buffers contain source
;; files: if the major mode of the buffer is in SOURCE-MODES, it's source.
;; Typically, (lisp-mode) or (scheme-mode).
;;
;; If the command is given while the cursor is inside a string, *and*
;; the string is an existing filename, *and* the filename is not a directory,
;; then the string is taken as default.  This allows you to just position
;; your cursor over a string that's a filename and have it taken as default.
;;
;; If the command is given in a file buffer whose major mode is in
;; SOURCE-MODES, then the filename is the default file, and the
;; file's directory is the default directory.
;;
;; If the buffer isn't a source file buffer (e.g., it's the process buffer),
;; then the default directory & file are what was used in the last source-file
;; processing command (i.e., PREVIOUS-DIR/FILE).  If this is the first time
;; the command has been run (PREVIOUS-DIR/FILE is nil), the default directory
;; is the cwd, with no default file.  (\"no default file\" = nil)
;;
;; SOURCE-REGEXP is typically going to be something like (tea-mode)
;; for T programs, (lisp-mode) for Lisp programs, (soar-mode lisp-mode)
;; for Soar programs, etc.
;;
;; The function returns a pair: (default-directory . default-file).

(defun term-source-default (previous-dir/file source-modes)
  (cond ((and buffer-file-name (memq major-mode source-modes))
	 (cons (file-name-directory    buffer-file-name)
	       (file-name-nondirectory buffer-file-name)))
	(previous-dir/file)
	(t
	 (cons default-directory nil))))


;; (TERM-CHECK-SOURCE fname)
;;============================================================================
;; Prior to loading or compiling (or otherwise processing) a file (in the CMU
;; process-in-a-buffer modes), this function can be called on the filename.
;; If the file is loaded into a buffer, and the buffer is modified, the user
;; is queried to see if he wants to save the buffer before proceeding with
;; the load or compile.

(defun term-check-source (fname)
  (let ((buff (get-file-buffer fname)))
    (when (and buff
	       (buffer-modified-p buff)
	       (y-or-n-p (format "Save buffer %s first? "
				 (buffer-name buff))))
      ;; save BUFF.
      (with-current-buffer buff
	(save-buffer)))))


;; (TERM-GET-SOURCE prompt prev-dir/file source-modes mustmatch-p)
;;============================================================================
;; TERM-GET-SOURCE is used to prompt for filenames in command-interpreter
;; commands that process source files (like loading or compiling a file).
;; It prompts for the filename, provides a default, if there is one,
;; and returns the result filename.
;;
;; See TERM-SOURCE-DEFAULT for more on determining defaults.
;;
;; PROMPT is the prompt string.  PREV-DIR/FILE is the (directory . file) pair
;; from the last source processing command.  SOURCE-MODES is a list of major
;; modes used to determine what file buffers contain source files.  (These
;; two arguments are used for determining defaults).  If MUSTMATCH-P is true,
;; then the filename reader will only accept a file that exists.
;;
;; A typical use:
;; (interactive (term-get-source "Compile file" prev-lisp-dir/file
;;                                 '(lisp-mode) t))

;; This is pretty stupid about strings.  It decides we're in a string
;; if there's a quote on both sides of point on the current line.
(defun term-extract-string ()
  "Return string around `point' that starts the current line or nil."
  (save-excursion
    (let* ((point (point))
	   (bol (line-beginning-position))
	   (eol (line-end-position))
	   (start (and (search-backward "\"" bol t)
                       (1+ (point))))
	   (end (progn (goto-char point)
		       (and (search-forward "\"" eol t)
			    (1- (point))))))
      (and start end
	   (buffer-substring start end)))))

(defun term-get-source (prompt prev-dir/file source-modes mustmatch-p)
  (let* ((def (term-source-default prev-dir/file source-modes))
         (stringfile (term-extract-string))
	 (sfile-p (and stringfile
		       (condition-case ()
			   (file-exists-p stringfile)
			 (error nil))
		       (not (file-directory-p stringfile))))
	 (defdir  (if sfile-p (file-name-directory stringfile)
                      (car def)))
	 (deffile (if sfile-p (file-name-nondirectory stringfile)
                      (cdr def)))
	 (ans (read-file-name (format-prompt prompt deffile)
			      defdir
			      (concat defdir deffile)
			      mustmatch-p)))
    (list (expand-file-name (substitute-in-file-name ans)))))

;; I am somewhat divided on this string-default feature.  It seems
;; to violate the principle-of-least-astonishment, in that it makes
;; the default harder to predict, so you actually have to look and see
;; what the default really is before choosing it.  This can trip you up.
;; On the other hand, it can be useful, I guess.  I would appreciate feedback
;; on this.
;;     -Olin


;;; Simple process query facility.
;; ===========================================================================
;; This function is for commands that want to send a query to the process
;; and show the response to the user.  For example, a command to get the
;; arglist for a Common Lisp function might send a "(arglist 'foo)" query
;; to an inferior Common Lisp process.
;;
;; This simple facility just sends strings to the inferior process and pops
;; up a window for the process buffer so you can see what the process
;; responds with.  We don't do anything fancy like try to intercept what the
;; process responds with and put it in a pop-up window or on the message
;; line.  We just display the buffer.  Low tech.  Simple.  Works good.

;; Send to the inferior process PROC the string STR.  Pop-up but do not select
;; a window for the inferior process so that its response can be seen.
(defun term-proc-query (proc str)
  (let* ((proc-buf (process-buffer proc))
	 (proc-mark (process-mark proc)))
    (display-buffer proc-buf)
    (set-buffer proc-buf) ; but it's not the selected *window*
    (let ((proc-win (get-buffer-window proc-buf))
	  (proc-pt (marker-position proc-mark)))
      (term-send-string proc str) ; send the query
      (accept-process-output proc)  ; wait for some output
      ;; Try to position the proc window so you can see the answer.
      ;; This is bogus code.  If you delete the (sit-for 0), it breaks.
      ;; I don't know why.  Wizards invited to improve it.
      (when (not (pos-visible-in-window-p proc-pt proc-win))
	(let ((opoint (window-point proc-win)))
	  (set-window-point proc-win proc-mark) (sit-for 0)
	  (if (not (pos-visible-in-window-p opoint proc-win))
	      (push-mark opoint)
	    (set-window-point proc-win opoint)))))))

;; Returns the current column in the current screen line.
;; Note: (current-column) yields column in buffer line.

(defun term-horizontal-column ()
  (- (term-current-column) (term-start-line-column)))

;; Calls either vertical-motion or term-buffer-vertical-motion
(defmacro term-vertical-motion (count)
  (list 'funcall 'term-vertical-motion count))

; An emulation of vertical-motion that is independent of having a window.
; Instead, it uses the term-width variable as the logical window width.

(defun term-buffer-vertical-motion (count)
  (cond ((= count 0)
	 (move-to-column (* term-width (/ (current-column) term-width)))
	 0)
	((> count 0)
	 (let ((H)
	       (todo (+ count (/ (current-column) term-width))))
	   (end-of-line)
	   ;; The loop iterates over buffer lines;
	   ;; H is the number of screen lines in the current line, i.e.
	   ;; the ceiling of dividing the buffer line width by term-width.
	   (while (and (<= (setq H (max (/ (+ (current-column) term-width -1)
					   term-width)
					1))
			   todo)
		       (not (eobp)))
	     (setq todo (- todo H))
	     (forward-char) ;; Move past the ?\n
	     (end-of-line)) ;; and on to the end of the next line.
	   (if (and (>= todo H) (> todo 0))
	       (+ (- count todo) H -1) ;; Hit end of buffer.
	     (move-to-column (* todo term-width))
	     count)))
	(t ;; (< count 0) ;; Similar algorithm, but for upward motion.
	 (let ((H)
	       (todo (- count)))
	   (while (and (<= (setq H (max (/ (+ (current-column) term-width -1)
					   term-width)
					1))
			   todo)
		       (progn (beginning-of-line)
			      (not (bobp))))
	     (setq todo (- todo H))
	     (backward-char)) ;; Move to end of previous line.
	   (if (and (>= todo H) (> todo 0))
	       (+ count todo (- 1 H)) ;; Hit beginning of buffer.
	     (move-to-column (* (- H todo 1) term-width))
	     count)))))

;; The term-start-line-column variable is used as a cache.
(defun term-start-line-column ()
  (cond (term-start-line-column)
	((let ((save-pos (point)))
	   (term-vertical-motion 0)
	   (setq term-start-line-column (current-column))
	   (goto-char save-pos)
	   term-start-line-column))))

;; Same as (current-column), but uses term-current-column as a cache.
(defun term-current-column ()
  (cond (term-current-column)
	((setq term-current-column (current-column)))))

(defun term-move-to-column (column)
  (setq term-current-column column)
  (let ((line-end-position (line-end-position)))
    (move-to-column term-current-column t)
    ;; If move-to-column extends the current line it will use the face
    ;; from the last character on the line, set the face for the chars
    ;; to default.
    (when (> (point) line-end-position)
      (put-text-property line-end-position (point) 'font-lock-face 'default))))

;; Move DELTA column right (or left if delta < 0 limiting at column 0).
(defun term-move-columns (delta)
  (term-move-to-column
   (max 0 (+ (term-current-column) delta))))

;; Insert COUNT copies of CHAR in the default face.
(defun term-insert-char (char count)
  (let ((old-point (point)))
    (insert-char char count)
    (put-text-property old-point (point) 'font-lock-face 'default)))

(defun term-current-row ()
  (cond (term-current-row)
	((setq term-current-row
	       (save-restriction
		 (save-excursion
		   (narrow-to-region term-home-marker (point-max))
		   (- (term-vertical-motion -9999))))))))

(defun term-adjust-current-row-cache (delta)
  (when term-current-row
    (setq term-current-row
	  (max 0 (+ term-current-row delta)))))

(defun term-terminal-pos ()
  (save-excursion ;    save-restriction
    (let ((save-col (term-current-column))
	  x y)
      (term-vertical-motion 0)
      (setq x (- save-col (current-column)))
      (setq y (term-vertical-motion term-height))
      (cons x y))))

;;Function that handles term messages: code by rms (and you can see the
;;difference ;-) -mm

(defun term-handle-ansi-terminal-messages (message)
  ;; Is there a command here?
  (while (string-match "\eAnSiT.+\n" message)
    ;; Extract the command code and the argument.
    (let* ((start (match-beginning 0))
	   (command-code (aref message (+ start 6)))
	   (argument
	    (save-match-data
	      (substring message
			 (+ start 8)
			 (string-match "\r?\n" message
				       (+ start 8)))))
	   ignore)
      ;; Delete this command from MESSAGE.
      (setq message (replace-match "" t t message))

      ;; If we recognize the type of command, set the appropriate variable.
      (cond ((= command-code ?c)
	     (setq term-ansi-at-dir argument))
	    ((= command-code ?h)
	     (setq term-ansi-at-host argument))
	    ((= command-code ?u)
	     (setq term-ansi-at-user argument))
	    ;; Otherwise ignore this one.
	    (t
	     (setq ignore t)))

      ;; Update default-directory based on the changes this command made.
      (if ignore
	  nil
	(setq default-directory
	      (file-name-as-directory
	       (if (and (string= term-ansi-at-host (system-name))
                        (string= term-ansi-at-user (user-real-login-name)))
		   (expand-file-name term-ansi-at-dir)
                 (concat "/-:" term-ansi-at-user "@" term-ansi-at-host ":"
                         term-ansi-at-dir))))

	;; I'm not sure this is necessary,
	;; but it's best to be on the safe side.
	(if (string= term-ansi-at-host (system-name))
	    (progn
	      (setq ange-ftp-default-user term-ansi-at-save-user)
	      (setq ange-ftp-default-password term-ansi-at-save-pwd)
	      (setq ange-ftp-generate-anonymous-password term-ansi-at-save-anon))
	  (setq term-ansi-at-save-user ange-ftp-default-user)
	  (setq term-ansi-at-save-pwd ange-ftp-default-password)
	  (setq term-ansi-at-save-anon ange-ftp-generate-anonymous-password)
	  (setq ange-ftp-default-user nil)
	  (setq ange-ftp-default-password nil)
	  (setq ange-ftp-generate-anonymous-password nil)))))
  message)


;; Terminal emulation
;; This is the standard process filter for term buffers.
;; It emulates (most of the features of) a VT100/ANSI-style terminal.

;; References:
;; [ctlseqs]: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
;; [ECMA-48]: https://www.ecma-international.org/publications/standards/Ecma-048.htm
;; [vt100]: https://vt100.net/docs/vt100-ug/chapter3.html

(defconst term-control-seq-regexp
  (concat
   ;; A control character not matched in a longer sequence below,
   "\\(?:[\x00-\x19\x1C-\x1F]\\|"
   ;; some Emacs specific control sequences, implemented by
   ;; `term-command-hook',
   "\032[^\n]+\n\\|"
   ;; a C1 escape coded character (see [ECMA-48] section 5.3 "Elements
   ;; of the C1 set"),
   "\e\\(?:[DM78c]\\|"
   ;; another Emacs specific control sequence,
   "AnSiT[^\n]+\n\\|"
   ;; OSC (See [ECMA-48] section 8.3.89 "Operation System Command".)
   ;; The spec only allows 0x08-0x0d 0x20-7e, but this regexp also
   ;; allows non-ascii (UTF-8) characters.
   "\\][^\x00-\x07\x0e-\x1f\x7f]*\\(?:\a\\|\e\\\\\\)?\\|"
   ;; or an escape sequence (section 5.4 "Control Sequences"),
   "\\[\\([\x30-\x3F]*\\)[\x20-\x2F]*[\x40-\x7E]\\)\\)")
  "Regexp matching control sequences handled by term.el.")

(defconst term-control-seq-prefix-regexp
  "[\032\e]")

(defconst term--osc-max-bytes (* 32 1024 1024)
  "Limit the length of OSC sequences to keep in memory.")

(defun term-emulate-terminal (proc str)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let* ((i 0) funny
	     decoded-substring
	     save-point save-marker win
	     (inhibit-read-only t)
	     (buffer-undo-list t)
	     (selected (selected-window))
	     last-win
	     (str-length (length str)))
        (save-selected-window

	  (when (marker-buffer term-pending-delete-marker)
	    ;; Delete text following term-pending-delete-marker.
	    (delete-region term-pending-delete-marker (process-mark proc))
	    (set-marker term-pending-delete-marker nil))

	  (when (/= (point) (process-mark proc))
	    (setq save-point (point-marker)))

          (setf term-vertical-motion
                (if (eq (window-buffer) (current-buffer))
                    'vertical-motion
                  'term-buffer-vertical-motion))
          (setq save-marker (copy-marker (process-mark proc)))
	  (goto-char (process-mark proc))

	  (save-restriction
	    ;; If the buffer is in line mode, and there is a partial
	    ;; input line, save the line (by narrowing to leave it
	    ;; outside the restriction ) until we're done with output.
	    (when (and (> (point-max) (process-mark proc))
		       (term-in-line-mode))
	      (narrow-to-region (point-min) (process-mark proc)))

	    (when term-log-buffer
	      (princ str term-log-buffer))
            (when term-terminal-undecoded-bytes
              (setq str (concat term-terminal-undecoded-bytes str))
              (setq str-length (length str))
              (setq term-terminal-undecoded-bytes nil))

            (while (< i str-length)
              (setq funny (string-match term-control-seq-regexp str i))
              (let ((ctl-params (and funny (match-string 1 str)))
                    (ctl-params-end (and funny (match-end 1)))
                    (ctl-end (if funny (match-end 0)
                               (setq funny (string-match term-control-seq-prefix-regexp str i))
                               (if funny
                                   (setq term-terminal-undecoded-bytes
                                         (substring str funny))
                                 (setq funny str-length))
                               ;; The control sequence ends somewhere
                               ;; past the end of this string.
                               (1+ str-length))))
                (when (> funny i)
                  (when term-do-line-wrapping
                    (term-down 1 t)
                    (term-move-to-column 0)
                    (setq term-do-line-wrapping nil))
                  ;; Handle non-control data.  Decode the string before
                  ;; counting characters, to avoid garbling of certain
                  ;; multibyte characters (bug#1006).
                  (setq decoded-substring
                        (decode-coding-string
                         (substring str i funny)
                         locale-coding-system t))
                  ;; Check for multibyte characters that ends
                  ;; before end of string, and save it for
                  ;; next time.
                  (when (= funny str-length)
                    (let ((partial 0)
                          (count (length decoded-substring)))
                      (while (and (< partial count)
                                  (eq (char-charset (aref decoded-substring
                                                          (- count 1 partial)))
                                      'eight-bit))
                        (incf partial))
                      (when (> partial 0)
                        (setq term-terminal-undecoded-bytes
                              (substring decoded-substring (- partial)))
                        (setq decoded-substring
                              (substring decoded-substring 0 (- partial)))
                        (decf str-length partial)
                        (decf funny partial))))

                  ;; Insert a string, check how many columns
                  ;; we moved, then delete that many columns
                  ;; following point if not eob nor insert-mode.
                  (let ((old-column (term-horizontal-column))
                        (old-point (point))
                        columns)
                    (unless term-suppress-hard-newline
                      (while (> (+ (length decoded-substring) old-column)
                                term-width)
                        (let* ((here-length (- term-width old-column))
                               (to-insert (substring decoded-substring 0 here-length)))
                          (setf decoded-substring (substring decoded-substring here-length))
                          (insert to-insert)
                          (setf term-current-column nil)
                          ;; Since we've enough text to fill the whole line,
                          ;; delete previous text regardless of
                          ;; `term-insert-mode's value.
                          (delete-region (point) (line-end-position))
                          (if term-auto-margins
                              (progn
                                (term-move-to-column 0)
                                (term-down 1 t)
                                (add-text-properties (1- (point)) (point)
                                                     '(term-line-wrap t rear-nonsticky t))
                                (setq old-column 0))
                            (term-move-columns -1)
                            (setf old-column (term-current-column))))))
                    (insert decoded-substring)
                    (setq term-current-column (current-column)
                          columns (- term-current-column old-column))
                    (when (not (or (eobp) term-insert-mode))
                      (let ((pos (point)))
                        (term-move-columns columns)
                        (delete-region pos (point))
                        (setq term-current-column nil)))
                    ;; In insert mode if the current line
                    ;; has become too long it needs to be
                    ;; chopped off.
                    (when term-insert-mode
                      (let ((pos (point)))
                        (end-of-line)
                        (when (> (current-column) term-width)
                          (delete-region (- (point) (- (current-column) term-width))
                                         (point)))
                        (goto-char pos)))

                    (put-text-property old-point (point)
                                       'font-lock-face term-current-face))
                  ;; If the last char was written in last column and auto-margins is enabled,
                  ;; back up one column, but remember we did so.
                  ;; Thus we emulate xterm/vt100-style line-wrapping.
                  ;; If auto-margins is disabled, the cursor stays at the last column
                  ;; and further output is discarded until a cursor movement occurs.
                  (when (eq (term-current-column) term-width)
                    (term-move-columns -1)
                    ;; Only set line-wrapping if auto-margins is enabled
                    (when term-auto-margins
                      ;; We check after ctrl sequence handling if point
                      ;; was moved (and leave line-wrapping state if so).
                      (setq term-do-line-wrapping (point))))
                  (setq term-current-column nil)
                  (setq i funny))
                (pcase-exhaustive (and (<= ctl-end str-length) (aref str i))
                  (?\t ;; TAB (terminfo: ht)
                   ;; The line cannot exceed term-width. TAB at
                   ;; the end of a line should not cause wrapping.
                   (let ((col (term-current-column)))
                     (term-move-to-column
                      (min (1- term-width)
                           (+ col 8 (- (mod col 8)))))))
                  (?\r ;; (terminfo: cr)
                   (term-vertical-motion 0)
                   (setq term-current-column term-start-line-column))
                  (?\n ;; (terminfo: cud1, ind)
                   (unless (and term-kill-echo-list
                                (term-check-kill-echo-list))
                     (term-down 1 t)))
                  (?\b ;; (terminfo: cub1)
                   (term-move-columns -1))
                  (?\C-g ;; (terminfo: bel)
                   (beep t))
                  (?\032            ; Emacs specific control sequence.
                   (funcall term-command-function
                            (decode-coding-string
                             (substring str (1+ i)
                                        (- ctl-end
                                           (if (eq (aref str (- ctl-end 2)) ?\r)
                                               2 1)))
                             locale-coding-system t)))
                  (?\e
                   (pcase (aref str (1+ i))
                     (?\[
                      ;; We only handle control sequences with a single
                      ;; "Final" byte (see [ECMA-48] section 5.4).
                      (when (eq ctl-params-end (1- ctl-end))
                        (let* ((private (string-prefix-p "?" ctl-params))
                               (ctl-params
                                (if private (substring ctl-params 1) ctl-params)))
                          (term-handle-ansi-escape
                           proc
                           (mapcar ;; We don't distinguish empty params
                            ;; from 0 (according to [ECMA-48] we
                            ;; should, but all commands we support
                            ;; default to 0 values anyway).
                            #'string-to-number
                            (split-string ctl-params ";"))
                           (aref str (1- ctl-end))
                           private))))
                     (?\] ;; An OSC sequence
                      (let ((seq-str (substring str (+ i 2) ctl-end)))
                        (string-match
                         "\\`\\(\\([0-9A-Za-z]+\\);\\)?.*?\\(\a\\|\e\\\\\\)?\\'"
                         seq-str)
                        (let ((code (match-string 2 seq-str))
                              (text-start (match-end 1))
                              (end-mark (match-beginning 3)))
                          (when (and code end-mark)
                            (when-let* ((func (cdr (or (assoc-string
                                                        code term-osc-handlers)
                                                       (assoc-string
                                                        code ansi-osc-handlers)))))
                              (with-demoted-errors "term OSC error: %S"
                                (funcall
                                 func code
                                 (decode-coding-string
                                  (substring seq-str text-start end-mark)
                                  locale-coding-system t)))))
                          (when (and (not end-mark)
                                     (>= ctl-end str-length)
                                     (< (- ctl-end i) term--osc-max-bytes))
                            ;; Continue ignoring until the end marker.
                            (setq term-terminal-undecoded-bytes
                                  (substring str i)))))
                      ;; Consume everything
                      (setq i ctl-end))
                     (?D ;; Scroll forward (apparently not documented in
                      ;; [ECMA-48], [ctlseqs] mentions it as C1
                      ;; character "Index" though).
                      (term-handle-deferred-scroll)
                      (term-down 1 t))
                     (?M ;; Scroll reversed (terminfo: ri, ECMA-48
                      ;; "Reverse Linefeed").
                      (if (or (< (term-current-row) term-scroll-start)
                              (>= (1- (term-current-row))
                                  term-scroll-start))
                          ;; Scrolling up will not move outside
                          ;; the scroll region.
                          (term-down -1)
                        ;; Scrolling the scroll region is needed.
                        (term-down -1 t)))
                     (?7 ;; Save cursor (terminfo: sc, not in [ECMA-48],
                      ;; [ctlseqs] has it as "DECSC").
                      (term-handle-deferred-scroll)
                      (setq term-saved-cursor
                            (list (term-current-row)
                                  (term-horizontal-column)
                                  term-ansi-current-bg-color
                                  term-ansi-current-bold
                                  term-ansi-current-faint
                                  term-ansi-current-italic
                                  term-ansi-current-underline
                                  term-ansi-current-slow-blink
                                  term-ansi-current-fast-blink
                                  term-ansi-current-color
                                  term-ansi-current-invisible
                                  term-ansi-current-reverse
                                  term-current-face)))
                     (?8 ;; Restore cursor (terminfo: rc, [ctlseqs]
                      ;; "DECRC").
                      (when term-saved-cursor
                        (term-goto (nth 0 term-saved-cursor)
                                   (nth 1 term-saved-cursor))
                        (pcase-setq
                         `( ,_ ,_
                            ,term-ansi-current-bg-color
                            ,term-ansi-current-bold
                            ,term-ansi-current-faint
                            ,term-ansi-current-italic
                            ,term-ansi-current-underline
                            ,term-ansi-current-slow-blink
                            ,term-ansi-current-fast-blink
                            ,term-ansi-current-color
                            ,term-ansi-current-invisible
                            ,term-ansi-current-reverse
                            ,term-current-face)
                         term-saved-cursor)))
                     (?c ;; \Ec - Reset (terminfo: rs1, [ctlseqs] "RIS").
                      ;; This is used by the "clear" program.
                      (term-reset-terminal))
                     (?A ;; An \eAnSiT sequence (Emacs specific).
                      (term-handle-ansi-terminal-messages
                       (substring str i ctl-end)))))
                  ;; Ignore any control character not already recognized.
                  ((or 'nil
                       (and (pred characterp) (pred (lambda (c) (<= c ?\x1F))))) nil))
                ;; Leave line-wrapping state if point was moved.
                (unless (eq term-do-line-wrapping (point))
                  (setq term-do-line-wrapping nil))
                (if (term-handling-pager)
                    (progn
                      ;; Finish stuff to get ready to handle PAGER.
                      (if (> (% (current-column) term-width) 0)
                          (setq term-terminal-undecoded-bytes
                                (substring str i))
                        ;; We're at column 0.  Goto end of buffer; to compensate,
                        ;; prepend a ?\r for later.  This looks more consistent.
                        (if (zerop i)
                            (setq term-terminal-undecoded-bytes
                                  (concat "\r" (substring str i)))
                          (setq term-terminal-undecoded-bytes (substring str (1- i)))
                          (aset term-terminal-undecoded-bytes 0 ?\r))
                        (goto-char (point-max)))
                      ;; FIXME: Use (add-function :override (process-filter proc)
                      (setq-local term-pager-old-filter (process-filter proc))
                      ;; FIXME: Where is `term-pager-filter' set to a function?!
                      (set-process-filter proc term-pager-filter)
                      (setq i str-length))
                  (setq i ctl-end)))))

	  (when (>= (term-current-row) term-height)
	    (term-handle-deferred-scroll))

	  (set-marker (process-mark proc) (point))
          (when (stringp decoded-substring)
            (term-watch-for-password-prompt decoded-substring))
	  (when save-point
	    (goto-char save-point)
	    (set-marker save-point nil))

	  ;; Check for a pending filename-and-line number to display.
	  ;; We do this before scrolling, because we might create a new window.
	  (when (and term-pending-frame
		     (eq (window-buffer selected) (current-buffer)))
	    (term-display-line (car term-pending-frame)
			       (cdr term-pending-frame))
            (setq term-pending-frame nil))

	  ;; Scroll each window displaying the buffer but (by default)
	  ;; only if the point matches the process-mark we started with.
	  (setq win selected)
	  ;; Avoid infinite loop in strange case where minibuffer window
	  ;; is selected but not active.
	  (while (window-minibuffer-p win)
	    (setq win (next-window win nil t)))
	  (setq last-win win)
	  (while (progn
		   (setq win (next-window win nil t))
		   (when (eq (window-buffer win) (process-buffer proc))
		     (let ((scroll term-scroll-to-bottom-on-output))
		       (select-window win t)
		       (when (or (= (point) save-marker)
			         (eq scroll t) (eq scroll 'all)
			         ;; Maybe user wants point to jump to the end.
			         (and (eq selected win)
				      (or (eq scroll 'this) (not save-point)))
			         (and (eq scroll 'others)
				      (not (eq selected win))))
		         (when term-scroll-snap-to-bottom
		           (goto-char term-home-marker)
		           (recenter 0))
		         (goto-char (process-mark proc))
		         (if (not (pos-visible-in-window-p (point) win))
			     (recenter -1)))
		       ;; Optionally scroll so that the text
		       ;; ends at the bottom of the window.
		       (when (and term-scroll-show-maximum-output
				  (>= (point) (process-mark proc))
				  (or term-scroll-snap-to-bottom
				      (not (pos-visible-in-window-p
                                            (point-max) win))))
		         (save-excursion
			   (goto-char (point-max))
			   (recenter -1)))))
		   (not (eq win last-win))))

          ;; Stolen from comint.el and adapted -mm
	  (when (> term-buffer-maximum-size 0)
	    (save-excursion
	      (goto-char (process-mark (get-buffer-process (current-buffer))))
	      (forward-line (- term-buffer-maximum-size))
	      (beginning-of-line)
	      (delete-region (point-min) (point))))
	  (set-marker save-marker nil)))
      ;; This might be expensive, but we need it to handle something
      ;; like `sleep 5 | less -c' in more-or-less real time.
      (when (get-buffer-window (current-buffer))
        (redisplay)))))

(defvar-local term-goto-process-mark t
  "Whether to reset point to the current process mark after this command.

Set in `pre-command-hook' in char mode by `term-set-goto-process-mark'.")

(defun term-set-goto-process-mark ()
  "Set `term-goto-process-mark'.

Always set to nil if `term-char-mode-point-at-process-mark' is nil.

Called as a buffer-local `pre-command-hook' function in
`term-char-mode' so that when point is equal to the process mark
at the pre-command stage, we know to restore point to the process
mark at the post-command stage.

See also `term-goto-process-mark-maybe'."
  (setq term-goto-process-mark
        (and term-char-mode-point-at-process-mark
             (eq (point) (marker-position (term-process-mark))))))

(defun term-goto-process-mark-maybe ()
  "Move point to the term buffer's process mark upon keyboard input.

Called as a buffer-local `post-command-hook' function in
`term-char-mode' to prevent commands from putting the buffer into
an inconsistent state by unexpectedly moving point.

Mouse and wheel events are ignored so that mouse selection and
mouse wheel scrolling are unimpeded.

Only acts when the pre-command position of point was equal to the
process mark, and the `term-char-mode-point-at-process-mark'
option is enabled.  See `term-set-goto-process-mark'."
  (when term-goto-process-mark
    (unless (or (mouse-event-p last-command-event)
                (memq (event-basic-type last-command-event)
                      '(wheel-down wheel-up)))
      (goto-char (term-process-mark)))))

(defun term-process-mark ()
  "The current `process-mark' for the term buffer process."
  (process-mark (get-buffer-process (current-buffer))))

(defun term-handle-deferred-scroll ()
  (let ((count (- (term-current-row) term-height)))
    (when (>= count 0)
      (save-excursion
	(goto-char term-home-marker)
	(term-vertical-motion (1+ count))
	(set-marker term-home-marker (point))
	(setq term-current-row (term--last-line))))))

(defun term-reset-terminal ()
  "Reset the terminal, delete all the content and set the face to the default one."
  (erase-buffer)
  (term-ansi-reset)
  (setq term-current-row 0)
  (setq term-current-column 1)
  (term--reset-scroll-region)
  (setq term-insert-mode nil)
  (setq term-auto-margins t))

(defun term--color-as-hex (for-foreground)
  "Return the current ANSI color as a hexadecimal color string.
Use the current background color if FOR-FOREGROUND is nil,
otherwise use the current foreground color.  Return nil if the
color is unset in the terminal state."
  (let ((color (if for-foreground term-ansi-current-color
                 term-ansi-current-bg-color)))
    (when color
      (or (ansi-color--code-as-hex (1- color))
          (progn
            (and ansi-color-bold-is-bright term-ansi-current-bold
                 (<= 1 color 8)
                 (setq color (+ color 8)))
            (if for-foreground
                (face-foreground (elt ansi-term-color-vector color)
                                 nil 'default)
              (face-background (elt ansi-term-color-vector color)
                               nil 'default)))))))

;; New function to deal with ansi colorized output, as you can see you can
;; have any bold/underline/fg/bg/reverse combination. -mm

(defun term-handle-colors-array (parameter)
  (declare (obsolete term--handle-colors-list "29.1"))
  (term--handle-colors-list (list parameter)))

(defun term--handle-colors-list (parameters)
  (while parameters
    (pcase (pop parameters)
      (1 (setq term-ansi-current-bold t))       ; (terminfo: bold)
      (2 (setq term-ansi-current-faint t))      ; (terminfo: dim)
      (3 (setq term-ansi-current-italic t))     ; (terminfo: sitm)
      (4 (setq term-ansi-current-underline t))  ; (terminfo: smul)
      (5 (setq term-ansi-current-slow-blink t)) ; (terminfo: blink)
      (6 (setq term-ansi-current-fast-blink t))
      (7 (setq term-ansi-current-reverse t))    ; (terminfo: smso, rev)
      (8 (setq term-ansi-current-invisible t))  ; (terminfo: invis)
      (21 (setq term-ansi-current-bold nil))
      (22 (setq term-ansi-current-bold nil)
          (setq term-ansi-current-faint nil))
      (23 (setq term-ansi-current-italic nil))    ; (terminfo: ritm)
      (24 (setq term-ansi-current-underline nil)) ; (terminfo: rmul)
      (25 (setq term-ansi-current-slow-blink nil)
          (setq term-ansi-current-fast-blink nil))
      (27 (setq term-ansi-current-reverse nil)) ; (terminfo: rmso)

      ;; Foreground (terminfo: setaf)
      ((and param (guard (<= 30 param 37)))
       (setq term-ansi-current-color (- param 29)))

      ;; Bright foreground (terminfo: setaf)
      ((and param (guard (<= 90 param 97)))
       (setq term-ansi-current-color (- param 81)))

      ;; Extended foreground (terminfo: setaf)
      (38
       (pcase (pop parameters)
         ;; 256 color
         (5 (if (setq term-ansi-current-color (pop parameters))
                (incf term-ansi-current-color)
              (term-ansi-reset)))
         ;; Full 24-bit color
         (2 (cl-loop with color = (1+ 256) ; Base
                     for i from 16 downto 0 by 8
                     if (pop parameters)
                     do (setq color (+ color (ash it i)))
                     else return (term-ansi-reset)
                     finally
                     (if (> color (+ 1 256 #xFFFFFF))
                         (term-ansi-reset)
                       (setq term-ansi-current-color color))))
         (_ (term-ansi-reset))))

      ;; Reset foreground (terminfo: op)
      (39 (setq term-ansi-current-color nil))

      ;; Background (terminfo: setab)
      ((and param (guard (<= 40 param 47)))
       (setq term-ansi-current-bg-color (- param 39)))

      ;; Bright background (terminfo: setab)
      ((and param (guard (<= 100 param 107)))
       (setq term-ansi-current-bg-color (- param 91)))

      ;; Extended background (terminfo: setab)
      (48
       (pcase (pop parameters)
         ;; 256 color
         (5 (if (setq term-ansi-current-bg-color (pop parameters))
                (incf term-ansi-current-bg-color)
              (term-ansi-reset)))
         ;; Full 24-bit color
         (2 (cl-loop with color = (1+ 256) ; Base
                     for i from 16 downto 0 by 8
                     if (pop parameters)
                     do (setq color (+ color (ash it i)))
                     else return (term-ansi-reset)
                     finally
                     (if (> color (+ 1 256 #xFFFFFF))
                         (term-ansi-reset)
                       (setq term-ansi-current-bg-color color))))
         (_ (term-ansi-reset))))

      ;; Reset background (terminfo: op)
      (49 (setq term-ansi-current-bg-color nil))

      ;; 0 (Reset) (terminfo: sgr0) or unknown (reset anyway)
      (_ (term-ansi-reset))))

  (let (fg bg)
    (if term-ansi-current-invisible
        (setq bg (term--color-as-hex term-ansi-current-reverse)
              fg bg)
      (setq fg (term--color-as-hex t)
            bg (term--color-as-hex nil)))
    (setq term-current-face
          `(,@(when fg `(:foreground ,fg))
            ,@(when bg `(:background ,bg))
            ,@(when (and term-ansi-current-reverse
                         (not term-ansi-current-invisible))
                (list :inverse-video term-ansi-current-reverse)))))

  (setq term-current-face
        `(,term-current-face
          ,@(when term-ansi-current-bold
              '(term-bold))
          ,@(when term-ansi-current-faint
              '(term-faint))
          ,@(when term-ansi-current-italic
              '(term-italic))
          ,@(when term-ansi-current-underline
              '(term-underline))
          ,@(when term-ansi-current-slow-blink
              '(term-slow-blink))
          ,@(when term-ansi-current-fast-blink
              '(term-fast-blink)))))


;; Handle a character assuming (eq terminal-state 2) -
;; i.e. we have previously seen Escape followed by ?[.

(defun term-handle-ansi-escape (proc params char &optional private)
  (cond
   ((and private (not (memq char '(?h ?l))))
    ;; Recognize private capabilities only for mode entry and exit
    nil)
   ((or (eq char ?H)  ;; cursor motion (terminfo: cup,home)
	;; (eq char ?f) ;; xterm seems to handle this sequence too, not
	;; needed for now
	)
    (term-goto
     (1- (max 1 (min (or (nth 0 params) 0) term-height)))
     (1- (max 1 (min (or (nth 1 params) 0) term-width)))))
   ;; \E[A - cursor up (terminfo: cuu, cuu1)
   ((eq char ?A)
    (term-handle-deferred-scroll)
    (let ((tcr (term-current-row))
          (scroll-amount (car params)))
      (term-down
       (if (< (- tcr scroll-amount) term-scroll-start)
	   ;; If the amount to move is before scroll start, move
	   ;; to scroll start.
	   (- term-scroll-start tcr)
         (if (>= scroll-amount tcr)
	     (- tcr)
           (- (max 1 scroll-amount))))
       t)))
   ;; \E[B - cursor down (terminfo: cud)
   ((eq char ?B)
    (let ((tcr (term-current-row))
          (scroll-amount (car params)))
      (unless (>= tcr term-scroll-end)
	(term-down
         (min (- term-scroll-end tcr) (max 1 scroll-amount))
         t))))
   ;; \E[C - cursor right (terminfo: cuf, cuf1)
   ((eq char ?C)
    (term-move-columns
     (max 1
          (if (>= (+ (car params) (term-current-column)) term-width)
	      (- term-width (term-current-column)  1)
            (car params)))))
   ;; \E[D - cursor left (terminfo: cub)
   ((eq char ?D)
    (term-move-columns (- (max 1 (car params)))))
   ;; \E[G - cursor motion to absolute column (terminfo: hpa)
   ((eq char ?G)
    (term-move-columns (- (max 0 (min term-width (car params)))
                          (term-current-column))))
   ;; \E[J - clear to end of screen (terminfo: ed, clear)
   ((eq char ?J)
    (term-erase-in-display (car params)))
   ;; \E[K - clear to end of line (terminfo: el, el1)
   ((eq char ?K)
    (term-erase-in-line (car params)))
   ;; \E[L - insert lines (terminfo: il, il1)
   ((eq char ?L)
    (term-insert-lines (max 1 (car params))))
   ;; \E[M - delete lines (terminfo: dl, dl1)
   ((eq char ?M)
    (term-delete-lines (max 1 (car params))))
   ;; \E[P - delete chars (terminfo: dch, dch1)
   ((eq char ?P)
    (term-delete-chars (max 1 (car params))))
   ;; \E[@ - insert spaces (terminfo: ich)
   ((eq char ?@)
    (term-insert-spaces (max 1 (car params))))
   ;; \E[?h - DEC Private Mode Set

   ;; N.B. we previously had a bug in which we'd decode \e[?<NR>h or
   ;; \e[?<NR>l as a command with zero in the params field and so
   ;; didn't recognize DEC private escape sequences.  However, the
   ;; termcap and terminfo files had the non-? (question mark means DEC
   ;; private) versions, so things kind of worked anyway.  To preserve
   ;; compatibility, we recognize both private- and non-private
   ;; messages for capabilities we added before we fixed the bug but
   ;; require the private flag for capabilities we added after.
   ((eq char ?h)
    (cond ((eq (car params) 4) ;; (terminfo: smir)
           (setq term-insert-mode t))
          ((and private (eq (car params) 7)) ;; (terminfo: smam)
           (setq term-auto-margins t))
          ((eq (car params) 47) ;; (terminfo: smcup)
           (term-switch-to-alternate-sub-buffer t))))
   ;; \E[?l - DEC Private Mode Reset
   ((eq char ?l)
    (cond ((eq (car params) 4) ;; (terminfo: rmir)
           (setq term-insert-mode nil))
          ((and private (eq (car params) 7)) ;; (terminfo: rmam)
           (setq term-auto-margins nil))
          ((eq (car params) 47) ;; (terminfo: rmcup)
           (term-switch-to-alternate-sub-buffer nil))))

   ;; Modified to allow ansi coloring -mm
   ;; \E[m - Set/reset modes, set bg/fg
   ;;(terminfo: smso,rmso,smul,rmul,rev,bold,dim,sitm,ritm,blink,sgr0,invis,op,setab,setaf)
   ((eq char ?m)
    (term--handle-colors-list params))

   ;; \E[6n - Report cursor position (terminfo: u7)
   ((eq char ?n)
    (term-handle-deferred-scroll)
    (process-send-string proc
			 ;; (terminfo: u6)
			 (format "\e[%s;%sR"
				 (1+ (term-current-row))
				 (1+ (term-horizontal-column)))))
   ;; \E[r - Set scrolling region (terminfo: csr)
   ((eq char ?r)
    (term-set-scroll-region
     (1- (or (nth 0 params) 0))
     (1- (or (nth 1 params) 0))))
   (t)))

(defun term--reset-scroll-region ()
  "Set the scroll region to the full height of the terminal."
  (term-set-scroll-region 0 (term--last-line)))

(defun term-set-scroll-region (top bottom)
  "Set scrolling region.
TOP is the top-most line (inclusive) of the new scrolling region,
while BOTTOM is the line following the new scrolling region (e.g. exclusive).
The top-most line is line 0."
  (setq term-scroll-start
	(if (or (< top 0) (>= top term-height))
	    0
	  top))
  (setq term-scroll-end
	(if (or (<= bottom term-scroll-start) (> bottom (term--last-line)))
	    (term--last-line)
	  bottom))
  (setq term-scroll-with-delete
	(or (term-using-alternate-sub-buffer)
	    (not (and (= term-scroll-start 0)
                      (= term-scroll-end (term--last-line))))))
  (term-move-columns (- (term-current-column)))
  (term-goto 0 0))

(defun term-switch-to-alternate-sub-buffer (set)
  ;; If asked to switch to (from) the alternate sub-buffer, and already (not)
  ;; using it, do nothing.  This test is needed for some programs (including
  ;; Emacs) that emit the ti termcap string twice, for unknown reason.
  (term-handle-deferred-scroll)
  (when (eq set (not (term-using-alternate-sub-buffer)))
    (cond
     (set
      (goto-char (point-max))
      (if (not (eq (preceding-char) ?\n))
          (term-insert-char ?\n 1))
      (setq term-scroll-with-delete t)
      (setq term-saved-home-marker (copy-marker term-home-marker))
      (set-marker term-home-marker (point)))
     (t
      (setq term-scroll-with-delete
            (not (and (= term-scroll-start 0)
                      (= term-scroll-end (term--last-line)))))
      (goto-char (point-max))
      (when term-clear-full-screen-programs
        (delete-region term-home-marker (point))
        (set-marker term-home-marker term-saved-home-marker))
      (set-marker term-saved-home-marker nil)
      (setq term-saved-home-marker nil)))

    (setq term-start-line-column nil)
    (setq term-current-column nil)
    (setq term-current-row nil)
    (term-handle-deferred-scroll)))

;; Default value for the symbol term-command-function.

(defun term-command-hook (string)
  (cond ((equal string "")
	 t)
	((= (aref string 0) ?\032)
	 ;; gdb (when invoked with -fullname) prints:
	 ;; \032\032FULLFILENAME:LINENUMBER:CHARPOS:BEG_OR_MIDDLE:PC\n
	 (let* ((first-colon (string-search ":" string 1))
		(second-colon
		 (string-search ":" string (1+ first-colon)))
		(filename (substring string 1 first-colon))
		(fileline (string-to-number
			   (substring string (1+ first-colon) second-colon))))
	   (setq term-pending-frame (cons filename fileline))))
	((= (aref string 0) ?/)
	 (cd (substring string 1)))
	;; Allowing the inferior to call functions in Emacs is
	;; probably too big a security hole.
	;; ((= (aref string 0) ?!)
	;; (eval (car (read-from-string string 1))))
	(t)));; Otherwise ignore it

;; Make sure the file named TRUE-FILE is in a buffer that appears on the screen
;; and that its line LINE is visible.
;; Put the overlay-arrow on the line LINE in that buffer.
;; This is mainly used by gdb.

(defun term-display-line (true-file line)
  (term-display-buffer-line (find-file-noselect true-file) line))

(defun term-display-buffer-line (buffer line)
  (let* ((window (display-buffer buffer t))
	 (pos))
    (with-current-buffer buffer
      (save-restriction
	(widen)
	(goto-char (point-min))
	(forward-line (1- line))
	(setq pos (point))
	(setq overlay-arrow-string "=>")
	(or overlay-arrow-position
	    (setq overlay-arrow-position (make-marker)))
	(set-marker overlay-arrow-position (point) (current-buffer)))
      (cond ((or (< pos (point-min)) (> pos (point-max)))
	     (widen)
	     (goto-char pos))))
    (set-window-point window overlay-arrow-position)))

;; The buffer-local marker term-home-marker defines the "home position"
;; (in terms of cursor motion).  However, we move the term-home-marker
;; "down" as needed so that is no more that a window-full above (point-max).

(defun term-goto-home ()
  (term-handle-deferred-scroll)
  (goto-char term-home-marker)
  (setq term-current-row 0)
  (setq term-current-column (current-column))
  (setq term-start-line-column term-current-column))

(defun term-goto (row col)
  (term-handle-deferred-scroll)
  (cond ((and term-current-row (>= row term-current-row))
	 ;; I assume this is a worthwhile optimization.
	 (term-vertical-motion 0)
	 (setq term-current-column term-start-line-column)
	 (setq row (- row term-current-row)))
	(t
	 (term-goto-home)))
  (term-down row)
  (term-move-columns col))

;; The page is full, so enter "pager" mode, and wait for input.

(defun term-process-pager ()
  ;; (let ((process (get-buffer-process (current-buffer))))
  ;;   (stop-process process))
  (setq term-pager-old-local-map (current-local-map))
  (use-local-map term-pager-break-map)
  (setq-local term-old-mode-line-format mode-line-format)
  (setq mode-line-format
	(list "--  **MORE**  "
	      mode-line-buffer-identification
	      " [Type ? for help] "
	      "%-"))
  (force-mode-line-update))

(defun term-pager-line (lines)
  (interactive "p")
  (let* ((moved (vertical-motion (1+ lines)))
	 (deficit (- lines moved)))
    (when (> moved lines)
      (backward-char))
    (cond ((<= deficit 0) ;; OK, had enough in the buffer for request.
	   (recenter (term--last-line)))
	  ((term-pager-continue deficit)))))

(defun term-pager-page (arg)
  "Proceed past the **MORE** break, allowing the next page of output to appear."
  (interactive "p")
  (term-pager-line (* arg term-height)))

;; Pager mode command to go to beginning of buffer.
(defun term-pager-bob ()
  (interactive)
  (goto-char (point-min))
  (when (= (vertical-motion term-height) term-height)
    (backward-char))
  (recenter (term--last-line)))

;; Pager mode command to go to end of buffer.
(defun term-pager-eob ()
  (interactive)
  (goto-char term-home-marker)
  (recenter 0)
  (goto-char (process-mark (get-buffer-process (current-buffer)))))

(defun term-pager-back-line (lines)
  (interactive "p")
  (vertical-motion (- 1 lines))
  (if (not (bobp))
      (backward-char)
    (beep)
    ;; Move cursor to end of window.
    (vertical-motion term-height)
    (backward-char))
  (recenter (term--last-line)))

(defun term-pager-back-page (arg)
  (interactive "p")
  (term-pager-back-line (* arg term-height)))

(defun term-pager-discard ()
  (interactive)
  (setq term-terminal-undecoded-bytes "")
  (interrupt-process nil t)
  (term-pager-continue term-height))

;; Disable pager processing.
;; Only callable while in pager mode.  (Contrast term-disable-pager.)
(defun term-pager-disable ()
  (interactive)
  (if (term-handling-pager)
      (term-pager-continue nil)
    (setq term-pager-count nil))
  (term-update-mode-line))

;; Enable pager processing.
(defun term-pager-enable ()
  (interactive)
  (or (term-pager-enabled)
      (setq term-pager-count 0)) ;; Or maybe set to (term-current-row) ??
  (term-update-mode-line))

(defun term-pager-toggle ()
  (interactive)
  (if (term-pager-enabled) (term-pager-disable) (term-pager-enable)))

(defun term-pager-help ()
  "Provide help on commands available in a terminal-emulator **MORE** break."
  (interactive)
  (message "Terminal-emulator pager break help...")
  (sit-for 0)
  (with-electric-help
    (lambda ()
      (princ (substitute-command-keys
"\\<term-pager-break-map>\
Terminal-emulator MORE break.\n\
Type one of the following keys:\n\n\
\\[term-pager-page]\t\tMove forward one page.\n\
\\[term-pager-line]\t\tMove forward one line.\n\
\\[universal-argument] N \\[term-pager-page]\tMove N pages forward.\n\
\\[universal-argument] N \\[term-pager-line]\tMove N lines forward.\n\
\\[universal-argument] N \\[term-pager-back-line]\tMove N lines back.\n\
\\[universal-argument] N \\[term-pager-back-page]\t\tMove N pages back.\n\
\\[term-pager-bob]\t\tMove to the beginning of the buffer.\n\
\\[term-pager-eob]\t\tMove to the end of the buffer.\n\
\\[term-pager-discard]\t\tKill pending output and kill process.\n\
\\[term-pager-disable]\t\tDisable PAGER handling.\n\n\
\\{term-pager-break-map}\n\
Any other key is passed through to the program
running under the terminal emulator and disables pager processing until
all pending output has been dealt with."))
      nil)))

(defun term-pager-continue (new-count)
  (let ((process (get-buffer-process (current-buffer))))
    (use-local-map term-pager-old-local-map)
    (setq term-pager-old-local-map nil)
    (setq mode-line-format term-old-mode-line-format)
    (force-mode-line-update)
    (setq term-pager-count new-count)
    (set-process-filter process term-pager-old-filter)
    (funcall term-pager-old-filter process "")
    (continue-process process)))

;; Make sure there are DOWN blank lines below the current one.
;; Return 0 if we're unable (because of PAGER handling), else return DOWN.

(defun term-handle-scroll (down)
  (let ((scroll-needed
	 (- (+ (term-current-row) down)
	    (if (< down 0) term-scroll-start term-scroll-end))))
    (when (or (and (< down 0) (< scroll-needed 0))
	      (and (> down 0) (> scroll-needed 0)))
      (let ((save-point (point-marker)) (save-top))
	(goto-char term-home-marker)
	(cond (term-scroll-with-delete
	       (if (< down 0)
		   (progn
		     ;; Delete scroll-needed lines at term-scroll-end,
		     ;; then insert scroll-needed lines.
		     (term-vertical-motion term-scroll-end)
		     (end-of-line)
		     (setq save-top (point))
		     (term-vertical-motion scroll-needed)
		     (end-of-line)
		     (delete-region save-top (point))
		     (goto-char save-point)
		     (setq down (- scroll-needed down))
		     (term-vertical-motion down))
		 ;; Delete scroll-needed lines at term-scroll-start.
		 (term-vertical-motion term-scroll-start)
		 (setq save-top (point))
		 (term-vertical-motion scroll-needed)
		 (delete-region save-top (point))
		 (goto-char save-point)
		 (term-vertical-motion down)
		 (term-adjust-current-row-cache (- scroll-needed)))
	       (setq term-current-column nil)
	       (term-insert-char ?\n (abs scroll-needed)))
	      ((and (numberp term-pager-count)
		    (< (setq term-pager-count (- term-pager-count down))
		       0))
	       (setq down 0)
	       (term-process-pager))
	      (t
	       (term-adjust-current-row-cache (- scroll-needed))
	       (term-vertical-motion scroll-needed)
	       (set-marker term-home-marker (point))))
	(goto-char save-point)
	(set-marker save-point nil))))
  down)

(defun term-down (down &optional check-for-scroll)
  "Move down DOWN screen lines vertically."
  (let ((start-column (term-horizontal-column)))
    (when (and check-for-scroll (or term-scroll-with-delete term-pager-count))
      (setq down (term-handle-scroll down)))
    (unless (and (= (term-current-row) 0) (< down 0))
      (term-adjust-current-row-cache down)
      (when (or (/= (point) (point-max)) (< down 0))
	(setq down (- down (term-vertical-motion down)))))
    (cond ((>= down 0)
	   ;; Extend buffer with extra blank lines if needed.
	   (term-insert-char ?\n down)
	   (setq term-current-column 0)
	   (setq term-start-line-column 0))
	  (t
	   (when (= (term-current-row) 0)
	     ;; Insert lines if at the beginning.
	     (save-excursion (term-insert-char ?\n (- down)))
	     (save-excursion
	       (let (p)
		 ;; Delete lines from the end.
		 (forward-line term-height)
		 (setq p (point))
		 (forward-line (- down))
		 (delete-region p (point)))))
	   (setq term-current-column 0)
	   (setq term-start-line-column (current-column))))
    (when start-column
      (term-move-columns start-column))))

;; Assuming point is at the beginning of a screen line,
;; if the line above point wraps around, add a ?\n to undo the wrapping.
;; FIXME:  Probably should be called more than it is.
(defun term-unwrap-line ()
  (when (not (bolp))
    (let ((old-point (point)))
      (insert-before-markers ?\n)
      (add-text-properties old-point (point)
                           '(term-line-wrap t rear-nonsticky t)))))

(defun term-erase-in-line (kind)
  (when (>= kind 1) ;; erase left of point
    (let ((cols (term-horizontal-column)) (saved-point (point)))
      (term-vertical-motion 0)
      (delete-region (point) saved-point)
      (term-insert-char ?  cols)))
  (when (not (eq kind 1)) ;; erase right of point
    (let ((saved-point (point))
	  (wrapped (and (zerop (term-horizontal-column))
			(not (zerop (term-current-column))))))
      (term-vertical-motion 1)
      ;; Do nothing if we have nothing to delete
      (unless (and (eq saved-point (1- (point)))
                   (eq (char-before) ?\n)
                   (not wrapped))
        ;; Insert before deletion to preserve markers.
        ;; wrapped is true if we're at the beginning of screen line,
        ;; but not a buffer line.  If we delete the current screen line
        ;; that will make the previous line no longer wrap, and (because
        ;; of the way Emacs display works) point will be at the end of
        ;; the previous screen line rather then the beginning of the
        ;; current one.  To avoid that, we make sure that current line
        ;; contain a space, to force the previous line to continue to wrap.
        ;; We could do this always, but it seems preferable to not add the
        ;; extra space when wrapped is false.
        (when wrapped
	  (insert-before-markers ? ))
        (insert-before-markers ?\n)
        (delete-region saved-point (point)))
      (put-text-property saved-point (point) 'font-lock-face 'default)
      (goto-char saved-point))))

(defun term-erase-in-display (kind)
  "Erase (that is blank out) part of the window.
If KIND is 0, erase from point to point-max;
if KIND is 1, erase from home to point; else erase from home to point-max."
  (term-handle-deferred-scroll)
  (cond ((eq kind 0)
	 (let ((need-unwrap (bolp)))
	   (delete-region (point) (point-max))
	   (when need-unwrap (term-unwrap-line))))
	((let ((row (term-current-row))
	      (col (term-horizontal-column))
	      (start-region term-home-marker)
	      (end-region (if (eq kind 1) (point) (point-max))))
	   (delete-region start-region end-region)
	   (term-unwrap-line)
	   (when (eq kind 1)
	     (term-insert-char ?\n row))
	   (setq term-current-column nil)
	   (setq term-current-row nil)
	   (term-goto row col)))))

(defun term-delete-chars (count)
  (let ((save-point (point)))
    (term-vertical-motion 1)
    (term-unwrap-line)
    (goto-char save-point)
    (move-to-column (+ (term-current-column) count) t)
    (delete-region save-point (point))))

;; Insert COUNT spaces after point, but do not change any of
;; following screen lines.  Hence we may have to delete characters
;; at the end of this screen line to make room.

(defun term-insert-spaces (count)
  (let ((save-point (point)) (save-eol) (pnt-at-eol))
    (term-vertical-motion 1)
    (when (bolp)
      (backward-char))
    (setq save-eol (point)
          pnt-at-eol (line-end-position))
    (move-to-column (+ (term-start-line-column) (- term-width count)) t)
    ;; If move-to-column extends the current line it will use the face
    ;; from the last character on the line, set the face for the chars
    ;; to default.
    (when (>= (point) pnt-at-eol)
      (put-text-property pnt-at-eol (point) 'font-lock-face 'default))
    (when (> save-eol (point))
      (delete-region (point) save-eol))
    (goto-char save-point)
    (term-insert-char ?  count)
    (goto-char save-point)))

(defun term-delete-lines (lines)
  (let ((start (point))
	(save-current-column term-current-column)
	(save-start-line-column term-start-line-column)
	(save-current-row (term-current-row)))
    ;; The number of inserted lines shouldn't exceed the scroll region end.
    ;; The `term-scroll-end' line is part of the scrolling region, so
    ;; we need to go one line past it in order to ensure correct
    ;; scrolling.
    (when (> (+ save-current-row lines) (1+ term-scroll-end))
      (setq lines (- lines (- (+ save-current-row lines) (1+ term-scroll-end)))))
    (term-down lines)
    (delete-region start (point))
    (term-down (- (1+ term-scroll-end) save-current-row lines))
    (term-insert-char ?\n lines)
    (setq term-current-column save-current-column)
    (setq term-start-line-column save-start-line-column)
    (setq term-current-row save-current-row)
    (goto-char start)))

(defun term-insert-lines (lines)
  (let ((start (point))
	(start-deleted)
	(save-current-column term-current-column)
	(save-start-line-column term-start-line-column)
	(save-current-row (term-current-row)))
    ;; Inserting lines should take into account the scroll region.
    ;; The `term-scroll-end' line is part of the scrolling region, so
    ;; we need to go one line past it in order to ensure correct
    ;; scrolling.
    (if (< save-current-row term-scroll-start)
	;; If point is before scroll start,
	(progn
	  (setq lines (- lines (- term-scroll-start save-current-row)))
	  (term-down (- term-scroll-start save-current-row))
	  (setq start (point)))
      ;; The number of inserted lines shouldn't exceed the scroll region end.
      (when (> (+ save-current-row lines) (1+ term-scroll-end))
	(setq lines (- lines (- (+ save-current-row lines)(1+ term-scroll-end)))))
      (term-down (- (1+ term-scroll-end) save-current-row lines)))
    (setq start-deleted (point))
    (term-down lines)
    (delete-region start-deleted (point))
    (goto-char start)
    (setq term-current-column save-current-column)
    (setq term-start-line-column save-start-line-column)
    (setq term-current-row save-current-row)
    (term-insert-char ?\n lines)
    (goto-char start)))

(defun term-start-output-log (name)
  "Record raw inferior process output in a buffer."
  (interactive (list (if term-log-buffer
			 nil
		       (read-buffer "Record output in buffer: "
				    (format "%s output-log"
					    (buffer-name (current-buffer)))
				    nil))))
  (if (or (null name) (equal name ""))
      (progn (setq term-log-buffer nil)
	     (message "Output logging off."))
    (if (get-buffer name)
	nil
      (with-current-buffer (get-buffer-create name)
	(fundamental-mode)
	(buffer-disable-undo (current-buffer))
	(erase-buffer)))
    (setq term-log-buffer (get-buffer name))
    (message "Recording terminal emulator output into buffer \"%s\""
	     (buffer-name term-log-buffer))))

(defun term-stop-output-log ()
  "Discontinue raw inferior process logging."
  (interactive)
  (term-start-output-log nil))

(defun term-show-maximum-output ()
  "Put the end of the buffer at the bottom of the window."
  (interactive)
  (goto-char (point-max))
  (recenter -1))

;;; Do the user's customization...

(defvar term-load-hook nil
  "This hook is run when term is loaded in.
This is a good place to put keybindings.")

(run-hooks 'term-load-hook)


;;; Filename/command/history completion in a buffer
;; ===========================================================================
;; Useful completion functions, courtesy of the Ergo group.

;; Six commands:
;; term-dynamic-complete		Complete or expand command, filename,
;;					history at point.
;; term-dynamic-complete-filename	Complete filename at point.
;; term-dynamic-list-filename-completions List completions in help buffer.
;; term-replace-by-expanded-filename	Expand and complete filename at point;
;;					replace with expanded/completed name.

;; These are not installed in the term-mode keymap.  But they are
;; available for people who want them.  Shell-mode installs them:
;; (keymap-set shell-mode-map "TAB" 'term-dynamic-complete)
;; (keymap-set shell-mode-map "M-?"
;;             'term-dynamic-list-filename-completions)))
;;
;; Commands like this are fine things to put in load hooks if you
;; want them present in specific modes.

(defcustom term-completion-autolist nil
  "If non-nil, automatically list possibilities on partial completion.
This mirrors the optional behavior of tcsh."
  :group 'term
  :type 'boolean)

(defcustom term-completion-addsuffix t
  "If non-nil, add a `/' to completed directories, ` ' to file names.
If a cons pair, it should be of the form (DIRSUFFIX . FILESUFFIX) where
DIRSUFFIX and FILESUFFIX are strings added on unambiguous or exact
completion.  This mirrors the optional behavior of tcsh."
  :group 'term
  :type '(choice (const :tag "No suffix" nil)
                 (cons (string :tag "dirsuffix") (string :tag "filesuffix"))
                 (other :tag "Suffix" t)))

(defcustom term-completion-recexact nil
  "If non-nil, use shortest completion if characters cannot be added.
This mirrors the optional behavior of tcsh.

A non-nil value is useful if `term-completion-autolist' is non-nil too."
  :group 'term
  :type 'boolean)

(defcustom term-completion-fignore nil
  "List of suffixes to be disregarded during file completion.
This mirrors the optional behavior of bash and tcsh.

Note that this applies to `term-dynamic-complete-filename' only."
  :group 'term
  :type '(choice (const nil)
                 (repeat :tag "List of suffixes" string)))

(defvar term-file-name-prefix ""
  "Prefix prepended to absolute file names taken from process input.
This is used by term's and shell's completion functions, and by shell's
directory tracking functions.")


(defun term-directory (directory)
  ;; Return expanded DIRECTORY, with `term-file-name-prefix' if absolute.
  (expand-file-name (if (file-name-absolute-p directory)
			(concat term-file-name-prefix directory)
		      directory)))


(defun term-word (word-chars)
  "Return the word of WORD-CHARS at point, or nil if none is found.
Word constituents are considered to be those in WORD-CHARS, which is like the
inside of a \"[...]\" (see `skip-chars-forward')."
  (save-excursion
    (let ((limit (point))
	  (word (concat "[" word-chars "]"))
	  (non-word (concat "[^" word-chars "]")))
      (when (re-search-backward non-word nil 'move)
	(forward-char 1))
      ;; Anchor the search forwards.
      (if (or (eolp) (looking-at non-word))
	  nil
	(re-search-forward (concat word "+") limit)
	(buffer-substring (match-beginning 0) (match-end 0))))))


(defun term-match-partial-filename ()
  "Return the filename at point, or nil if none is found.
Environment variables are substituted.  See `term-word'."
  (let ((filename (term-word "~/A-Za-z0-9+@:_.$#,={}-")))
    (and filename (substitute-in-file-name filename))))


(defun term-dynamic-complete ()
  "Dynamically perform completion at point.
Calls the functions in `term-dynamic-complete-functions' to perform
completion until a function returns non-nil, at which point completion is
assumed to have occurred."
  (interactive)
  (run-hook-with-args-until-success 'term-dynamic-complete-functions))


(defun term-dynamic-complete-filename ()
  "Dynamically complete the filename at point.
Completes if after a filename.  See `term-match-partial-filename' and
`term-dynamic-complete-as-filename'.
This function is similar to `term-replace-by-expanded-filename', except that
it won't change parts of the filename already entered in the buffer; it just
adds completion characters to the end of the filename.  A completions listing
may be shown in a help buffer if completion is ambiguous.

Completion is dependent on the value of `term-completion-addsuffix',
`term-completion-recexact' and `term-completion-fignore', and the timing of
completions listing is dependent on the value of `term-completion-autolist'.

Returns t if successful."
  (interactive)
  (when (term-match-partial-filename)
    (prog2 (or (eq (selected-window) (minibuffer-window))
	       (message "Completing file name..."))
	(term-dynamic-complete-as-filename))))

(defun term-dynamic-complete-as-filename ()
  "Dynamically complete at point as a filename.
See `term-dynamic-complete-filename'.  Returns t if successful."
  (let* ((completion-ignore-case nil)
	 (completion-ignored-extensions term-completion-fignore)
	 (success t)
	 (dirsuffix (cond ((not term-completion-addsuffix) "")
			  ((not (consp term-completion-addsuffix)) "/")
			  (t (car term-completion-addsuffix))))
	 (filesuffix (cond ((not term-completion-addsuffix) "")
			   ((not (consp term-completion-addsuffix)) " ")
			   (t (cdr term-completion-addsuffix))))
	 (filename (or (term-match-partial-filename) ""))
	 (pathdir (file-name-directory filename))
	 (pathnondir (file-name-nondirectory filename))
	 (directory (if pathdir (term-directory pathdir) default-directory))
	 (completion (file-name-completion pathnondir directory))
	 (mini-flag (eq (selected-window) (minibuffer-window))))
    (cond ((null completion)
           (message "No completions of %s" filename)
	   (setq success nil))
          ((eq completion t)            ; Means already completed "file".
           (when term-completion-addsuffix (insert " "))
           (or mini-flag (message "Sole completion")))
          ((string-equal completion "") ; Means completion on "directory/".
           (term-dynamic-list-filename-completions))
          (t                            ; Completion string returned.
           (let ((file (concat (file-name-as-directory directory) completion)))
             (insert (substring (directory-file-name completion)
                                (length pathnondir)))
             (cond ((symbolp (file-name-completion completion directory))
                    ;; We inserted a unique completion.
		    (insert (if (file-directory-p file) dirsuffix filesuffix))
                    (or mini-flag (message "Completed")))
                   ((and term-completion-recexact term-completion-addsuffix
                         (string-equal pathnondir completion)
                         (file-exists-p file))
                    ;; It's not unique, but user wants shortest match.
		    (insert (if (file-directory-p file) dirsuffix filesuffix))
                    (or mini-flag (message "Completed shortest")))
                   ((or term-completion-autolist
                        (string-equal pathnondir completion))
                    ;; It's not unique, list possible completions.
                    (term-dynamic-list-filename-completions))
                   (t
                    (or mini-flag (message "Partially completed")))))))
    success))


(defun term-replace-by-expanded-filename ()
  "Dynamically expand and complete the filename at point.
Replace the filename with an expanded, canonicalized and completed replacement.
\"Expanded\" means environment variables (e.g., $HOME) and `~'s are replaced
with the corresponding directories.  \"Canonicalized\" means `..'  and `.' are
removed, and the filename is made absolute instead of relative.  For expansion
see `expand-file-name' and `substitute-in-file-name'.  For completion see
`term-dynamic-complete-filename'."
  (interactive)
  (replace-match (expand-file-name (term-match-partial-filename)) t t)
  (term-dynamic-complete-filename))


(defun term-dynamic-list-filename-completions ()
  "List in help buffer possible completions of the filename at point."
  (interactive)
  (let* ((completion-ignore-case nil)
	 (filename (or (term-match-partial-filename) ""))
	 (pathdir (file-name-directory filename))
	 (pathnondir (file-name-nondirectory filename))
	 (directory (if pathdir (term-directory pathdir) default-directory))
	 (completions (file-name-all-completions pathnondir directory)))
    (if completions
	(term-dynamic-list-completions completions)
      (message "No completions of %s" filename))))


(defun term-dynamic-list-completions (completions)
  "List in help buffer sorted COMPLETIONS.
Typing SPC flushes the help buffer."
  (let ((conf (current-window-configuration)))
    (with-output-to-temp-buffer "*Completions*"
      (display-completion-list (sort completions 'string-lessp)))
    (message "Hit space to flush")
    (let (key first)
      (if (with-current-buffer "*Completions*"
	    (setq key (read-key-sequence nil)
		  first (aref key 0))
	    (and (consp first)
		 (eq (window-buffer (posn-window (event-start first)))
		     (get-buffer "*Completions*"))
		 (memq (key-binding key)
                       '(choose-completion))))
	  ;; If the user does choose-completion with the mouse,
	  ;; execute the command, then delete the completion window.
	  (progn
	    (choose-completion first)
	    (set-window-configuration conf))
	(if (eq first ?\s)
	    (set-window-configuration conf)
	  (setq unread-command-events
                (nconc (listify-key-sequence key)
                       unread-command-events)))))))

;; I need a make-term that doesn't surround with *s -mm
(defun term-ansi-make-term (name program &optional startfile &rest switches)
  "Make a term process NAME in a buffer, running PROGRAM.
The name of the buffer is NAME.
If there is already a running process in that buffer, it is not restarted.
Optional third arg STARTFILE is the name of a file to send the contents of to
the process.  Any more args are arguments to PROGRAM."
  (let ((buffer (get-buffer-create name )))
    ;; If no process, or nuked process, crank up a new one and put buffer in
    ;; term mode.  Otherwise, leave buffer and existing process alone.
    (cond ((not (term-check-proc buffer))
	   (with-current-buffer buffer
	     (term-mode)) ; Install local vars, mode, keymap, ...
	   (term-exec buffer name program startfile switches)))
    buffer))

(defvar term-ansi-buffer-name nil)
(defvar term-ansi-default-program nil)
(defvar term-ansi-buffer-base-name nil)

;;;###autoload
(defun ansi-term (program &optional new-buffer-name)
  "Start a terminal-emulator in a new buffer.
This is almost the same as `term' apart from always creating a new buffer,
and \\`C-x' being marked as a `term-escape-char'."
  (interactive (list (read-from-minibuffer "Run program: "
					   (or explicit-shell-file-name
					       (getenv "ESHELL")
					       shell-file-name))))

  ;; Pick the name of the new buffer.
  (setq term-ansi-buffer-name
	(if new-buffer-name
	    new-buffer-name
	  (if term-ansi-buffer-base-name
	      (if (eq term-ansi-buffer-base-name t)
		  (file-name-nondirectory program)
		term-ansi-buffer-base-name)
	    "ansi-term")))

  (setq term-ansi-buffer-name (concat "*" term-ansi-buffer-name "*"))

  ;; In order to have more than one term active at a time
  ;; I'd like to have the term names have the *term-ansi-term<?>* form,
  ;; for now they have the *term-ansi-term*<?> form but we'll see...

  (setq term-ansi-buffer-name (generate-new-buffer-name term-ansi-buffer-name))
  (let ((prog (split-string-shell-command program)))
    (setq term-ansi-buffer-name
          (apply #'term-ansi-make-term term-ansi-buffer-name (car prog)
                 nil (cdr prog))))

  (set-buffer term-ansi-buffer-name)
  (term-mode)
  (term-char-mode)

  ;; Historical baggage.  A call to term-set-escape-char used to not
  ;; undo any previous call to t-s-e-c.  Because of this, ansi-term
  ;; ended up with both C-x and C-c as escape chars.  Who knows what
  ;; the original intention was, but people could have become used to
  ;; either.   (Bug#12842)
  (let (term-escape-char)
    ;; I wanna have find-file on C-x C-f -mm
    ;; your mileage may definitely vary, maybe it's better to put this in your
    ;; .emacs ...
    (term-set-escape-char ?\C-x))

  (switch-to-buffer term-ansi-buffer-name))


;;; Serial terminals
;; ===========================================================================
(defun serial-port-is-file-p ()
  "Guess whether serial ports are files on this system.
Return t if this is a Unix-based system, where serial ports are
files, such as /dev/ttyS0.
Return nil if this is Windows or DOS, where serial ports have
special identifiers such as COM1."
  (not (memq system-type '(windows-nt cygwin ms-dos))))

(defvar serial-name-history
  (if (serial-port-is-file-p)
      (or (when (file-exists-p "/dev/ttys0") (list "/dev/ttys0"))
          (when (file-exists-p "/dev/ttyS0") (list "/dev/ttyS0")))
    (list "COM1"))
  "History of serial ports used by `serial-read-name'.")

(defvar serial-speed-history
  ;; Initialized with reasonable values for newbies.
  (list "9600" ;; Given twice because 9600 b/s is the most common speed
        "1200" "2400" "4800" "9600" "14400" "19200"
        "28800" "38400" "57600" "115200")
  "History of serial port speeds used by `serial-read-speed'.")

(defun serial-nice-speed-history ()
  "Return `serial-speed-history' cleaned up for a mouse-menu."
  (let ((x) (y))
    (setq x
         (sort
          (copy-sequence serial-speed-history)
          (lambda (a b) (when (and (stringp a) (stringp b))
                     (> (string-to-number a) (string-to-number b))))))
    (dolist (i x) (when (not (equal i (car y))) (push i y)))
    y))

(defconst serial-no-speed "nil"
  "String for `serial-read-speed' for special serial ports.
If `serial-read-speed' reads this string from the user, it
returns nil, which is recognized by `serial-process-configure'
for special serial ports that cannot be configured.")

(defun serial-supported-or-barf ()
  "Signal an error if serial processes are not supported."
  (unless (fboundp 'make-serial-process)
    (error "Serial processes are not supported on this system")))

(defun serial-read-name ()
  "Read a serial port name from the user.
Try to be nice by providing useful defaults and history.
On Windows, prepend \\.\ to the port name unless it already
contains a backslash.  This handles the legacy ports COM1-COM9 as
well as the newer ports COM10 and higher."
  (serial-supported-or-barf)
  (let* ((file-name-history serial-name-history)
         (h (car file-name-history))
         (x (if (serial-port-is-file-p)
                (read-file-name
                 ;; `prompt': The most recently used port is provided as
                 ;; the default value, which is used when the user
                 ;; simply presses return.
                 (format-prompt "Serial port" h)
                 ;; `directory': Most systems have their serial ports
                 ;; in the same directory, so start in the directory
                 ;; of the most recently used port, or in a reasonable
                 ;; default directory.
                 (or (and h (file-name-directory h))
                     (and (file-exists-p "/dev/") "/dev/")
                     (and (file-exists-p "/") "/"))
                 ;; `default': This causes (read-file-name) to return
                 ;; the empty string if he user simply presses return.
                 ;; Using nil here may result in a default directory
                 ;; of the current buffer, which is not useful for
                 ;; serial port.
                 "")
              (read-from-minibuffer
               (format-prompt "Serial port" h)
               nil nil nil '(file-name-history . 1) nil nil))))
    (if (or (null x) (and (stringp x) (zerop (length x))))
        (setq x h)
      (setq serial-name-history file-name-history))
    (when (or (null x) (and (stringp x) (zerop (length x))))
      (error "No serial port selected"))
    (when (not (or (serial-port-is-file-p)
                   (string-search "\\" x)))
      (setq x (concat "\\\\.\\" x)))
    x))

(defun serial-read-speed ()
  "Read a serial port speed (in bits per second) from the user.
Try to be nice by providing useful defaults and history."
  (serial-supported-or-barf)
  (let* ((history serial-speed-history)
         (h (car history))
         (x (read-from-minibuffer
             (cond ((string= h serial-no-speed)
                    "Speed (default nil = set by port): ")
                   (h
                    (format-prompt "Speed" (format "%s b/s" h)))
                   (t "Speed (b/s): "))
             nil nil nil '(history . 1) nil nil)))
    (when (or (null x) (and (stringp x) (zerop (length x))))
      (setq x h))
    (when (or (null x) (not (stringp x)) (zerop (length x)))
      (error "Invalid speed"))
    (if (string= x serial-no-speed)
        (setq x nil)
      (setq x (string-to-number x))
      (when (or (null x) (not (integerp x)) (<= x 0))
        (error "Invalid speed")))
    (setq serial-speed-history history)
    x))

;;;###autoload
(defun serial-term (port speed &optional line-mode)
  "Start a terminal-emulator for a serial port in a new buffer.
PORT is the path or name of the serial port.  For example, this
could be \"/dev/ttyS0\" on Unix.  On Windows, this could be
\"COM1\" or \"\\\\.\\COM10\".

SPEED is the speed of the serial port in bits per second.  9600
is a common value.  SPEED can be nil, see
`serial-process-configure' for details.

Usually `term-char-mode' is used, but if LINE-MODE (the prefix
when used interactively) is non-nil, `term-line-mode' is used
instead.

The buffer is in Term mode; see `term-mode' for the commands to
use in that buffer.

\\<term-raw-map>Type \\[switch-to-buffer] to switch to another buffer."
  (interactive (list (serial-read-name) (serial-read-speed)
                     current-prefix-arg))
  (serial-supported-or-barf)
  (let* ((process (make-serial-process
                   :port port
                   :speed speed
                   :coding 'no-conversion
                   :noquery t))
         (buffer (process-buffer process)))
    (with-current-buffer buffer
      (term-mode)
      (unless line-mode
        (term-char-mode))
      (goto-char (point-max))
      (set-marker (process-mark process) (point))
      (set-process-filter process #'term-emulate-terminal)
      (set-process-sentinel process #'term-sentinel))
    (switch-to-buffer buffer)
    buffer))

(defvar serial-mode-line-speed-menu nil)
(defvar serial-mode-line-config-menu nil)

(defun serial-speed ()
  "Return the speed of the serial port of the current buffer's process.
The return value may be nil for a special serial port."
  (process-contact (get-buffer-process (current-buffer)) :speed))

(defun serial-mode-line-speed-menu-1 (event)
  (interactive "e")
  (save-selected-window
    (select-window (posn-window (event-start event)))
    (serial-update-speed-menu)
    (let* ((selection (serial-mode-line-speed-menu event))
	   (binding (and selection (lookup-key serial-mode-line-speed-menu
					       (vector (car selection))))))
      (when binding (call-interactively binding)))))

(defun serial-mode-line-speed-menu (event)
  (x-popup-menu event serial-mode-line-speed-menu))

(defun serial-update-speed-menu ()
  (setq serial-mode-line-speed-menu (make-sparse-keymap "Speed (b/s)"))
  (define-key serial-mode-line-speed-menu [serial-mode-line-speed-menu-other]
    '(menu-item "Other..."
                (lambda (event) (interactive "e")
                  (let ((speed (serial-read-speed)))
                    (serial-process-configure :speed speed)
                    (term-update-mode-line)
                    (message "Speed set to %d b/s" speed)))))
  (dolist (str (serial-nice-speed-history))
    (let ((num (or (and (stringp str) (string-to-number str)) 0)))
      (define-key
        serial-mode-line-speed-menu
        (vector (make-symbol (format "serial-mode-line-speed-menu-%s" str)))
        `(menu-item
          ,str
          (lambda (event) (interactive "e")
            (serial-process-configure :speed ,num)
            (term-update-mode-line)
            (message "Speed set to %d b/s" ,num))
          :button (:toggle . (= (serial-speed) ,num)))))))

(defun serial-mode-line-config-menu-1 (event)
  (interactive "e")
  (save-selected-window
    (select-window (posn-window (event-start event)))
    (serial-update-config-menu)
    (let* ((selection (serial-mode-line-config-menu event))
           (binding (and selection (lookup-key serial-mode-line-config-menu
                                               (vector (car selection))))))
      (when binding (call-interactively binding)))))

(defun serial-mode-line-config-menu (event)
  (x-popup-menu event serial-mode-line-config-menu))

(defun serial-update-config-menu ()
  (setq serial-mode-line-config-menu (make-sparse-keymap "Configuration"))
  (let ((config (process-contact
                 (get-buffer-process (current-buffer)) t)))
    (dolist (y '((:flowcontrol hw   "Hardware flowcontrol (RTS/CTS)")
                 (:flowcontrol sw   "Software flowcontrol (XON/XOFF)")
                 (:flowcontrol nil  "No flowcontrol")
                 (:stopbits    2    "2 stopbits")
                 (:stopbits    1    "1 stopbit")
                 (:parity      odd  "Odd parity")
                 (:parity      even "Even parity")
                 (:parity      nil  "No parity")
                 (:bytesize    7    "7 bits per byte")
                 (:bytesize    8    "8 bits per byte")))
      (define-key serial-mode-line-config-menu
        (vector (make-symbol (format "%s-%s" (nth 0 y) (nth 1 y))))
        `(menu-item
          ,(nth 2 y)
          (lambda (event) (interactive "e")
            (serial-process-configure ,(nth 0 y) ',(nth 1 y))
            (term-update-mode-line)
            (message "%s" ,(nth 2 y)))
          ;; Use :toggle instead of :radio because a non-standard port
          ;; configuration may not match any menu items.
          :button (:toggle . ,(equal (plist-get config (nth 0 y))
                                     (nth 1 y))))))))


(provide 'term)

;;; term.el ends here
