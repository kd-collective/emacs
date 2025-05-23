;;; scheme.el --- Scheme (and DSSSL) editing mode    -*- lexical-binding: t; -*-

;; Copyright (C) 1986-2025 Free Software Foundation, Inc.

;; Author: Bill Rozas <jinx@martigny.ai.mit.edu>
;; Adapted-by: Dave Love <d.love@dl.ac.uk>
;; Keywords: languages, lisp

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

;; The major mode for editing Scheme-type Lisp code, very similar to
;; the Lisp mode documented in the Emacs manual.  `dsssl-mode' is a
;; variant of scheme-mode for editing DSSSL specifications for SGML
;; documents.  [As of Apr 1997, some pointers for DSSSL may be found,
;; for instance, at <URL:https://www.sil.org/sgml/related.html#dsssl>.]
;; All these Lisp-ish modes vary basically in details of the language
;; syntax they highlight/indent/index, but dsssl-mode uses "^;;;" as
;; the page-delimiter since ^L isn't normally a valid SGML character.
;;
;; For interacting with a Scheme interpreter See also `run-scheme' in
;; the `cmuscheme' package and also the implementation-specific
;; `xscheme' package.

;; Here's a recipe to generate a TAGS file for DSSSL, by the way:
;; etags --lang=scheme --regex='/[ \t]*(\(mode\|element\)[ \t
;; ]+\([^ \t(
;; ]+\)/\2/' --regex='/[ \t]*(element[ \t
;; ]*([^)]+[ \t
;; ]+\([^)]+\)[ \t
;; ]*)/\1/' --regex='/(declare[^ \t
;; ]*[ \t
;; ]+\([^ \t
;; ]+\)/\1/' "$@"

;;; Code:

(require 'lisp-mode)
(eval-when-compile 'subr-x)             ;For `named-let'.

(defvar scheme-mode-syntax-table
  (let ((st (make-syntax-table))
        (i 0))
    ;; Symbol constituents
    ;; We used to treat chars 128-256 as symbol-constituent, but they
    ;; should be valid word constituents (Bug#8843).  Note that valid
    ;; identifier characters are Scheme-implementation dependent.
    (while (< i ?0)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?9))
    (while (< i ?A)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?Z))
    (while (< i ?a)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?z))
    (while (< i 128)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))

    ;; Whitespace
    (modify-syntax-entry ?\t "    " st)
    (modify-syntax-entry ?\n ">   " st)
    (modify-syntax-entry ?\f "    " st)
    (modify-syntax-entry ?\r "    " st)
    (modify-syntax-entry ?\s "    " st)

    ;; These characters are delimiters but otherwise undefined.
    ;; Brackets and braces balance for editing convenience.
    (modify-syntax-entry ?\[ "(]  " st)
    (modify-syntax-entry ?\] ")[  " st)
    (modify-syntax-entry ?{ "(}  " st)
    (modify-syntax-entry ?} "){  " st)
    (modify-syntax-entry ?\| "\" 23bn" st)
    ;; Guile allows #! ... !# comments.
    ;; But SRFI-22 defines the comment as #!...\n instead.
    ;; Also Guile says that the !# should be on a line of its own.
    ;; It's too difficult to get it right, for too little benefit.
    ;; (modify-syntax-entry ?! "_ 2" st)

    ;; Other atom delimiters
    (modify-syntax-entry ?\( "()  " st)
    (modify-syntax-entry ?\) ")(  " st)
    ;; It's used for single-line comments as well as for #;(...) sexp-comments.
    (modify-syntax-entry ?\; "<"    st)
    (modify-syntax-entry ?\" "\"   " st)
    (modify-syntax-entry ?' "'   " st)
    (modify-syntax-entry ?` "'   " st)

    ;; Special characters
    (modify-syntax-entry ?, "'   " st)
    (modify-syntax-entry ?@ "'   " st)
    (modify-syntax-entry ?# "' 14" st)
    (modify-syntax-entry ?\\ "\\   " st)
    st))

(defvar scheme-mode-abbrev-table nil)
(define-abbrev-table 'scheme-mode-abbrev-table ())

(defvar scheme-imenu-generic-expression
  `((nil
     ,(rx bol (zero-or-more space)
          "(define"
          (zero-or-one "*")
          (zero-or-one "-public")
          (one-or-more space)
          (zero-or-one "(")
          (group (one-or-more (or word (syntax symbol)))))
     1)
    ("Methods"
     ,(rx bol (zero-or-more space)
          "(define-"
          (or "generic" "method" "accessor")
          (one-or-more space)
          (zero-or-one "(")
          (group (one-or-more (or word (syntax symbol)))))
     1)
    ("Classes"
     ,(rx bol (zero-or-more space)
          "(define-class"
          (one-or-more space)
          (zero-or-one "(")
          (group (one-or-more (or word (syntax symbol)))))
     1)
    ("Records"
     ,(rx bol (zero-or-more space)
          "(define-record-type"
          (zero-or-one "*")
          (one-or-more space)
          (group (one-or-more (or word (syntax symbol)))))
     1)
    ("Conditions"
     ,(rx bol (zero-or-more space)
          "(define-condition-type"
          (one-or-more space)
          (group (one-or-more (or word (syntax symbol)))))
     1)
    ("Modules"
     ,(rx bol (zero-or-more space)
          "(define-module"
          (one-or-more space)
          (group "(" (one-or-more nonl) ")"))
     1)
    ("Macros"
     ,(rx bol (zero-or-more space) "("
          (or (and "defmacro"
                   (zero-or-one "*")
                   (zero-or-one "-public"))
              "define-macro" "define-syntax" "define-syntax-rule")
          (one-or-more space)
          (zero-or-one "(")
          (group (one-or-more (or word (syntax symbol)))))
     1))
  "Imenu generic expression for Scheme mode.  See `imenu-generic-expression'.")

(defun scheme-mode-variables ()
  (set-syntax-table scheme-mode-syntax-table)
  (setq local-abbrev-table scheme-mode-abbrev-table)
  (setq-local paragraph-start (concat "$\\|" page-delimiter))
  (setq-local paragraph-separate paragraph-start)
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local fill-paragraph-function 'lisp-fill-paragraph)
  ;; Adaptive fill mode gets in the way of auto-fill,
  ;; and should make no difference for explicit fill
  ;; because lisp-fill-paragraph should do the job.
  (setq-local adaptive-fill-mode nil)
  (setq-local indent-line-function 'lisp-indent-line)
  (setq-local parse-sexp-ignore-comments t)
  (setq-local outline-regexp ";;; \\|(....")
  (setq-local add-log-current-defun-function #'lisp-current-defun-name)
  (setq-local comment-start ";")
  (setq-local comment-add 1)
  (setq-local comment-start-skip ";+[ \t]*")
  (setq-local comment-use-syntax t)
  (setq-local comment-column 40)
  (setq-local lisp-indent-function 'scheme-indent-function)
  (setq mode-line-process '("" scheme-mode-line-process))
  (setq-local imenu-case-fold-search t)
  (setq-local imenu-generic-expression scheme-imenu-generic-expression)
  (setq-local imenu-syntax-alist '(("+-*/.<>=?!$%_&~^:" . "w")))
  (setq-local syntax-propertize-function #'scheme-syntax-propertize)
  (setq font-lock-defaults
        '((scheme-font-lock-keywords
           scheme-font-lock-keywords-1 scheme-font-lock-keywords-2)
          nil t (("+-*/.<>=!?$%_&~^:" . "w") (?#. "w 14"))
          beginning-of-defun
          (font-lock-mark-block-function . mark-defun)))
  (setq-local prettify-symbols-alist lisp-prettify-symbols-alist)
  (setq-local lisp-doc-string-elt-property 'scheme-doc-string-elt))

(defvar scheme-mode-line-process "")

(defvar-keymap scheme-mode-map
  :doc "Keymap for Scheme mode.
All commands in `lisp-mode-shared-map' are inherited by this map."
  :parent lisp-mode-shared-map)

(easy-menu-define scheme-mode-menu scheme-mode-map
  "Menu for Scheme mode."
  '("Scheme"
    ["Indent Line" lisp-indent-line]
    ["Indent Region" indent-region
     :enable mark-active]
    ["Comment Out Region" comment-region
     :enable mark-active]
    ["Uncomment Out Region" (lambda (beg end)
                                (interactive "r")
                                (comment-region beg end '(4)))
     :enable mark-active]
    ["Run Inferior Scheme" run-scheme]))

;; Used by cmuscheme
(defun scheme-mode-commands (map)
  ;;(define-key map "\t" 'indent-for-tab-command) ; default
  (define-key map "\177" 'backward-delete-char-untabify)
  (define-key map "\e\C-q" 'indent-sexp))

;;;###autoload
(define-derived-mode scheme-mode prog-mode "Scheme"
  "Major mode for editing Scheme code.
Editing commands are similar to those of `lisp-mode'.

In addition, if an inferior Scheme process is running, some additional
commands will be defined, for evaluating expressions and controlling
the interpreter, and the state of the process will be displayed in the
mode line of all Scheme buffers.  The names of commands that interact
with the Scheme process start with \"xscheme-\" if you use the MIT
Scheme-specific `xscheme' package; for more information see the
documentation for `xscheme-interaction-mode'.  Use \\[run-scheme] to
start an inferior Scheme using the more general `cmuscheme' package.

Commands:
Delete converts tabs to spaces as it moves back.
Blank lines separate paragraphs.  Semicolons start comments.
\\{scheme-mode-map}"
  (scheme-mode-variables))

(defgroup scheme nil
  "Editing Scheme code."
  :link '(custom-group-link :tag "Font Lock Faces group" font-lock-faces)
  :group 'lisp)

(defcustom scheme-mit-dialect t
  "If non-nil, scheme mode is specialized for MIT Scheme.
Set this to nil if you normally use another dialect."
  :type 'boolean)

(defcustom dsssl-sgml-declaration
  "<!DOCTYPE style-sheet PUBLIC \"-//James Clark//DTD DSSSL Style Sheet//EN\">
"
  "An SGML declaration for the DSSSL file.
If it is defined as a string this will be inserted into an empty buffer
which is in `dsssl-mode'.  It is typically James Clark's style-sheet
doctype, as required for Jade."
  :type '(choice (string :tag "Specified string")
                 (const :tag "None" :value nil)))

(defcustom scheme-mode-hook nil
  "Normal hook run when entering `scheme-mode'.
See `run-hooks'."
  :type 'hook)

(defcustom dsssl-mode-hook nil
  "Normal hook run when entering `dsssl-mode'.
See `run-hooks'."
  :type 'hook)

;; This is shared by cmuscheme and xscheme.
(defcustom scheme-program-name "scheme"
  "Program invoked by the `run-scheme' command."
  :type 'string)

(defvar dsssl-imenu-generic-expression
  ;; Perhaps this should also look for the style-sheet DTD tags.  I'm
  ;; not sure it's the best way to organize it; perhaps one type
  ;; should be at the first level, though you don't see this anyhow if
  ;; it gets split up.
  '(("Defines"
     "^(define\\s-+(?\\(\\sw+\\)" 1)
    ("Modes"
     "^\\s-*(mode\\s-+\\(\\(\\sw\\|\\s-\\)+\\)" 1)
    ("Elements"
     ;; (element foo ...) or (element (foo bar ...) ...)
     ;; Fixme: Perhaps it should do `root'.
     "^\\s-*(element\\s-+(?\\(\\(\\sw\\|\\s-\\)+\\))?" 1)
    ("Declarations"
     "^(declare\\(-\\sw+\\)+\\>\\s-+\\(\\sw+\\)" 2))
  "Imenu generic expression for DSSSL mode.  See `imenu-generic-expression'.")

(defconst scheme-font-lock-keywords-1
  (eval-when-compile
    (list
     ;;
     ;; Declarations.  Hannes Haug <hannes.haug@student.uni-tuebingen.de> says
     ;; this works for SOS, STklos, SCOOPS, Meroon and Tiny CLOS.
     (list (concat "(\\(define\\*?\\("
                   ;; Function names.
                   "\\(\\|-public\\|-method\\|-generic\\(-procedure\\)?\\)\\|"
                   ;; Macro names, as variable names.  A bit dubious, this.
                   "\\(-syntax\\|-macro\\)\\|"
                   ;; Class names.
                   "-class"
                   ;; Guile modules.
                   "\\|-module"
                   "\\)\\)\\>"
                   ;; Any whitespace and declared object.
                   ;; The "(*" is for curried definitions, e.g.,
                   ;;  (define ((sum a) b) (+ a b))
                   "[ \t]*(*"
                   "\\(\\sw+\\)?")
           '(1 font-lock-keyword-face)
           '(6 (cond ((match-beginning 3) font-lock-function-name-face)
                     ((match-beginning 5) font-lock-variable-name-face)
                     (t font-lock-type-face))
               nil t))
     ))
  "Subdued expressions to highlight in Scheme modes.")

(defconst scheme-font-lock-keywords-2
  (append scheme-font-lock-keywords-1
   (eval-when-compile
     (list
      ;;
      ;; Control structures.
      (cons
       (concat
        "(" (regexp-opt
             '("begin" "call-with-current-continuation" "call/cc"
               "call-with-input-file" "call-with-output-file"
               "call-with-port"
               "case" "cond"
               "do" "else" "for-each" "if" "lambda" "λ"
               "let" "let*" "let-syntax" "letrec" "letrec-syntax"
               ;; R6RS library subforms.
               "export" "import"
               ;; SRFI 11 usage comes up often enough.
               "let-values" "let*-values"
               ;; Hannes Haug <hannes.haug@student.uni-tuebingen.de> wants:
               "and" "or" "delay" "force"
               ;; Stefan Monnier <stefan.monnier@epfl.ch> says don't bother:
               ;;"quasiquote" "quote" "unquote" "unquote-splicing"
	       "map" "syntax" "syntax-rules"
	       ;; For R7RS
	       "when" "unless" "letrec*" "include" "include-ci" "cond-expand"
	       "delay-force" "parameterize" "guard" "case-lambda"
	       "syntax-error" "only" "except" "prefix" "rename" "define-values"
	       "define-record-type" "define-library"
	       "include-library-declarations"
	       ;; SRFI-8
	       "receive"
	       ) t)
        "\\>") 1)
      ;;
      ;; It wouldn't be Scheme without named-let.
      '("(let\\s-+\\(\\sw+\\)"
        (1 font-lock-function-name-face))
      ;;
      ;; David Fox <fox@graphics.cs.nyu.edu> for SOS/STklos class specifiers.
      '("\\<<\\sw+>\\>" . font-lock-type-face)
      ;;
      ;; Scheme `:' and `#:' keywords as builtins.
      '("\\<#?:\\sw+\\>" . font-lock-builtin-face)
      ;; R6RS library declarations.
      '("(\\(\\<library\\>\\)\\s-*(?\\(\\sw+\\)?"
        (1 font-lock-keyword-face)
        (2 font-lock-type-face))
      )))
  "Gaudy expressions to highlight in Scheme modes.")

(defvar scheme-font-lock-keywords scheme-font-lock-keywords-1
  "Default expressions to highlight in Scheme modes.")

;; (defconst scheme-sexp-comment-syntax-table
;;   (let ((st (make-syntax-table scheme-mode-syntax-table)))
;;     (modify-syntax-entry ?\; "." st)
;;     (modify-syntax-entry ?\n " " st)
;;     (modify-syntax-entry ?#  "'" st)
;;     st))

(put 'lambda 'scheme-doc-string-elt 2)
(put 'lambda* 'scheme-doc-string-elt 2)
;; Docstring's pos in a `define' depends on whether it's a var or fun def.
(put 'define 'scheme-doc-string-elt
     (lambda ()
       ;; The function is called with point right after "define".
       (forward-comment (point-max))
       (if (eq (char-after) ?\() 2 0)))
(put 'define* 'scheme-doc-string-elt 2)
(put 'case-lambda 'scheme-doc-string-elt 1)
(put 'case-lambda* 'scheme-doc-string-elt 1)
(put 'define-syntax-rule 'scheme-doc-string-elt 2)
(put 'syntax-rules 'scheme-doc-string-elt 2)

(defun scheme-syntax-propertize (beg end)
  (goto-char beg)
  (scheme-syntax-propertize-sexp-comment end)
  (scheme-syntax-propertize-regexp end)
  (funcall
   (syntax-propertize-rules
    ("\\(#\\);" (1 (prog1 "< cn"
                     (scheme-syntax-propertize-sexp-comment end))))
    ("\\(#\\)/" (1 (when (null (nth 8 (save-excursion
                                        (syntax-ppss (match-beginning 0)))))
                     (put-text-property
                      (match-beginning 1)
                      (match-end 1)
                      'syntax-table (string-to-syntax "|"))
                     (scheme-syntax-propertize-regexp end)
                     nil))))
   (point) end))

(defun scheme-syntax-propertize-sexp-comment (end)
  (let ((state (syntax-ppss))
        ;; (beg (point))
        (checked (point)))
    (when (eq 2 (nth 7 state))
      ;; It's a sexp-comment.  Tell parse-partial-sexp where it ends.
      (named-let loop ((startpos (+ 2 (nth 8 state))))
        (let ((found nil))
          (while
              (progn
                (setq found nil)
                (condition-case nil
                    (save-restriction
                      (narrow-to-region (point-min) end)
                      (goto-char startpos)
                      (forward-sexp 1)
                      ;; (cl-assert (> (point) beg))
                      (setq found (point)))
                  (scan-error (goto-char end)))
                ;; If there's a nested `#;', the syntax-tables will normally
                ;; consider the `;' to start a normal comment, so the
                ;; (forward-sexp 1) above may have landed at the wrong place.
                ;; So look for `#;' in the text over which we jumped, and
                ;; mark those we found as nested sexp-comments.
                (let ((limit (min end (or found end))))
                  (when (< checked limit)
                    (goto-char checked)
                    (while (and (re-search-forward "\\(#\\);" limit 'move)
                                ;; Skip those #; inside comments and strings.
                                (nth 8 (save-excursion
                                         (parse-partial-sexp
                                          startpos (match-beginning 0))))))
                    (setq checked (point))
                    (when (< (point) limit)
                      (put-text-property (match-beginning 1) (match-end 1)
                                         'syntax-table
                                         (string-to-syntax "< cn"))
                      (loop (point))
                      ;; Try the `forward-sexp' with the new text state.
                      t)))))
          (when found
            (goto-char found)
            (put-text-property (1- found) found
                               'syntax-table (string-to-syntax "> cn"))))))))

(defun scheme-syntax-propertize-regexp (end)
  (let* ((state (syntax-ppss))
         (within-str (nth 3 state))
         (start-delim-pos (nth 8 state)))
    (when (and within-str
               (char-equal ?# (char-after start-delim-pos)))
      (while (and (re-search-forward "/" end 'move)
                  (eq -1
                      (% (save-excursion
                           (backward-char)
                           (skip-chars-backward "\\\\"))
                         2))))
      (when (< (point) end)
       (put-text-property (match-beginning 0) (match-end 0)
                          'syntax-table (string-to-syntax "|"))))))

;;;###autoload
(define-derived-mode dsssl-mode scheme-mode "DSSSL"
  "Major mode for editing DSSSL code.
Editing commands are similar to those of `lisp-mode'.

Commands:
Delete converts tabs to spaces as it moves back.
Blank lines separate paragraphs.  Semicolons start comments.
\\{scheme-mode-map}
Entering this mode runs the hooks `scheme-mode-hook' and then
`dsssl-mode-hook' and inserts the value of `dsssl-sgml-declaration' if
that variable's value is a string."
  (setq-local page-delimiter "^;;;") ; ^L not valid SGML char
  ;; Insert a suitable SGML declaration into an empty buffer.
  ;; FIXME: This should use `auto-insert-alist' instead.
  (and (zerop (buffer-size))
       (stringp dsssl-sgml-declaration)
       (not buffer-read-only)
       (insert dsssl-sgml-declaration))
  (setq font-lock-defaults '(dsssl-font-lock-keywords
                             nil t (("+-*/.<>=?$%_&~^:" . "w"))
                             beginning-of-defun
                             (font-lock-mark-block-function . mark-defun)))
  (setq-local add-log-current-defun-function #'lisp-current-defun-name)
  (setq-local imenu-case-fold-search nil)
  (setq imenu-generic-expression dsssl-imenu-generic-expression)
  (setq-local imenu-syntax-alist '(("+-*/.<>=?$%_&~^:" . "w"))))

;; Extra syntax for DSSSL.  This isn't separated from Scheme, but
;; shouldn't cause much trouble in scheme-mode.
(put 'element 'scheme-indent-function 1)
(put 'mode 'scheme-indent-function 1)
(put 'with-mode 'scheme-indent-function 1)
(put 'make 'scheme-indent-function 1)
(put 'style 'scheme-indent-function 1)
(put 'root 'scheme-indent-function 1)
(put 'λ 'scheme-indent-function 1)

(defvar dsssl-font-lock-keywords
  (eval-when-compile
    (list
     ;; Similar to Scheme
     (list "(\\(define\\(-\\w+\\)?\\)\\>[ \t]*\\((?\\)\\(\\sw+\\)\\>"
           '(1 font-lock-keyword-face)
           '(4 font-lock-function-name-face))
     (cons
      (concat "(" (regexp-opt
                   '("case" "cond" "else" "if" "lambda"
                     "let" "let*" "letrec" "and" "or" "map" "with-mode")
                   'words))
      1)
     ;; DSSSL syntax
     '("(\\(element\\|mode\\|declare-\\w+\\)\\>[ \t]*\\(\\sw+\\)"
       (1 font-lock-keyword-face)
       (2 font-lock-type-face))
     '("(\\(element\\)\\>[ \t]*(\\(\\S)+\\))"
       (1 font-lock-keyword-face)
       (2 font-lock-type-face))
     '("\\<\\sw+:\\>" . font-lock-constant-face) ; trailing `:' cf. scheme
     ;; SGML markup (from sgml-mode) :
     '("<\\([!?][-a-z0-9]+\\)" 1 font-lock-keyword-face)
     '("<\\(/?[-a-z0-9]+\\)" 1 font-lock-function-name-face)))
  "Default expressions to highlight in DSSSL mode.")


(defvar calculate-lisp-indent-last-sexp)


;; FIXME this duplicates almost all of lisp-indent-function.
;; Extract common code to a subroutine.
(defun scheme-indent-function (indent-point state)
  "Scheme mode function for the value of the variable `lisp-indent-function'.
This behaves like the function `lisp-indent-function', except that:

i) it checks for a non-nil value of the property `scheme-indent-function'
\(or the deprecated `scheme-indent-hook'), rather than `lisp-indent-function'.

ii) if that property specifies a function, it is called with three
arguments (not two), the third argument being the default (i.e., current)
indentation."
  (let ((normal-indent (current-column)))
    (goto-char (1+ (elt state 1)))
    (parse-partial-sexp (point) calculate-lisp-indent-last-sexp 0 t)
    (if (and (elt state 2)
             (not (looking-at "\\sw\\|\\s_")))
        ;; car of form doesn't seem to be a symbol
        (progn
          (if (not (> (save-excursion (forward-line 1) (point))
                      calculate-lisp-indent-last-sexp))
              (progn (goto-char calculate-lisp-indent-last-sexp)
                     (beginning-of-line)
                     (parse-partial-sexp (point)
                                         calculate-lisp-indent-last-sexp 0 t)))
          ;; Indent under the list or under the first sexp on the same
          ;; line as calculate-lisp-indent-last-sexp.  Note that first
          ;; thing on that line has to be complete sexp since we are
          ;; inside the innermost containing sexp.
          (backward-prefix-chars)
          (current-column))
      (let ((function (buffer-substring (point)
                                        (progn (forward-sexp 1) (point))))
            method)
        (setq method (or (get (intern-soft function) 'scheme-indent-function)
                         (get (intern-soft function) 'scheme-indent-hook)))
        (cond ((or (eq method 'defun)
                   (and (null method)
                        (> (length function) 3)
                        (string-match "\\`def" function)))
               (lisp-indent-defform state indent-point))
              ((integerp method)
               (lisp-indent-specform method state
                                     indent-point normal-indent))
              (method
                (funcall method state indent-point normal-indent)))))))


;;; Let is different in Scheme

;; (defun scheme-would-be-symbol (string)
;;   (not (string-equal (substring string 0 1) "(")))

;; (defun scheme-next-sexp-as-string ()
;;   ;; Assumes that it is protected by a save-excursion
;;   (forward-sexp 1)
;;   (let ((the-end (point)))
;;     (backward-sexp 1)
;;     (buffer-substring (point) the-end)))

;; This is correct but too slow.
;; The one below works almost always.
;;(defun scheme-let-indent (state indent-point)
;;  (if (scheme-would-be-symbol (scheme-next-sexp-as-string))
;;      (scheme-indent-specform 2 state indent-point)
;;      (scheme-indent-specform 1 state indent-point)))

(defun scheme-let-indent (state indent-point normal-indent)
  (skip-chars-forward " \t")
  (if (looking-at "[-a-zA-Z0-9+*/?!@$%^&_:~]")
      (lisp-indent-specform 2 state indent-point normal-indent)
    (lisp-indent-specform 1 state indent-point normal-indent)))

;; See `scheme-indent-function' (the function) for what these do.
;; In a nutshell:
;;  . for forms with no `scheme-indent-function' property the 2nd
;;    and subsequent lines will be indented with one space;
;;  . if the value of the property is zero, then when the first form
;;    is on a separate line, the next lines will be indented with 2
;;    spaces instead of the default one space;
;;  . if the value is a positive integer N, the first N lines after
;;    the first one will be indented with 4 spaces, and the rest
;;    will be indented with 2 spaces;
;;  . if the value is `defun', the indentation is like for `defun';
;;  . if the value is a function, it will be called to produce the
;;    required indentation.
;; See also http://community.schemewiki.org/?emacs-indentation.
(put 'begin 'scheme-indent-function 0)
(put 'case 'scheme-indent-function 1)
(put 'delay 'scheme-indent-function 0)
(put 'do 'scheme-indent-function 2)
(put 'lambda 'scheme-indent-function 1)
(put 'let 'scheme-indent-function 'scheme-let-indent)
(put 'let* 'scheme-indent-function 1)
(put 'letrec 'scheme-indent-function 1)
(put 'let-values 'scheme-indent-function 1) ; SRFI 11
(put 'let*-values 'scheme-indent-function 1) ; SRFI 11
(put 'and-let* 'scheme-indent-function 1) ; SRFI 2
(put 'sequence 'scheme-indent-function 0) ; SICP, not r4rs
(put 'let-syntax 'scheme-indent-function 1)
(put 'letrec-syntax 'scheme-indent-function 1)
(put 'syntax-rules 'scheme-indent-function 'defun)
(put 'syntax-case 'scheme-indent-function 2) ; not r5rs
(put 'with-syntax 'scheme-indent-function 1)
(put 'library 'scheme-indent-function 1) ; R6RS
;; Part of at least Guile, Chez Scheme, Chicken
(put 'eval-when 'scheme-indent-function 1)

(put 'call-with-input-file 'scheme-indent-function 1)
(put 'call-with-port 'scheme-indent-function 1)
(put 'with-input-from-file 'scheme-indent-function 1)
(put 'with-input-from-port 'scheme-indent-function 1)
(put 'call-with-output-file 'scheme-indent-function 1)
(put 'with-output-to-file 'scheme-indent-function 1)
(put 'with-output-to-port 'scheme-indent-function 1)
(put 'call-with-values 'scheme-indent-function 1) ; r5rs?
(put 'dynamic-wind 'scheme-indent-function 3) ; r5rs?

;; R7RS
(put 'when 'scheme-indent-function 1)
(put 'unless 'scheme-indent-function 1)
(put 'letrec* 'scheme-indent-function 1)
(put 'parameterize 'scheme-indent-function 1)
(put 'define-values 'scheme-indent-function 1)
(put 'define-record-type 'scheme-indent-function 1) ;; is 1 correct?
(put 'define-library 'scheme-indent-function 1)
(put 'guard 'scheme-indent-function 1)

;; SRFI-8
(put 'receive 'scheme-indent-function 2)

;; SRFI 64
(put 'test-group 'scheme-indent-function 1)
(put 'test-group-with-cleanup 'scheme-indent-function 1)

;; SRFI-204 (withdrawn, but provided in many implementations, see the SRFI text)
(put 'match 'scheme-indent-function 1)
(put 'match-lambda 'scheme-indent-function 0)
(put 'match-lambda* 'scheme-indent-function 0)
(put 'match-let 'scheme-indent-function 'scheme-let-indent)
(put 'match-let* 'scheme-indent-function 1)
(put 'match-letrec 'scheme-indent-function 1)

;; SRFI-227
(put 'opt-lambda 'scheme-indent-function 1)
(put 'opt*-lambda 'scheme-indent-function 1)
(put 'let-optionals 'scheme-indent-function 2)
(put 'let-optionals* 'scheme-indent-function 2)
;; define-optionals and define-optionals* already work

;; SRFI-253
(put 'check-case 'scheme-indent-function 1)
(put 'lambda-checked 'scheme-indent-function 1)
(put 'case-lambda-checked 'scheme-doc-string-elt 1)
;; define-checked and define-record-type-checked already work

;;;; MIT Scheme specific indentation.

(if scheme-mit-dialect
    (progn
      (put 'fluid-let 'scheme-indent-function 1)
      (put 'in-package 'scheme-indent-function 1)
      (put 'local-declare 'scheme-indent-function 1)
      (put 'macro 'scheme-indent-function 1)
      (put 'make-environment 'scheme-indent-function 0)
      (put 'named-lambda 'scheme-indent-function 1)
      (put 'using-syntax 'scheme-indent-function 1)

      (put 'with-input-from-string 'scheme-indent-function 1)
      (put 'with-output-to-string 'scheme-indent-function 0)
      (put 'with-values 'scheme-indent-function 1)

      (put 'syntax-table-define 'scheme-indent-function 2)
      (put 'list-transform-positive 'scheme-indent-function 1)
      (put 'list-transform-negative 'scheme-indent-function 1)
      (put 'list-search-positive 'scheme-indent-function 1)
      (put 'list-search-negative 'scheme-indent-function 1)

      (put 'access-components 'scheme-indent-function 1)
      (put 'assignment-components 'scheme-indent-function 1)
      (put 'combination-components 'scheme-indent-function 1)
      (put 'comment-components 'scheme-indent-function 1)
      (put 'conditional-components 'scheme-indent-function 1)
      (put 'disjunction-components 'scheme-indent-function 1)
      (put 'declaration-components 'scheme-indent-function 1)
      (put 'definition-components 'scheme-indent-function 1)
      (put 'delay-components 'scheme-indent-function 1)
      (put 'in-package-components 'scheme-indent-function 1)
      (put 'lambda-components 'scheme-indent-function 1)
      (put 'lambda-components* 'scheme-indent-function 1)
      (put 'lambda-components** 'scheme-indent-function 1)
      (put 'open-block-components 'scheme-indent-function 1)
      (put 'pathname-components 'scheme-indent-function 1)
      (put 'procedure-components 'scheme-indent-function 1)
      (put 'sequence-components 'scheme-indent-function 1)
      (put 'unassigned\?-components 'scheme-indent-function 1)
      (put 'unbound\?-components 'scheme-indent-function 1)
      (put 'variable-components 'scheme-indent-function 1)))

(provide 'scheme)

;;; scheme.el ends here
