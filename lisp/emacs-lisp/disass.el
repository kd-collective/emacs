;;; disass.el --- disassembler for compiled Emacs Lisp code  -*- lexical-binding:t -*-

;; Copyright (C) 1986, 1991, 2002-2025 Free Software Foundation, Inc.

;; Author: Doug Cutting <doug@csli.stanford.edu>
;;	Jamie Zawinski <jwz@lucid.com>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: internal

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

;; The single entry point, `disassemble', disassembles a code object generated
;; by the Emacs Lisp byte-compiler.  This doesn't invert the compilation
;; operation, not by a long shot, but it's useful for debugging.

;;
;; Original version by Doug Cutting (doug@csli.stanford.edu)
;; Substantially modified by Jamie Zawinski <jwz@lucid.com> for
;; the new lapcode-based byte compiler.

;;; Code:

(require 'macroexp)
(require 'cl-lib)

;; The variable byte-code-vector is defined by the new bytecomp.el.
;; The function byte-decompile-lapcode is defined in byte-opt.el.
;; Since we don't use byte-decompile-lapcode, let's try not loading byte-opt.
(require 'byte-compile "bytecomp")

(declare-function comp-c-func-name "comp.el")

(defvar disassemble-column-1-indent 8 "*")
(defvar disassemble-column-2-indent 10 "*")

(defvar disassemble-recursive-indent 3 "*")

;;;###autoload
(defun disassemble (object &optional buffer indent interactive-p)
  "Print disassembled code for OBJECT in (optional) BUFFER.
OBJECT can be a symbol defined as a function, or a function itself
\(a lambda expression or a byte-code-function object).
If OBJECT is not already compiled, we compile it, but do not
redefine OBJECT if it is a symbol."
  (interactive
   (let* ((fn (function-called-at-point))
          (def (and fn (symbol-name fn))))
     (list (intern (completing-read (format-prompt "Disassemble function" fn)
                                    obarray 'fboundp t nil nil def))
           nil 0 t)))
  (let ((lb lexical-binding))
    (when (and (consp object) (not (eq (car object) 'lambda)))
      (setq object
            (if (eq (car object) 'byte-code)
                (apply #'make-byte-code 0 (cdr object))
              `(lambda () ,object))))
    (or indent (setq indent 0))		;Default indent to zero
    (save-excursion
      (if (or interactive-p (null buffer))
	  (with-output-to-temp-buffer "*Disassemble*"
	    (set-buffer standard-output)
            (let ((lexical-binding lb))
	      (disassemble-internal object indent (not interactive-p))))
        (set-buffer buffer)
        (let ((lexical-binding lb))
          (disassemble-internal object indent nil)))))
  nil)

(declare-function native-comp-unit-file "data.c")
(declare-function subr-native-comp-unit "data.c")
(cl-defun disassemble-internal (obj indent interactive-p)
  (let ((macro 'nil)
	(name (when (symbolp obj)
                (prog1 obj
                  (setq obj (indirect-function obj)))))
	args)
    (setq obj (autoload-do-load obj name))
    (if (subrp obj)
        (if (and (fboundp 'native-comp-function-p)
                 (native-comp-function-p obj))
            (progn
              (require 'comp)
              (let ((eln (native-comp-unit-file (subr-native-comp-unit obj))))
                (if (file-exists-p eln)
                    (call-process "objdump" nil (current-buffer) t "-S" eln)
                  (error "Missing eln file for #<subr %s>" name)))
              (goto-char (point-min))
              (re-search-forward (concat "^.*<_?"
                                         (regexp-quote
                                          (comp-c-func-name
                                           (subr-name obj) "F" t))
                                         ">:"))
              (beginning-of-line)
              (delete-region (point-min) (point))
              (when (re-search-forward "^.*<.*>:" nil t 2)
                (delete-region (match-beginning 0) (point-max)))
              (asm-mode)
              (setq buffer-read-only t)
              (cl-return-from disassemble-internal))
	  (error "Can't disassemble #<subr %s>" name)))
    (if (eq (car-safe obj) 'macro)	;Handle macros.
	(setq macro t
	      obj (cdr obj)))
    (when (or (consp obj) (interpreted-function-p obj))
      (unless (functionp obj) (error "Not a function"))
      (if interactive-p (message (if name
                                     "Compiling %s's definition..."
                                   "Compiling definition...")
                                 name))
      (setq obj (byte-compile obj))
      (if interactive-p (message "Done compiling.  Disassembling...")))
    (cond ((consp obj)
	   (setq args (help-function-arglist obj))	;save arg list
	   (setq obj (cdr obj))		;throw lambda away
	   (setq obj (cdr obj)))
	  ((closurep obj)
	   (setq args (help-function-arglist obj)))
          (t (error "Compilation failed")))
    (if (zerop indent) ; not a nested function
	(progn
	  (indent-to indent)
	  (insert (format "byte code%s%s%s:\n"
			  (if (or macro name) " for" "")
			  (if macro " macro" "")
			  (if name (format " %s" name) "")))))
    (let ((doc (if (consp obj)
		   (and (stringp (car obj)) (car obj))
		 ;; Use documentation to get lazy-loaded doc string
		 (documentation obj t))))
      (if (and doc (stringp doc))
	  (progn (and (consp obj) (setq obj (cdr obj)))
		 (indent-to indent)
		 (princ "  doc:  " (current-buffer))
		 (if (string-match "\n" doc)
		     (setq doc (concat (substring doc 0 (match-beginning 0))
				       " ...")))
		 (insert doc "\n"))))
    (indent-to indent)
    (insert "  args: ")
    (prin1 args (current-buffer))
    (insert "\n")
    (let ((interactive (interactive-form obj)))
      (if interactive
	  (progn
	    (setq interactive (nth 1 interactive))
	    (if (eq (car-safe (car-safe obj)) 'interactive)
		(setq obj (cdr obj)))
	    (indent-to indent)
	    (insert " interactive: ")
	    (if (eq (car-safe interactive) 'byte-code)
		(progn
		  (insert "\n")
		  (disassemble-1 interactive
				 (+ indent disassemble-recursive-indent)))
	      (let ((print-escape-newlines t))
		(prin1 interactive (current-buffer))))
	    (insert "\n"))))
    (cond ((byte-code-function-p obj)
	   (disassemble-1 obj indent))
	  (t
	   (insert "Uncompiled body:  ")
	   (let ((print-escape-newlines t))
	     (prin1 (macroexp-progn (if (interpreted-function-p obj)
		                        (aref obj 1)
		                      obj))
		    (current-buffer))))))
  (if interactive-p
      (message "")))


(defun disassemble-1 (obj indent)
  "Print the byte-code call OBJ in the current buffer.
OBJ should be a call to BYTE-CODE generated by the byte compiler."
  (let (bytes constvec)
    (if (consp obj)
	(setq bytes (car (cdr obj))		;the byte code
	      constvec (car (cdr (cdr obj))))	;constant vector
      (setq bytes (aref obj 1)
	    constvec (aref obj 2)))
    (cl-assert (not (multibyte-string-p bytes)))
    (let ((lap (byte-decompile-bytecode bytes constvec))
	  op arg opname pc-value)
      (let ((tagno 0)
	    tmp
	    (lap lap))
	(while (setq tmp (assq 'TAG lap))
	  (setcar (cdr tmp) (setq tagno (1+ tagno)))
	  (setq lap (cdr (memq tmp lap)))))
      (while lap
	;; Take off the pc value of the next thing
	;; and put it in pc-value.
	(setq pc-value nil)
	(if (numberp (car lap))
	    (setq pc-value (car lap)
		  lap (cdr lap)))
	;; Fetch the next op and its arg.
	(setq op (car (car lap))
	      arg (cdr (car lap)))
	(setq lap (cdr lap))
	(indent-to indent)
	(if (eq 'TAG op)
	    (progn
	      ;; We have a label.  Display it, but first its pc value.
	      (if pc-value
		  (insert (format "%d:" pc-value)))
	      (insert (int-to-string (car arg))))
	  ;; We have an instruction.  Display its pc value first.
	  (if pc-value
	      (insert (format "%d" pc-value)))
	  (indent-to (+ indent disassemble-column-1-indent))
	  (if (and op
		   (string-match "^byte-" (setq opname (symbol-name op))))
	      (setq opname (substring opname 5))
	    (setq opname "<not-an-opcode>"))
	  (if (eq op 'byte-constant2)
	      (insert " #### shouldn't have seen constant2 here!\n  "))
	  (insert opname)
	  (indent-to (+ indent disassemble-column-1-indent
			disassemble-column-2-indent
			-1))
	  (insert " ")
	  (cond ((memq op byte-goto-ops)
		 (insert (int-to-string (nth 1 arg))))
		((memq op '(byte-call byte-unbind
			    byte-listN byte-concatN byte-insertN
			    byte-stack-ref byte-stack-set byte-stack-set2
			    byte-discardN byte-discardN-preserve-tos))
		 (insert (int-to-string arg)))
		((memq op '(byte-varref byte-varset byte-varbind))
		 (prin1 (car arg) (current-buffer)))
		((memq op '(byte-constant byte-constant2))
		 ;; it's a constant
		 (setq arg (car arg))
                 ;; if the succeeding op is byte-switch, display the jump table
                 ;; used
		 (cond ((eq (car-safe (car-safe (cdr lap))) 'byte-switch)
                        (insert (format "<jump-table-%s (" (hash-table-test arg)))
                        (let ((first-time t))
                          (maphash #'(lambda (value tag)
                                       (if first-time
                                           (setq first-time nil)
                                         (insert " "))
                                       (insert (format "%s %s" value (cadr tag))))
                                   arg))
                        (insert ")>"))
                       ;; if the value of the constant is compiled code, then
                       ;; recursively disassemble it.
                       ((or (byte-code-function-p arg)
			    (and (eq (car-safe arg) 'macro)
				 (byte-code-function-p (cdr arg))))
			(cond ((byte-code-function-p arg)
			       (insert "<byte-code-function>\n"))
			      (t (insert "<compiled macro>\n")))
			(disassemble-internal
			 arg
			 (+ indent disassemble-recursive-indent 1)
			 nil))
		       ((eq (car-safe arg) 'byte-code)
			(insert "<byte code>\n")
			(disassemble-1	;recurse on byte-code object
			 arg
			 (+ indent disassemble-recursive-indent)))
		       ((eq (car-safe (car-safe arg)) 'byte-code)
			;; FIXME: I'm 99% sure bytecomp never generates
			;; this any more.
			(insert "(<byte code>...)\n")
			(mapc      ;Recurse on list of byte-code objects.
			 (lambda (obj)
                           (disassemble-1
                            obj
                            (+ indent disassemble-recursive-indent)))
			 arg))
		       (t
			;; really just a constant
			(let ((print-escape-newlines t))
			  (prin1 arg (current-buffer))))))
		)
	  (insert "\n")))))
  nil)

(defun re-disassemble (regexp &optional case-table)
  "Describe the compiled form of REGEXP in a separate window.
If CASE-TABLE is non-nil, use it as translation table for case-folding.

This function is mainly intended for maintenance of Emacs itself
and may change at any time.  It requires Emacs to be built with
`--enable-checking'."
  (interactive "XRegexp (Lisp expression): ")
  (let ((desc (with-temp-buffer
                (when case-table
                  (set-case-table case-table))
                (let ((case-fold-search (and case-table t)))
                  (re--describe-compiled regexp)))))
    (with-output-to-temp-buffer "*Regexp-disassemble*"
      (with-current-buffer standard-output
        (insert desc)))))

(provide 'disass)

;;; disass.el ends here
