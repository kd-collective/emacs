;;; ede.el --- Emacs Development Environment gloss  -*- lexical-binding: t; -*-

;; Copyright (C) 1998-2025 Free Software Foundation, Inc.

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: project, make
;; Version: 2.0

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
;;
;; EDE is the top level Lisp interface to a project management scheme
;; for Emacs.  Emacs does many things well, including editing,
;; building, and debugging.  Folks migrating from other IDEs don't
;; seem to think this qualifies, however, because they still have to
;; write the makefiles, and specify parameters to programs.
;;
;; This EDE mode will attempt to link these diverse programs together
;; into a comprehensive single interface, instead of a bunch of
;; different ones.

;;; Install
;;
;;  This command enables project mode on all files.
;;
;;  (global-ede-mode t)

;;; Code:

(require 'cedet)
(require 'cl-lib)
(require 'eieio)
(require 'cl-generic)
(require 'eieio-speedbar)
(require 'ede/source)
(require 'ede/base)
(require 'ede/auto)
(require 'ede/detect)

(eval-and-compile
  (load "ede/loaddefs" nil 'nomessage))

(declare-function ede-commit-project "ede/custom")
(declare-function ede-convert-path "ede/files")
(declare-function ede-directory-get-open-project "ede/files")
(declare-function ede-directory-get-toplevel-open-project "ede/files")
(declare-function ede-directory-project-p "ede/files")
(declare-function ede-find-subproject-for-directory "ede/files")
(declare-function ede-project-directory-remove-hash "ede/files")
(declare-function ede-toplevel "ede/base")
(declare-function ede-toplevel-project "ede/files")
(declare-function ede-up-directory "ede/files")
(declare-function semantic-lex-make-spp-table "semantic/lex-spp")

(defconst ede-version "2.0"
  "Current version of the Emacs EDE.")
(make-obsolete-variable 'ede-version 'emacs-version "29.1")

(defun ede-version ()
  "Display the current running version of EDE."
  (declare (obsolete emacs-version "29.1"))
  (interactive) (message "EDE %s" ede-version))

(defgroup ede nil
  "Emacs Development Environment."
  :group 'tools
  :group 'extensions)

(defcustom ede-auto-add-method 'ask
  "Whether a new source file should be automatically added to a target.
Whenever a new file is encountered in a directory controlled by a
project file, all targets are queried to see if it should be added.
If the value is `always', then the new file is added to the first
target encountered.  If the value is `multi-ask', then if more than one
target wants the file, the user is asked.  If only one target wants
the file, then it is automatically added to that target.  If the
value is `ask', then the user is always asked, unless there is no
target willing to take the file.  `never' means never perform the check."
  :type '(choice (const always)
		 (const multi-ask)
		 (const ask)
		 (const never)))

(defcustom ede-debug-program-function 'gdb
  "Default Emacs command used to debug a target."
  :type 'function) ; make this be a list of options some day

(defcustom ede-project-directories nil
  "Directories in which EDE may search for project files.
If the value is t, EDE may search in any directory.

If the value is a function, EDE calls that function with one
argument, the directory name; the function should return t if
EDE should look for project files in the directory.

Otherwise, the value should be a list of fully-expanded directory
names.  EDE searches for project files only in those directories.
If you invoke the commands \\[ede] or \\[ede-new] on a directory
that is not listed, Emacs will offer to add it to the list.

Any other value disables searching for EDE project files."
  :type '(choice (const :tag "Any directory" t)
		 (repeat :tag "List of directories"
			 (directory))
		 (function :tag "Predicate"))
  :version "23.4"
  :risky t)

(defun ede-directory-safe-p (dir)
  "Return non-nil if DIR is a safe directory to load projects from.
Projects that do not load a project definition as Emacs Lisp code
are safe, and can be loaded automatically.  Other project types,
such as those created with Project.ede files, are safe only if
specified by `ede-project-directories'."
  (setq dir (directory-file-name (expand-file-name dir)))
  ;; Load only if allowed by `ede-project-directories'.
  (or (eq ede-project-directories t)
      (and (functionp ede-project-directories)
	   (funcall ede-project-directories dir))
      (and (listp ede-project-directories)
	   (member dir ede-project-directories))))


;;; Management variables

(defvar ede-projects nil
  "A list of all active projects currently loaded in Emacs.")

(defvar-local ede-object-root-project nil
  "The current buffer's current root project.
If a file is under a project, this specifies the project that is at
the root of a project tree.")

(defvar-local ede-object-project nil
  "The current buffer's current project at that level.
If a file is under a project, this specifies the project that contains the
current target.")

(defvar-local ede-object nil
  "The current buffer's target object.
This object's class determines how to compile and debug from a buffer.")

(defvar ede-selected-object nil
  "The currently user-selected project or target.
If `ede-object' is nil, then commands will operate on this object.")

(defvar ede-constructing nil
  "Non-nil when constructing a project hierarchy.
If the project is being constructed from an autoload, then the
value is the autoload object being used.")

(defvar ede-deep-rescan nil
  "Non-nil means scan down a tree, otherwise rescans are top level only.
Do not set this to non-nil globally.  It is used internally.")


;;; Prompting
;;
(defun ede-singular-object (prompt)
  "Using PROMPT, choose a single object from the current buffer."
  (if (listp ede-object)
      (ede-choose-object prompt ede-object)
    ede-object))

(defun ede-choose-object (prompt list-o-o)
  "Using PROMPT, ask the user which OBJECT to use based on the name field.
Argument LIST-O-O is the list of objects to choose from."
  (let* ((al (object-assoc-list 'name list-o-o))
	 (ans (completing-read prompt al nil t)))
    (setq ans (assoc ans al))
    (cdr ans)))

;;; Menu and Keymap

(declare-function ede-speedbar "ede/speedbar" ())

(defvar ede-minor-mode-map
  (let ((map (make-sparse-keymap))
	(pmap (make-sparse-keymap)))
    (define-key pmap "e" #'ede-edit-file-target)
    (define-key pmap "a" #'ede-add-file)
    (define-key pmap "d" #'ede-remove-file)
    (define-key pmap "t" #'ede-new-target)
    (define-key pmap "g" #'ede-rescan-toplevel)
    (define-key pmap "s" #'ede-speedbar)
    (define-key pmap "f" #'ede-find-file)
    (define-key pmap "C" #'ede-compile-project)
    (define-key pmap "c" #'ede-compile-target)
    (define-key pmap "\C-c" #'ede-compile-selected)
    (define-key pmap "D" #'ede-debug-target)
    (define-key pmap "R" #'ede-run-target)
    ;; bind our submap into map
    (define-key map "\C-c." pmap)
    map)
  "Keymap used in project minor mode.")

(defvar global-ede-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [menu-bar cedet-menu]
      (cons "Development" cedet-menu-map))
    map)
  "Keymap used in `global-ede-mode'.")

;; Activate the EDE items in cedet-menu-map

(define-key cedet-menu-map [ede-find-file]
  '(menu-item "Find File in Project..." ede-find-file :enable ede-object
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede-speedbar]
  '(menu-item "View Project Tree" ede-speedbar :enable ede-object
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede]
  '(menu-item "Load Project" ede
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede-new]
  '(menu-item "Create Project" ede-new
	      :enable (not ede-object)
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede-target-options]
  '(menu-item "Target Options" ede-target-options
	      :filter ede-target-forms-menu
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede-project-options]
  '(menu-item "Project Options" ede-project-options
	      :filter ede-project-forms-menu
	      :visible global-ede-mode))
(define-key cedet-menu-map [ede-build-forms-menu]
  '(menu-item "Build Project" ede-build-forms-menu
	      :filter ede-build-forms-menu
	      :enable ede-object
	      :visible global-ede-mode))

(defun ede-buffer-belongs-to-target-p ()
  "Return non-nil if this buffer belongs to at least one target."
  (let ((obj ede-object))
    (if (consp obj)
	(setq obj (car obj)))
    (and obj (obj-of-class-p obj 'ede-target))))

(defun ede-buffer-belongs-to-project-p ()
  "Return non-nil if this buffer belongs to at least one project."
  (if (or (null ede-object) (consp ede-object)) nil
    (obj-of-class-p ede-object-project 'ede-project)))

(defun ede-menu-obj-of-class-p (class)
  "Return non-nil if some member of `ede-object' is a child of CLASS."
  (if (listp ede-object)
      (cl-some (lambda (o) (obj-of-class-p o class)) ede-object)
    (obj-of-class-p ede-object class)))

(defun ede-build-forms-menu (_menu-def)
  "Create a sub menu for building different parts of an EDE system.
Argument MENU-DEF is the menu definition to use."
  (easy-menu-filter-return
   (easy-menu-create-menu
    "Build Forms"
    (let ((obj (ede-current-project))
	  (newmenu nil) ;'([ "Build Selected..." ede-compile-selected t ]))
	  targets
	  targitems
	  ede-obj
	  (tskip nil))
      (if (not obj)
	  nil
	(setq targets (when (slot-boundp obj 'targets)
			(oref obj targets))
	      ede-obj (if (listp ede-object) ede-object (list ede-object)))
	;; First, collect the build items from the project
	(setq newmenu (append newmenu (ede-menu-items-build obj t)))
	;; Second, declare the current target menu items
	(if (and ede-obj (ede-menu-obj-of-class-p 'ede-target))
	    (while ede-obj
	      (setq newmenu (append newmenu
				    (ede-menu-items-build (car ede-obj) t))
		    tskip (car ede-obj)
		    ede-obj (cdr ede-obj))))
	;; Third, by name, enable builds for other local targets
	(while targets
	  (unless (eq tskip (car targets))
	    (setq targitems (ede-menu-items-build (car targets) nil))
	    (setq newmenu
		  (append newmenu
			  (if (= 1 (length targitems))
			      targitems
			    (cons (ede-name (car targets))
				  targitems))))
	    )
	  (setq targets (cdr targets)))
	;; Fourth, build sub projects.
	;; -- nerp
	;; Fifth, add make distribution
	(append newmenu (list [ "Make distribution" ede-make-dist t ]))
	)))))

(defun ede-target-forms-menu (_menu-def)
  "Create a target MENU-DEF based on the object belonging to this buffer."
  (easy-menu-filter-return
   (easy-menu-create-menu
    "Target Forms"
    (let ((obj (or ede-selected-object ede-object)))
      (append
       '([ "Add File" ede-add-file
	   (and (ede-current-project)
		(oref (ede-current-project) targets)) ]
	 [ "Remove File" ede-remove-file
	   (ede-buffer-belongs-to-project-p) ]
	 "-")
       (if (not obj)
	   nil
	 (if (and (not (listp obj)) (oref obj menu))
	     (oref obj menu)
	   (when (listp obj)
	     ;; This is bad, but I'm not sure what else to do.
	     (oref (car obj) menu)))))))))

(defun ede-project-forms-menu (_menu-def)
  "Create a target MENU-DEF based on the object belonging to this buffer."
  (easy-menu-filter-return
   (easy-menu-create-menu
    "Project Forms"
    (let* ((obj (ede-current-project))
	   (class (if obj (eieio-object-class obj)))
	   (menu nil))
      (condition-case err
	  (progn
	    (while (and class (slot-exists-p class 'menu))
	      ;;(message "Looking at class %S" class)
	      (setq menu (append menu (oref-default class menu))
		    class (eieio-class-parent class))
	      (if (listp class) (setq class (car class))))
	    (append
	     '( [ "Add Target" ede-new-target (ede-current-project) ]
		[ "Remove Target" ede-delete-target ede-object ]
		( "Default configuration" :filter ede-configuration-forms-menu )
		"-")
	     menu
	     ))
	(error (message "Err found: %S" err)
	       menu)
	)))))

(defun ede-configuration-forms-menu (_menu-def)
  "Create a submenu for selecting the default configuration for this project.
The current default is in the current object's CONFIGURATION-DEFAULT slot.
All possible configurations are in CONFIGURATIONS.
Argument MENU-DEF specifies the menu being created."
  (easy-menu-filter-return
   (easy-menu-create-menu
    "Configurations"
    (let* ((obj (ede-current-project))
	   (conf (when obj (oref obj configurations)))
	   (cdef (when obj (oref obj configuration-default)))
	   (menu nil))
      (dolist (C conf)
	(setq menu (cons (vector C (list 'ede-project-configurations-set C)
				 :style 'toggle
				 :selected (string= C cdef))
			 menu))
	)
      (nreverse menu)))))

(defun ede-project-configurations-set (newconfig)
  "Set the current project's current configuration to NEWCONFIG.
This function is designed to be used by `ede-configuration-forms-menu'
but can also be used interactively."
  (interactive
   (list (let* ((proj (ede-current-project))
		(configs (oref proj configurations)))
	   (completing-read "New configuration: "
			    configs nil t
			    (oref proj configuration-default)))))
  (oset (ede-current-project) configuration-default newconfig)
  (message "%s will now build in %s mode."
	   (eieio-object-name (ede-current-project))
	   newconfig))

(defun ede-customize-forms-menu (_menu-def)
  "Create a menu of the project, and targets that can be customized.
Argument MENU-DEF is the definition of the current menu."
  (easy-menu-filter-return
   (easy-menu-create-menu
    "Customize Project"
    (let* ((obj (ede-current-project))
	   targ)
      (when obj
	(setq targ (when (and obj (slot-boundp obj 'targets))
		     (oref obj targets)))
	;; Make custom menus for everything here.
	(append (list
		 (cons (concat "Project " (ede-name obj))
		       (eieio-customize-object-group obj))
		 [ "Reorder Targets" ede-project-sort-targets t ]
		 )
		(mapcar (lambda (o)
			  (cons (concat "Target " (ede-name o))
				(eieio-customize-object-group o)))
			targ)))))))


(defun ede-apply-object-keymap (&optional _default)
  "Add target specific keybindings into the local map.
Optional argument DEFAULT indicates if this should be set to the default
version of the keymap."
  (let ((object (or ede-object ede-selected-object))
	(proj ede-object-project))
    (condition-case nil
	(let ((keys (ede-object-keybindings object)))
	  (dolist (key
                   ;; Add keys for the project to whatever is in the current
                   ;; object so long as it isn't the same.
                   (if (eq object proj)
                       keys
                     (append keys (ede-object-keybindings proj))))
	    (local-set-key (concat "\C-c." (car key)) (cdr key))))
      (error nil))))

;;; Menu building methods for building
;;
(cl-defmethod ede-menu-items-build ((obj ede-project) &optional current)
  "Return a list of menu items for building project OBJ.
If optional argument CURRENT is non-nil, return sub-menu code."
  (if current
      (list [ "Build Current Project" ede-compile-project t ])
    (list (vector
	   (list
	    (concat "Build Project " (ede-name obj))
	    `(project-compile-project ,obj))))))

(cl-defmethod ede-menu-items-build ((obj ede-target) &optional current)
  "Return a list of menu items for building target OBJ.
If optional argument CURRENT is non-nil, return sub-menu code."
  (if current
      (list [ "Build Current Target" ede-compile-target t ])
    (list (vector
	   (concat "Build Target " (ede-name obj))
	   `(project-compile-target ,obj)
	   t))))

;;; Mode Declarations
;;

(defun ede-apply-target-options ()
  "Apply options to the current buffer for the active project/target."
  (ede-apply-project-local-variables)
  ;; Apply keymaps and preprocessor symbols.
  (ede-apply-object-keymap)
  (ede-apply-preprocessor-map)
  )

(defun ede-turn-on-hook ()
  "Turn on EDE minor mode in the current buffer if needed.
To be used in hook functions."
  (if (or (and (stringp (buffer-file-name))
	       (stringp default-directory))
	  ;; Emacs 21 has no buffer file name for directory edits.
	  ;; so we need to add these hacks in.
	  (eq major-mode 'dired-mode)
	  (eq major-mode 'vc-dir-mode))
      (ede-minor-mode 1)))

(define-minor-mode ede-minor-mode
  "Toggle EDE (Emacs Development Environment) minor mode.

If this file is contained, or could be contained in an EDE
controlled project, then this mode is activated automatically
provided `global-ede-mode' is enabled."
  :global nil
  (cond ((or (eq major-mode 'dired-mode)
	     (eq major-mode 'vc-dir-mode))
	 (ede-dired-minor-mode (if ede-minor-mode 1 -1)))
	(ede-minor-mode
	 (if (not ede-constructing)
	     (ede-initialize-state-current-buffer)
	   ;; If we fail to have a project here, turn it back off.
	   (ede-minor-mode -1)))))

(declare-function ede-directory-project-cons "ede/files" (dir &optional force))
(declare-function ede-toplevel-project-or-nil "ede/files" (dir))

(defun ede-initialize-state-current-buffer ()
  "Initialize the current buffer's state for EDE.
Sets buffer local variables for EDE."
  ;; due to inode recycling, make sure we don't
  ;; we flush projects deleted off the system.
  (ede-flush-deleted-projects)

  ;; Init the buffer.
  (let* ((ROOT nil)
	 (proj (ede-directory-get-open-project default-directory
					       (gv-ref ROOT))))

    (when (not proj)
      ;; If there is no open project, look up the project
      ;; autoloader to see if we should initialize.
      (let ((projdetect (ede-directory-project-cons default-directory)))

	(when projdetect
	  ;; No project was loaded, but we have a project description
	  ;; object.  This means that we try to load it.
	  ;;
	  ;; Before loading, we need to check if it is a safe
	  ;; project to load before requesting it to be loaded.

	  (when (or (oref (cdr projdetect) safe-p)
		    ;; The project style is not safe, so check if it is
		    ;; in `ede-project-directories'.
		    (let ((top (car projdetect)))
		      (ede-directory-safe-p top)))

	    ;; The project is safe, so load it in.
	    (setq proj (ede-load-project-file default-directory projdetect
	                                      (gv-ref ROOT)))))))

    ;; If PROJ is now loaded in, we can initialize our buffer to it.
    (when proj

      ;; ede-object represents the specific EDE related class that best
      ;; represents this buffer.  It could be a project (for a project file)
      ;; or a target.  Also save off ede-object-project, the project that
      ;; the buffer belongs to for the case where ede-object is a target.
      (setq ede-object (ede-buffer-object (current-buffer)
					  'ede-object-project))

      ;; Every project has a root.  It might be the same as ede-object.
      ;; Cache that also as the root is a very common thing to need.
      (setq ede-object-root-project
	    (or ROOT (ede-project-root ede-object-project)))

      ;; Check to see if we want to add this buffer to a target.
      (if (and (not ede-object) ede-object-project)
	  (ede-auto-add-to-target))

      ;; Apply any options from the found target.
      (ede-apply-target-options))))

(defun ede-reset-all-buffers ()
  "Reset all the buffers due to change in EDE."
  (interactive)
  (dolist (b (buffer-list))
    (when (buffer-file-name b)
      (with-current-buffer b
        ;; Reset all state variables
        (setq ede-object nil
              ede-object-project nil
              ede-object-root-project nil)
        ;; Now re-initialize this buffer.
        (ede-initialize-state-current-buffer)))))

;;;###autoload
(define-minor-mode global-ede-mode
  "Toggle global EDE (Emacs Development Environment) mode.

This global minor mode enables `ede-minor-mode' in all buffers in
an EDE controlled project."
  :global t
  (if global-ede-mode
      ;; Turn on global-ede-mode
      (progn
	(if semantic-mode
	    (define-key cedet-menu-map [cedet-menu-separator] '("--")))
	(add-hook 'semanticdb-project-predicate-functions #'ede-directory-project-p)
	(add-hook 'semanticdb-project-root-functions #'ede-toplevel-project-or-nil)
	(add-hook 'ecb-source-path-functions #'ede-ecb-project-paths)
	;; Append our hook to the end.  This allows mode-local to finish
	;; it's stuff before we start doing misc file loads, etc.
	(add-hook 'find-file-hook #'ede-turn-on-hook t)
	(add-hook 'dired-mode-hook #'ede-turn-on-hook)
	(add-hook 'kill-emacs-hook #'ede-save-cache)
	(ede-load-cache)
	(ede-reset-all-buffers))
    ;; Turn off global-ede-mode
    (define-key cedet-menu-map [cedet-menu-separator] nil)
    (remove-hook 'semanticdb-project-predicate-functions #'ede-directory-project-p)
    (remove-hook 'semanticdb-project-root-functions #'ede-toplevel-project-or-nil)
    (remove-hook 'ecb-source-path-functions #'ede-ecb-project-paths)
    (remove-hook 'find-file-hook #'ede-turn-on-hook)
    (remove-hook 'dired-mode-hook #'ede-turn-on-hook)
    (remove-hook 'kill-emacs-hook #'ede-save-cache)
    (ede-save-cache)
    (ede-reset-all-buffers)))

(defvar ede-ignored-file-alist
  '( "\\.cvsignore$"
     "\\.#"
     "~$"
     )
  "List of file name patterns that EDE will never ask about.")

(defun ede-ignore-file (filename)
  "Should we ignore FILENAME?"
  (let ((any nil)
	(F ede-ignored-file-alist))
    (while (and (not any) F)
      (when (string-match (car F) filename)
	(setq any t))
      (setq F (cdr F)))
    any))

(defun ede-auto-add-to-target ()
  "Look for a target that wants to own the current file.
Follow the preference set with `ede-auto-add-method' and get the list
of objects with the `ede-want-file-p' method."
  (if ede-object (error "ede-object already defined for %s" (buffer-name)))
  (if (or (eq ede-auto-add-method 'never)
	  (ede-ignore-file (buffer-file-name)))
      nil
    (let (desires)
      (dolist (want (oref (ede-current-project) targets));Find all the objects.
	(if (ede-want-file-p want (buffer-file-name))
            (push want desires)))
      (if desires
	  (cond ((or (eq ede-auto-add-method 'ask)
		     (and (eq ede-auto-add-method 'multi-ask)
			  (< 1 (length desires))))
		 (let* ((al (append
			     ;; some defaults
			     '(("none" . nil)
			       ("new target" . new))
			     ;; If we are in an unparented subdir,
			     ;; offer new a subproject
			     (if (ede-directory-project-p default-directory)
				 ()
			       '(("create subproject" . project)))
			     ;; Here are the existing objects we want.
			     (object-assoc-list 'name desires)))
			(case-fold-search t)
			(ans (completing-read
			      (format "Add %s to target: " (buffer-file-name))
			      al nil t)))
		   (setq ans (assoc ans al))
		   (cond ((eieio-object-p (cdr ans))
			  (ede-add-file (cdr ans)))
			 ((eq (cdr ans) 'new)
			  (ede-new-target))
			 (t nil))))
		((or (eq ede-auto-add-method 'always)
		     (and (eq ede-auto-add-method 'multi-ask)
			  (= 1 (length desires))))
		 (ede-add-file (car desires)))
		(t nil))))))


;;; Interactive method invocations
;;
(defun ede (dir)
  "Start up EDE for directory DIR.
If DIR has an existing project file, load it.
Otherwise, create a new project for DIR."
  (interactive
   ;; When choosing a directory to turn on, and we see some directory here,
   ;; provide that as the default.
   (let* ((top (ede-toplevel-project default-directory))
	  (promptdflt (or top default-directory)))
     (list (read-directory-name "Project directory: "
				promptdflt promptdflt t))))
  (unless (file-directory-p dir)
    (error "%s is not a directory" dir))
  (when (ede-directory-get-open-project dir)
    (error "%s already has an open project associated with it" dir))

  ;; Check if the directory has been added to the list of safe
  ;; directories.  It can also add the directory to the safe list if
  ;; the user chooses.
  (if (ede-check-project-directory dir)
      (progn
	;; Load the project in DIR, or make one.
	;; @TODO - IS THIS REAL?
	(ede-load-project-file dir)

	;; Check if we loaded anything on the previous line.
	(if (ede-current-project dir)

	    ;; We successfully opened an existing project.  Some open
	    ;; buffers may also be referring to this project.
	    ;; Resetting all the buffers will get them to also point
	    ;; at this new open project.
	    (ede-reset-all-buffers)

	  ;; ELSE
	  ;; There was no project, so switch to `ede-new' which is how
	  ;; a user can select a new kind of project to create.
	  (let ((default-directory (expand-file-name dir)))
	    (call-interactively 'ede-new))))

    ;; If the proposed directory isn't safe, then say so.
    (error "%s is not an allowed project directory in `ede-project-directories'"
	   dir)))

(defvar ede-check-project-query-fcn 'y-or-n-p
  "Function used to ask the user if they want to permit a project to load.
This is abstracted out so that tests can answer this question.")

(defun ede-check-project-directory (dir)
  "Check if DIR should be in `ede-project-directories'.
If it is not, try asking the user if it should be added; if so,
add it and save `ede-project-directories' via Customize.
Return nil if DIR should not be in `ede-project-directories'."
  (setq dir (directory-file-name (expand-file-name dir))) ; strip trailing /
  (or (eq ede-project-directories t)
      (and (functionp ede-project-directories)
	   (funcall ede-project-directories dir))
      ;; If `ede-project-directories' is a list, maybe add it.
      (when (listp ede-project-directories)
	(or (member dir ede-project-directories)
	    (when (funcall ede-check-project-query-fcn
			   (format-message
			    "`%s' is not listed in `ede-project-directories'.
Add it to the list of allowed project directories? "
			    dir))
	      (push dir ede-project-directories)
	      ;; If possible, save `ede-project-directories'.
	      (if (or custom-file user-init-file)
		  (let ((coding-system-for-read nil))
		    (customize-save-variable
		     'ede-project-directories
		     ede-project-directories)))
	      t)))))

(defun ede-new (type &optional name)
  "Create a new project starting from project type TYPE.
Optional argument NAME is the name to give this project."
  (interactive
   (list (completing-read "Project Type: "
			  (object-assoc-list
			   'name
			   (let* ((l ede-project-class-files)
				  (cp (ede-current-project))
				  (cs (when cp (eieio-object-class cp)))
				  (r nil))
			     (while l
			       (if cs
				   (if (eq (oref (car l) class-sym)
					   cs)
				       (setq r (cons (car l) r)))
				 (if (oref (car l) new-p)
				     (setq r (cons (car l) r))))
			       (setq l (cdr l)))
			     (when (not r)
			       (if cs
				   (error "No valid interactive sub project types for %s"
					  cs)
				 (error "EDE error: Can't find project types to create")))
			     r)
			   )
			  nil t)))
  (require 'ede/custom)
  ;; Make sure we have a valid directory
  (when (not (file-exists-p default-directory))
    (error "Cannot create project in non-existent directory %s" default-directory))
  (when (not (file-writable-p default-directory))
    (error "No write permissions for %s" default-directory))
  (unless (ede-check-project-directory default-directory)
    (error "%s is not an allowed project directory in `ede-project-directories'"
	   default-directory))
  ;; Make sure the project directory is loadable in the future.
  (ede-check-project-directory default-directory)
  ;; Create the project
  (let* ((obj (object-assoc type 'name ede-project-class-files))
	 (nobj (let ((f (oref obj file))
		     (pf (oref obj proj-file)))
		 ;; We are about to make something new, changing the
		 ;; state of existing directories.
		 (ede-project-directory-remove-hash default-directory)
		 ;; Make sure this class gets loaded!
		 (require f)
		 (make-instance (oref obj class-sym)
				:name (or name (read-string "Name: "))
				:directory default-directory
				:file (cond ((stringp pf)
					     (expand-file-name pf))
					    ((fboundp pf)
					     (funcall pf))
					    (t
					     (error
					      "Unknown file name specifier %S"
					      pf)))
				:targets nil)

		 ))
	 (inits (oref obj initializers)))
    ;; Force the name to match for new objects.
    (setf (slot-value nobj 'object-name) (oref nobj name))
    ;; Handle init args.
    (while inits
      (eieio-oset nobj (car inits) (car (cdr inits)))
      (setq inits (cdr (cdr inits))))
    (let ((pp (ede-parent-project)))
      (when pp
	(ede-add-subproject pp nobj)
	(ede-commit-project pp)))
    (ede-commit-project nobj))
  ;; Once the project is created, load it again.  This used to happen
  ;; lazily, but with project loading occurring less often and with
  ;; security in mind, this is now the safe time to reload.
  (ede-load-project-file default-directory)
  ;; Have the menu appear
  (setq ede-minor-mode t)
  ;; Allert the user
  (message "Project created and saved.  You may now create targets."))

(cl-defmethod ede-add-subproject ((proj-a ede-project) proj-b)
  "Add into PROJ-A, the subproject PROJ-B."
  (oset proj-a subproj (cons proj-b (oref proj-a subproj))))

(defun ede-invoke-method (sym &rest args)
  "Invoke method SYM on the current buffer's project object.
ARGS are additional arguments to pass to method SYM."
  (if (not ede-object)
      (error "Cannot invoke %s for %s" (symbol-name sym)
	     (buffer-name)))
  ;; Always query a target.  There should never be multiple
  ;; projects in a single buffer.
  (apply sym (ede-singular-object "Target: ") args))

(defun ede-rescan-toplevel ()
  "Rescan all project files."
  (interactive)
  (when (not (ede-toplevel))
    ;; This directory isn't open.  Can't rescan.
    (error "Attempt to rescan a project that isn't open"))

  ;; Continue
  (let ((root (ede-toplevel))
	(ede-deep-rescan t))

    (project-rescan root)
    (ede-reset-all-buffers)
    ))

(defun ede-new-target (&rest args)
  "Create a new target specific to this type of project file.
Different projects accept different arguments ARGS.
Typically you can specify NAME, target TYPE, and AUTOADD, where AUTOADD is
a string \"y\" or \"n\", which answers the y/n question done interactively."
  (interactive)
  (apply #'project-new-target (ede-current-project) args)
  (when (and buffer-file-name
	     (not (file-directory-p buffer-file-name)))
    (setq ede-object nil)
    (setq ede-object (ede-buffer-object (current-buffer)))
    (ede-apply-target-options)))

(defun ede-new-target-custom ()
  "Create a new target specific to this type of project file."
  (interactive)
  (project-new-target-custom (ede-current-project)))

(defun ede-delete-target (target)
  "Delete TARGET from the current project."
  (interactive (list
		(let ((ede-object (ede-current-project)))
		  (ede-invoke-method 'project-interactive-select-target
				     "Target: "))))
  ;; Find all sources in buffers associated with the condemned buffer.
  (let ((condemned (ede-target-buffers target)))
    (project-delete-target target)
    ;; Loop over all project controlled buffers
    (save-excursion
      (while condemned
	(set-buffer (car condemned))
	(setq ede-object nil)
	(setq ede-object (ede-buffer-object (current-buffer)))
	(setq condemned (cdr condemned))))
    (ede-apply-target-options)))

(defun ede-add-file (target)
  "Add the current buffer to a TARGET in the current project."
  (interactive (list
		(let ((ede-object (ede-current-project)))
		  (ede-invoke-method 'project-interactive-select-target
				     "Target: "))))
  (when (stringp target)
    (let* ((proj (ede-current-project))
	   (ob (object-assoc-list 'name (oref proj targets))))
      (setq target (cdr (assoc target ob)))))

  (when (not target)
    (error "Could not find specified target %S" target))

  (project-add-file target (buffer-file-name))
  (setq ede-object nil)

  ;; Setup buffer local variables.
  (ede-initialize-state-current-buffer)

  (when (not ede-object)
    (error "Can't add %s to target %s: Wrong file type"
	   (file-name-nondirectory (buffer-file-name))
	   (eieio-object-name target)))
  (ede-apply-target-options))

(defun ede-remove-file (&optional force)
  "Remove the current file from targets.
Optional argument FORCE forces the file to be removed without asking."
  (interactive "P")
  (if (not ede-object)
      (error "Cannot invoke remove-file for %s" (buffer-name)))
  (let ((eo (if (listp ede-object)
		(prog1
		    ede-object
		  (setq force nil))
	      (list ede-object))))
    (while eo
      (if (or force (y-or-n-p (format "Remove from %s? " (ede-name (car eo)))))
	  (project-remove-file (car eo) (buffer-file-name)))
      (setq eo (cdr eo)))
    (setq ede-object nil)
    (setq ede-object (ede-buffer-object (current-buffer)))
    (ede-apply-target-options)))

(defun ede-edit-file-target ()
  "Enter the project file to hand edit the current buffer's target."
  (interactive)
  (ede-invoke-method 'project-edit-file-target))

;;; Compilation / Debug / Run
;;
(defun ede-compile-project ()
  "Compile the current project."
  (interactive)
  ;; @TODO - This just wants the root.  There should be a better way.
  (let ((cp (ede-current-project)))
    (while (ede-parent-project cp)
      (setq cp (ede-parent-project cp)))
    (let ((ede-object cp))
      (ede-invoke-method 'project-compile-project))))

(defun ede-compile-selected (target)
  "Compile some TARGET from the current project."
  (interactive (list (project-interactive-select-target (ede-current-project)
							"Target to Build: ")))
  (project-compile-target target))

(defun ede-compile-target ()
  "Compile the current buffer's associated target."
  (interactive)
  (ede-invoke-method 'project-compile-target))

(defun ede-debug-target ()
  "Debug the current buffer's associated target."
  (interactive)
  (ede-invoke-method 'project-debug-target))

(defun ede-run-target ()
  "Run the current buffer's associated target."
  (interactive)
  (ede-invoke-method 'project-run-target))

(defun ede-make-dist ()
  "Create a distribution from the current project."
  (interactive)
  (let ((ede-object (ede-toplevel)))
    (ede-invoke-method 'project-make-dist)))


;;; EDE project target baseline methods.
;;
;;  If you are developing a new project type, you need to implement
;;  all of these methods, unless, of course, they do not make sense
;;  for your particular project.
;;
;;  Your targets should inherit from `ede-target', and your project
;;  files should inherit from `ede-project'.  Create the appropriate
;;  methods based on those below.

(cl-defmethod project-interactive-select-target ((this ede-project-placeholder) prompt)
					; checkdoc-params: (prompt)
  "Make sure placeholder THIS is replaced with the real thing, and pass through."
  (project-interactive-select-target this prompt))

(cl-defmethod project-interactive-select-target ((this ede-project) prompt)
  "Interactively query for a target that exists in project THIS.
Argument PROMPT is the prompt to use when querying the user for a target."
  (let ((ob (object-assoc-list 'name (oref this targets))))
    (cdr (assoc (completing-read prompt ob nil t) ob))))

(cl-defmethod project-add-file ((this ede-project-placeholder) file)
					; checkdoc-params: (file)
  "Make sure placeholder THIS is replaced with the real thing, and pass through."
  (project-add-file this file))

(cl-defmethod project-add-file ((ot ede-target) _file)
  "Add the current buffer into project target OT.
Argument FILE is the file to add."
  (error "add-file not supported by %s" (eieio-object-name ot)))

(cl-defmethod project-remove-file ((ot ede-target) _fnnd)
  "Remove the current buffer from project target OT.
Argument FNND is an argument."
  (error "remove-file not supported by %s" (eieio-object-name ot)))

(cl-defmethod project-edit-file-target ((_ot ede-target))
  "Edit the target OT associated with this file."
  (find-file (oref (ede-current-project) file)))

(cl-defmethod project-new-target ((proj ede-project) &rest _args)
  "Create a new target.  It is up to the project PROJ to get the name."
  (error "new-target not supported by %s" (eieio-object-name proj)))

(cl-defmethod project-new-target-custom ((proj ede-project))
  "Create a new target.  It is up to the project PROJ to get the name."
  (error "New-target-custom not supported by %s" (eieio-object-name proj)))

(cl-defmethod project-delete-target ((ot ede-target))
  "Delete the current target OT from its parent project."
  (error "add-file not supported by %s" (eieio-object-name ot)))

(cl-defmethod project-compile-project ((obj ede-project) &optional _command)
  "Compile the entire current project OBJ.
Argument COMMAND is the command to use when compiling."
  (error "compile-project not supported by %s" (eieio-object-name obj)))

(cl-defmethod project-compile-target ((obj ede-target) &optional _command)
  "Compile the current target OBJ.
Argument COMMAND is the command to use for compiling the target."
  (error "compile-target not supported by %s" (eieio-object-name obj)))

(cl-defmethod project-debug-target ((obj ede-target))
  "Run the current project target OBJ in a debugger."
  (error "debug-target not supported by %s" (eieio-object-name obj)))

(cl-defmethod project-run-target ((obj ede-target))
  "Run the current project target OBJ."
  (error "run-target not supported by %s" (eieio-object-name obj)))

(cl-defmethod project-make-dist ((this ede-project))
  "Build a distribution for the project based on THIS project."
  (error "Make-dist not supported by %s" (eieio-object-name this)))

(cl-defmethod project-dist-files ((this ede-project))
  "Return a list of files that constitute a distribution of THIS project."
  (error "Dist-files is not supported by %s" (eieio-object-name this)))

(cl-defmethod project-rescan ((this ede-project))
  "Rescan the EDE project THIS."
  (error "Rescanning a project is not supported by %s" (eieio-object-name this)))

(defun ede-ecb-project-paths ()
  "Return a list of all paths for all active EDE projects.
This functions is meant for use with ECB."
  (let ((p ede-projects)
	(d nil))
    (while p
      (setq d (cons (file-name-directory (oref (car p) file))
		    d)
	    p (cdr p)))
    d))

;;; PROJECT LOADING/TRACKING
;;
(defun ede-add-project-to-global-list (proj)
  "Add the project PROJ to the master list of projects.
On success, return the added project."
  (when (not proj)
    (error "No project created to add to master list"))
  (when (not (eieio-object-p proj))
    (error "Attempt to add non-object to master project list"))
  (when (not (obj-of-class-p proj 'ede-project-placeholder))
    (error "Attempt to add a non-project to the ede projects list"))
  (add-to-list 'ede-projects proj)
  proj)

(defun ede-delete-project-from-global-list (proj)
  "Remove project PROJ from the master list of projects."
  (setq ede-projects (remove proj ede-projects)))

(defun ede-flush-deleted-projects ()
  "Scan the projects list for projects which no longer exist.
Flush the dead projects from the project cache."
  (interactive)
  (let ((dead nil))
    (dolist (P ede-projects)
      (when (not (file-exists-p (oref P file)))
	(cl-pushnew P dead :test #'equal)))
    (dolist (D dead)
      (ede-delete-project-from-global-list D))
    ))

(defvar ede--disable-inode)             ;Defined in ede/files.el.
(declare-function ede--project-inode "ede/files" (proj))

(defun ede-global-list-sanity-check ()
  "Perform a sanity check to make sure there are no duplicate projects."
  (interactive)
  (let ((scanned nil))
    (dolist (P ede-projects)
      (if (member (oref P directory) scanned)
	  (error "Duplicate project (by dir) found in %s!" (oref P directory))
	(push (oref P directory) scanned)))
    (unless ede--disable-inode
      (setq scanned nil)
      (dolist (P ede-projects)
	(if (member (ede--project-inode P) scanned)
	  (error "Duplicate project (by inode) found in %s!" (ede--project-inode P))
	  (push (ede--project-inode P) scanned))))
    (message "EDE by directory %sis still sane." (if ede--disable-inode "" "& inode "))))

(defun ede-load-project-file (dir &optional detectin rootreturn)
  "Project file independent way to read a project in from DIR.
Optional DETECTIN is an autoload cons from `ede-detect-directory-for-project'
which can be passed in to save time.
Optional ROOTRETURN reference will return the root project for DIR."
  ;; Don't do anything if we are in the process of
  ;; constructing an EDE object.
  ;;
  ;; Prevent recursion.
  (unless ede-constructing

    ;; Only load if something new is going on.  Flush the dirhash.
    (ede-project-directory-remove-hash dir)

    ;; Do the load
    ;;(message "EDE LOAD : %S" file)
    (let* ((path (file-name-as-directory (expand-file-name dir)))
	   (detect (or detectin (ede-directory-project-cons path)))
	   (autoloader nil)
	   (toppath nil)
	   (o nil))

      (when detect
	(setq toppath (car detect))
	(setq autoloader (cdr detect))

	;; See if it's been loaded before.  Use exact matching since
	;; know that 'toppath' is the root of the project.
	(setq o (ede-directory-get-toplevel-open-project toppath 'exact))

	;; If not open yet, load it.
	(unless o
	  ;; NOTE: We set ede-constructing to the autoloader we are using.
	  ;;       Some project types have one class, but many autoloaders
	  ;;       and this is how we tell the instantiation which kind of
	  ;;       project to make.
	  (let ((ede-constructing autoloader))

	    ;; This is the only place `ede-auto-load-project' should be called.

	    (setq o (ede-auto-load-project autoloader toppath))))

	;; Return the found root project.
	(when rootreturn (if (symbolp rootreturn) (set rootreturn o)
	                   (setf (gv-deref rootreturn) o)))

	;; The project has been found (in the global list) or loaded from
	;; disk (via autoloader.)  We can now search for the project asked
	;; for from DIR in the sub-list.
	(ede-find-subproject-for-directory o path)

	;; Return the project.
	o))))

;;; PROJECT ASSOCIATIONS
;;
;; Moving between relative projects.  Associating between buffers and
;; projects.
(defun ede-parent-project (&optional obj)
  "Return the project belonging to the parent directory.
Return nil if there is no previous directory.
Optional argument OBJ is an object to find the parent of."
  (let* ((proj (or obj ede-object-project)) ;; Current project.
	 (root (if obj (ede-project-root obj)
		 ede-object-root-project)))
    ;; This case is a SHORTCUT if the project has defined
    ;; a way to calculate the project root.
    (if (and root proj (eq root proj))
	nil ;; we are at the root.
      ;; Else, we may have a nil proj or root.
      (let* ((thisdir (if obj (oref obj directory)
			default-directory))
	     (updir (ede-up-directory thisdir)))
        (when updir
	  ;; If there was no root, perhaps we can derive it from
	  ;; updir now.
	  (let ((root (or root (ede-directory-get-toplevel-open-project updir))))
	    (or
	     ;; This lets us find a subproject under root based on updir.
	     (and root
		  (ede-find-subproject-for-directory root updir))
	     ;; Try the all structure based search.
	     (ede-directory-get-open-project updir))))))))

(defun ede-current-project (&optional dir)
  "Return the current project file.
If optional DIR is provided, get the project for DIR instead."
  ;; If it matches the current directory, do we have a pre-existing project?
  (let ((proj (when (and (or (not dir) (string= dir default-directory))
			ede-object-project)
	        ede-object-project)))
    ;; No current project.
    (if proj
	proj
      (let* ((ldir (or dir default-directory)))
	(ede-directory-get-open-project ldir)))))

(defun ede-buffer-object (&optional buffer projsym)
  "Return the target object for BUFFER.
This function clears cached values and recalculates.
Optional PROJSYM is a symbol, which will be set to the project
that contains the target that becomes buffer's object."
  (save-excursion
    (if (not buffer) (setq buffer (current-buffer)))
    (set-buffer buffer)
    (setq ede-object nil)
    (let* ((localpo (ede-current-project))
	   (po localpo)
	   (top (ede-toplevel po)))
      (if po (setq ede-object (ede-find-target po buffer)))
      ;; If we get nothing, go with the backup plan of slowly
      ;; looping upward
      (while (and (not ede-object) (not (eq po top)))
	(setq po (ede-parent-project po))
	(if po (setq ede-object (ede-find-target po buffer))))
      ;; Filter down to 1 project if there are dups.
      (if (= (length ede-object) 1)
	  (setq ede-object (car ede-object)))
      ;; Track the project, if needed.
      (when (and projsym (symbolp projsym))
	(if ede-object
	    ;; If we found a target, then PO is the
	    ;; project to use.
	    (set projsym po)
	  ;; If there is no ede-object, then the projsym
	  ;; is whichever part of the project is most local.
	  (set projsym localpo))
	))
    ;; Return our findings.
    ede-object))

(cl-defmethod ede-target-in-project-p ((proj ede-project) target)
  "Is PROJ the parent of TARGET?
If TARGET belongs to a subproject, return that project file."
  (if (and (slot-boundp proj 'targets)
	   (memq target (oref proj targets)))
      proj
    (let ((s (oref proj subproj))
	  (ans nil))
      (while (and s (not ans))
	(setq ans (ede-target-in-project-p (car s) target))
	(setq s (cdr s)))
      ans)))

(defun ede-target-parent (target)
  "Return the project which is the parent of TARGET.
It is recommended you track the project a different way as this function
could become slow in time."
  (or ede-object-project
      ;; If not cached, derive it from the current directory of the target.
      (let ((ans nil) (projs ede-projects))
	(while (and (not ans) projs)
	  (setq ans (ede-target-in-project-p (car projs) target)
		projs (cdr projs)))
	ans)))

(cl-defmethod ede-find-target ((proj ede-project) buffer)
  "Fetch the target in PROJ belonging to BUFFER or nil."
  (with-current-buffer buffer

    ;; We can do a short-ut if ede-object local variable is set.
    (if ede-object
	;; If the buffer is already loaded with good EDE stuff, make sure the
	;; saved project is the project we're looking for.
	(when (and ede-object-project (eq proj ede-object-project)) ede-object)

      ;; If the variable wasn't set, then we are probably initializing the buffer.
      ;; In that case, search the file system.
      (if (ede-buffer-mine proj buffer)
	  proj
	(let ((targets (oref proj targets))
	      (f nil))
	  (while targets
	    (if (ede-buffer-mine (car targets) buffer)
		(setq f (cons (car targets) f)))
	    (setq targets (cdr targets)))
	  f)))))

(cl-defmethod ede-target-buffer-in-sourcelist ((this ede-target) buffer source)
  "Return non-nil if object THIS is in BUFFER to a SOURCE list.
Handles complex path issues."
  (member (ede-convert-path this (buffer-file-name buffer)) source))

(cl-defmethod ede-buffer-mine ((_this ede-project) _buffer)
  "Return non-nil if object THIS lays claim to the file in BUFFER."
  nil)

(cl-defmethod ede-buffer-mine ((this ede-target) buffer)
  "Return non-nil if object THIS lays claim to the file in BUFFER."
  (condition-case nil
      (ede-target-buffer-in-sourcelist this buffer (oref this source))
    ;; An error implies a bad match.
    (error nil)))


;;; Project mapping
;;
(defun ede-project-buffers (project)
  "Return a list of all active buffers controlled by PROJECT.
This includes buffers controlled by a specific target of PROJECT."
  (let ((bl (buffer-list))
	(pl nil))
    (while bl
      (with-current-buffer (car bl)
	(when (and ede-object (ede-find-target project (car bl)))
	  (setq pl (cons (car bl) pl))))
      (setq bl (cdr bl)))
    pl))

(defun ede-target-buffers (target)
  "Return a list of buffers that are controlled by TARGET."
  (let ((bl (buffer-list))
	(pl nil))
    (while bl
      (with-current-buffer (car bl)
	(if (if (listp ede-object)
		(memq target ede-object)
	      (eq ede-object target))
	    (setq pl (cons (car bl) pl))))
      (setq bl (cdr bl)))
    pl))

(defun ede-buffers ()
  "Return a list of all buffers controlled by an EDE object."
  (let ((bl (buffer-list))
	(pl nil))
    (while bl
      (with-current-buffer (car bl)
	(if ede-object
	    (setq pl (cons (car bl) pl))))
      (setq bl (cdr bl)))
    pl))

(defun ede-map-buffers (proc)
  "Execute PROC on all buffers controlled by EDE."
  (mapcar proc (ede-buffers)))

(cl-defmethod ede-map-project-buffers ((this ede-project) proc)
  "For THIS, execute PROC on all buffers belonging to THIS."
  (mapcar proc (ede-project-buffers this)))

(cl-defmethod ede-map-target-buffers ((this ede-target) proc)
  "For THIS, execute PROC on all buffers belonging to THIS."
  (mapcar proc (ede-target-buffers this)))

;; other types of mapping
(cl-defmethod ede-map-subprojects ((this ede-project) proc)
  "For object THIS, execute PROC on all direct subprojects.
This function does not apply PROC to sub-sub projects.
See also `ede-map-all-subprojects'."
  (mapcar proc (oref this subproj)))

(cl-defmethod ede-map-all-subprojects ((this ede-project) allproc)
  "For object THIS, execute PROC on THIS and all subprojects.
This function also applies PROC to sub-sub projects.
See also `ede-map-subprojects'."
  (apply #'append
	 (list (funcall allproc this))
	 (ede-map-subprojects
	  this
	  (lambda (sp)
	    (ede-map-all-subprojects sp allproc))
	  )))

;; (ede-map-all-subprojects (ede-load-project-file "../semantic/") (lambda (sp) (oref sp file)))

(cl-defmethod ede-map-targets ((this ede-project) proc)
  "For object THIS, execute PROC on all targets."
  (mapcar proc (oref this targets)))

(cl-defmethod ede-map-any-target-p ((this ede-project) proc)
  "For project THIS, map PROC to all targets and return if any non-nil.
Return the first non-nil value returned by PROC."
  (cl-some proc (oref this targets)))


;;; Some language specific methods.
;;
;; These items are needed by ede-cpp-root to add better support for
;; configuring items for Semantic.

;; Generic paths
(cl-defmethod ede-system-include-path ((_this ede-project))
  "Get the system include path used by project THIS."
  nil)

(cl-defmethod ede-system-include-path ((_this ede-target))
  "Get the system include path used by project THIS."
  nil)

(cl-defmethod ede-source-paths ((_this ede-project) _mode)
  "Get the base to all source trees in the current project for MODE.
For example, <root>/src for sources of c/c++, Java, etc,
and <root>/doc for doc sources."
  nil)

;; C/C++
(defun ede-apply-preprocessor-map ()
  "Apply preprocessor tables onto the current buffer."
  ;; TODO - what if semantic-mode isn't enabled?
  ;; what if we never want to load a C mode? Does this matter?
  ;; Note: This require is needed for the case where EDE ends up
  ;; in the hook order before Semantic based hooks.
  (require 'semantic/lex-spp)
  (when (and ede-object
	     (boundp 'semantic-lex-spp-project-macro-symbol-obarray))
    (let* ((objs ede-object)
	   (map (ede-preprocessor-map (if (consp objs)
					  (car objs)
					objs))))
      (when map
	;; We can't do a require for the below symbol.
	(setq semantic-lex-spp-project-macro-symbol-obarray
	      (semantic-lex-make-spp-table map)))
      (when (consp objs)
	(message "Choosing preprocessor syms for project %s"
		 (eieio-object-name (car objs)))))))

(cl-defmethod ede-system-include-path ((_this ede-project))
  "Get the system include path used by project THIS."
  nil)

(cl-defmethod ede-preprocessor-map ((_this ede-project))
  "Get the pre-processor map for project THIS."
  nil)

(cl-defmethod ede-preprocessor-map ((_this ede-target))
  "Get the pre-processor map for project THIS."
  nil)

;; Java
(cl-defmethod ede-java-classpath ((_this ede-project))
  "Return the classpath for this project."
  ;; @TODO - Can JDEE add something here?
  nil)


;;; Project-local variables

(defun ede-set (variable value &optional proj)
  "Set the project local VARIABLE to VALUE.
If VARIABLE is not project local, just use set.  Optional argument PROJ
is the project to use, instead of `ede-current-project'."
  (interactive "sVariable: \nxExpression: ")
  (let ((p (or proj (ede-toplevel))))
    ;; Make the change
    (ede-make-project-local-variable variable p)
    (ede-set-project-local-variable variable value p)
    (ede-commit-local-variables p)

    ;; This is a heavy hammer, but will apply variables properly
    ;; based on stacking between the toplevel and child projects.
    (ede-map-buffers 'ede-apply-project-local-variables)

    value))

(defun ede-apply-project-local-variables (&optional buffer)
  "Apply project local variables to the current buffer."
  (with-current-buffer (or buffer (current-buffer))
    ;; Always apply toplevel variables.
    (if (not (eq (ede-current-project) (ede-toplevel)))
	(ede-set-project-variables (ede-toplevel)))
    ;; Next apply more local project's variables.
    (if (ede-current-project)
	(ede-set-project-variables (ede-current-project)))
    ))

(defun ede-make-project-local-variable (variable &optional project)
  "Make VARIABLE project-local to PROJECT."
  (if (not project) (setq project (ede-toplevel)))
  (if (assoc variable (oref project local-variables))
      nil
    (oset project local-variables (cons (list variable)
					(oref project local-variables)))))

(defun ede-set-project-local-variable (variable value &optional project)
  "Set VARIABLE to VALUE for PROJECT.
If PROJ isn't specified, use the current project.
This function only assigns the value within the project structure.
It does not apply the value to buffers."
  (if (not project) (setq project (ede-toplevel)))
  (let ((va (assoc variable (oref project local-variables))))
    (unless va
      (error "Cannot set project variable until it is added with `ede-make-project-local-variable'"))
    (setcdr va value)))

(cl-defmethod ede-set-project-variables ((project ede-project) &optional buffer)
  "Set variables local to PROJECT in BUFFER."
  (if (not buffer) (setq buffer (current-buffer)))
  (with-current-buffer buffer
    (dolist (v (oref project local-variables))
      (make-local-variable (car v))
      (set (car v) (cdr v)))))

(cl-defmethod ede-commit-local-variables ((_proj ede-project))
  "Commit change to local variables in PROJ."
  nil)

;;; Integration with project.el

(defun project-try-ede (dir)
  ;; FIXME: This passes the `ROOT' dynbound variable, but I don't know
  ;; where it comes from!
  (let ((project-dir
         (locate-dominating-file
          dir
          (lambda (dir)
            (ede-directory-get-open-project dir 'ROOT)))))
    (when project-dir
      (ede-directory-get-open-project project-dir 'ROOT))))

(cl-defmethod project-root ((project ede-project))
  (ede-project-root-directory project))

;;; FIXME: Could someone look into implementing `project-ignores' for
;;; EDE and/or a faster `project-files'?

(add-hook 'project-find-functions #'project-try-ede 50)

(provide 'ede)

;; Include this last because it depends on ede.
(if t (require 'ede/files)) ;; Don't bother loading it at compile-time.

;; If this does not occur after the provide, we can get a recursive
;; load.  Yuck!
(with-eval-after-load 'speedbar
  (ede-speedbar-file-setup))

;;; ede.el ends here
