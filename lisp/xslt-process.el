;;;; xslt-process.el -- Invoke an XSLT processor on an Emacs buffer

;; Package: xslt-process
;; Author: Ovidiu Predescu <ovidiu@cup.hp.com>
;; Created: December 2, 2000
;; Time-stamp: <April  9, 2001 03:07:49 ovidiu>
;; Keywords: XML, XSLT
;; URL: http://www.geocities.com/SiliconValley/Monitor/7464/
;; Compatibility: XEmacs 21.1, Emacs 20.4

;; This file is not part of GNU Emacs

;; Copyright (C) 2000, 2001 Ovidiu Predescu

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
;; 02111-1307, USA.

;;; Comentary:

;; To use this package, put the lisp/ directory from this package in
;; your Emacs load-path and do:
;;
;; (autoload 'xslt-process-mode "xslt-process" "Run XSLT processor on buffer" t)
;;
;; Then, while being in an XML buffer, use the XSLT menu to either:
;;
;; - run an XSLT processor on the buffer and display the results in a
;; different one
;;
;; - run an XSLT processor in debug mode, so you can view the XSLT
;; processing as it happens
;;

(require 'jde)
(require 'cl)
(require 'xslt-speedbar)

;; From "custom" web page at http://www.dina.dk/~abraham/custom/
(eval-and-compile
  (condition-case ()
      (require 'custom)
    (error nil))
  (if (and (featurep 'custom) (fboundp 'custom-declare-variable))
      nil ;; We've got what we needed
    ;; We have the old custom-library, hack around it!
    (defmacro defgroup (&rest args)
      nil)
    (defmacro defface (var values doc &rest args)
      (` (progn
	   (defvar (, var) (quote (, var)))
	   ;; To make colors for your faces you need to set your .Xdefaults
	   ;; or set them up ahead of time in your .emacs file.
	   (make-face (, var))
	   )))
    (defmacro defcustom (var value doc &rest args)
      (` (defvar (, var) (, value) (, doc))))))

;;; User defaults

(defgroup xslt-process nil
  "Run an XSLT processor on an Emacs buffer."
  :group 'tools)

(defcustom xslt-process-default-processor (list 'Saxon)
  "*The default XSLT processor to be applied to an XML document."
  :group 'xslt-process
  :type '(list
	  (radio-button-choice
	   (const :tag "Saxon" Saxon)
	   (const :tag "Xalan 1.x" Xalan1)
	   (const :tag "Generic TrAX processor (Saxon 6.1 and greater, Xalan2 etc.)" TrAX)
	   (const :tag "Cocoon 1.x" Cocoon1))))

(defcustom xslt-process-cocoon1-properties-file ""
  "*The location of the Cocoon 1.x properties file."
  :group 'xslt-process
  :type '(file :must-match t :tag "Properties file"))

(defcustom xslt-process-jvm-arguments nil
  "*Additional arguments to be passed to the JVM.
Use this option to pass additional arguments to the JVM that might be
needed for the XSLT processor to function correctly."
  :group 'xslt-process
  :type '(repeat (string :tag "Argument")))

(defcustom xslt-process-additional-classpath nil
  "*Additional Java classpath to be passed when invoking Bean Shell.
Note that modifying this won't have any effect until you restart the
Bean Shell. You can do this by killing the *bsh* buffer."
  :group 'xslt-process
  :type '(repeat (file :must-match t :tag "Path")))

(defcustom xslt-process-key-binding "\C-c\C-xv"
  "*Keybinding for invoking the XSLT processor.
To enter a normal key, enter its corresponding character. To enter a
key with a modifier, either type C-q followed by the desired modified
keystroke, e.g. C-q C-c to enter Control c. To enter a function key,
use the [f1], [f2] etc. notation."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-toggle-debug-mode "\C-c\C-xd"
  "*Keybinding for toggling the debug mode."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-set-breakpoint "b"
  "*Keybinding for setting up a breakpoint at line in the current buffer.
The buffer has to be in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-delete-breakpoint "d"
  "*Keybinding for deleting the breakpoint at line in the current buffer.
The buffer has to be in the debug mode for this key to work"
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-enable/disable-breakpoint "e"
  "*Keybinding for enabling or disabling the breakpoint at line in the
current buffer. The buffer has to be in the debug mode for this key
to work"
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-quit-debug "q"
  "*Keybinding for exiting from the debug mode. The buffer has to be
in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-run "r"
  "*Keybinding for running the XSLT debugger on an XML file. The
buffer has to be in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-step "s"
  "*Keybinding for doing STEP in the debug mode. The buffer has to be
in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-next "n"
  "*Keybinding for doing NEXT in the debug mode. The buffer has to be
in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-finish "f"
  "*Keybinding for doing FINISH in the debug mode. The buffer has to be
in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-continue "c"
  "*Keybinding for doing CONTINUE in the debug mode. The buffer has to be
in the debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-stop "a"
  "*Keybinding for aborting a long XSLT processing. The buffer has to
be in debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defcustom xslt-process-do-quit "x"
  "*Keybing for exiting the debugger process. The buffer has to be in
debug mode for this key to work."
  :group 'xslt-process
  :type '(string :tag "Key"))

(defface xslt-process-enabled-breakpoint-face
  '((((class color) (background light))
     (:foreground "purple" :background "salmon")))
  "*Face used to highlight enabled breakpoints."
  :group 'font-lock-highlighting-faces)

(defface xslt-process-disabled-breakpoint-face
  '((((class color) (background light))
     (:foreground "purple" :background "wheat3")))
  "*Face used to highlight disabled breakpoints."
  :group 'font-lock-highlighting-faces)

(defface xslt-process-current-line-face
  '((((class color) (background light))
     (:foreground "black" :background "orange")))
  "*Face used to highlight disabled breakpoints."
  :group 'font-lock-highlighting-faces)

(defface xslt-process-indicator-face
  '((((class color) (background light))
     (:foreground "forest green" :background "black")))
  "*Face used to display the enter or exit in an element during debugging."
  :group 'font-lock-highlighting-faces)

;;;###autoload
(defcustom xslt-process-mode-line-string " XSLT"
  "*String displayed in the modeline when the xslt-process minor
mode is active. Set this to nil if you don't want a modeline
indicator."
  :group 'xslt-process
  :type 'string)

(defcustom xslt-process-debug-mode-line-string " XSLTd"
  "*String to appear in the modeline when the XSLT debug mode is active."
  :group 'xslt-process
  :type 'string)

;;; End of user customizations


;;; Other definitions

;;;###autoload
(defvar xslt-process-mode nil
  "Indicates whether the current buffer is in the XSLT-process minor mode.")

;;;###autoload
(defvar xslt-process-debug-mode nil
  "Indicates whether the current buffer is in debug mode.")

;; Keymaps
;;;###autoload
(defvar xslt-process-mode-map (make-sparse-keymap)
  "Keyboard bindings in normal XSLT-process mode enabled buffers.")

;;;###autoload
(defvar xslt-process-debug-mode-map (make-sparse-keymap)
  "Keyboard bindings for the XSLT debug mode.")
(make-variable-buffer-local 'xslt-process-mode)
(make-variable-buffer-local 'xslt-process-debug-mode)
(make-variable-buffer-local 'minor-mode-alist)

;; State variables of the mode
(defvar xslt-process-breakpoints (make-hashtable 10 'equal)
  "Hash table containing the currently defined breakpoints.")

(defvar xslt-process-comint-process nil
  "The XSLT debugger process.")

(defvar xslt-process-comint-buffer nil
  "The buffer within which the XSLT debugger process runs.")

(defvar xslt-process-last-selected-position [nil nil nil nil nil nil]
  "An array containing the filename, line, column, extent, annotation
and enter or exit action, describing the line where the debugger
stopped last time.")

(defvar xslt-process-debugger-process-started nil
  "Whether the XSLT debugger process has been started.")

(defvar xslt-process-process-state 'not-running
  "The state of the process. It can be either not-running, running or
stopped.")

(defvar xslt-process-source-frames-stack nil
  "The stack of source frames, a list of entries consisting of a
display name, a file name and a line number.")

(defvar xslt-process-style-frames-stack nil
  "The stack of style frames, a list of entries consisting of display
name, a file name and a line number.")

(defvar xslt-process-breakpoint-extents (make-hashtable 10 'equal)
  "Hash table of extents indexed by (filename . lineno). It is used to
keep track of the extents created to highlight lines.")

(defvar xslt-process-execution-context-error-function nil
  "Function to be called by the `xslt-process-report-error'. This
function should reset the proper state depending on the debugger
operation that was invoked.")

;; Other definitions
(defvar xslt-process-comint-process-name "xslt"
  "The name of the comint process.")

(defvar xslt-process-results-process-name "xslt results"
  "The name of the process that receives the result of the XSLT
processing.")

(defvar xslt-process-results-buffer-name "*xslt results*"
  "The name of the buffer to which the output of the XSLT processing
goes to.")

(defvar xslt-process-results-process nil
  "The Emacs process object that holds the connection with the socket
on which the XSLT results come from the XSLT processor.")

(defvar xslt-process-enter-glyph "=>"
  "Graphic indicator for entering inside an element.")

(defvar xslt-process-exit-glyph "<="
  "Graphic indicator for entering inside an element.")

(defvar xslt-process-breakpoint-set-hooks nil
  "List of functions to be called after a breakpoint is set.")

(defvar xslt-process-breakpoint-removed-hooks nil
  "List of functions to be called after a breakpoint is removed.")

(defvar xslt-process-breakpoint-enabled/disabled-hooks nil
  "List of functions to be called after a breakpoint is enabled or
disabled.")

(defvar xslt-process-source-frames-changed-hooks nil
  "List of functions to be called when the source frame stack
changes. The functions should take one argument, a list of (name
filename line) that indicate the new source frame stack.")

(defvar xslt-process-style-frames-changed-hooks nil
  "List of functions to be called when the style frame stack
changes. The functions should take one argument, a list of (name
filename line) that indicate the new style frame stack.")

;; Setup the main keymap
(define-key xslt-process-mode-map
  xslt-process-key-binding 'xslt-process-invoke)
(define-key xslt-process-mode-map
  xslt-process-toggle-debug-mode 'xslt-process-toggle-debug-mode)

;; Setup the keymap used for debugging
(define-key xslt-process-debug-mode-map
  xslt-process-key-binding 'xslt-process-invoke)
(define-key xslt-process-debug-mode-map
  xslt-process-toggle-debug-mode 'xslt-process-toggle-debug-mode)
(define-key xslt-process-debug-mode-map
  xslt-process-set-breakpoint 'xslt-process-set-breakpoint)
(define-key xslt-process-debug-mode-map
  xslt-process-delete-breakpoint 'xslt-process-delete-breakpoint)
(define-key xslt-process-debug-mode-map
  xslt-process-quit-debug 'xslt-process-quit-debug)
(define-key xslt-process-debug-mode-map
  xslt-process-set-breakpoint 'xslt-process-set-breakpoint)
(define-key xslt-process-debug-mode-map
  xslt-process-delete-breakpoint 'xslt-process-delete-breakpoint)
(define-key xslt-process-debug-mode-map
  xslt-process-enable/disable-breakpoint
  'xslt-process-enable/disable-breakpoint)
(define-key xslt-process-debug-mode-map
  xslt-process-do-run 'xslt-process-do-run)
(define-key xslt-process-debug-mode-map
  xslt-process-do-step 'xslt-process-do-step)
(define-key xslt-process-debug-mode-map
  xslt-process-do-next 'xslt-process-do-next)
(define-key xslt-process-debug-mode-map
  xslt-process-do-finish 'xslt-process-do-finish)
(define-key xslt-process-debug-mode-map
  xslt-process-do-continue 'xslt-process-do-continue)
(define-key xslt-process-debug-mode-map
  xslt-process-do-stop 'xslt-process-do-stop)
(define-key xslt-process-debug-mode-map
  xslt-process-do-quit 'xslt-process-do-quit)

;;;###autoload
(defun xslt-process-mode (&optional arg)
  "Minor mode to invoke an XSLT processor on the current buffer.

This mode spawns off a Java Bean Shell process in the background to
run an XSLT processor of your choice. This minor mode makes use of
Emacs-Lisp functionality defined in JDE, the Java Development
Environment for Emacs.

With no argument, this command toggles the xslt-process mode. With a
prefix argument ARG, turn xslt-process minor mode on iff ARG is
positive.

Bindings:
\\[xslt-process-invoke]: Invoke the XSLT processor on the current buffer.

Hooks:
xslt-process-hook is run after the xslt-process minor mode is entered.

For more information please check:

xslt-process:    http://www.geocities.com/SiliconValley/Monitor/7464/
Emacs JDE:       http://sunsite.dk/jde/
Java Bean Shell: http://www.beanshell.org/
"
  (interactive "P")
  (setq xslt-process-mode
	(if (null arg)
	    (not xslt-process-mode)
	  (> (prefix-numeric-value arg) 0)))
  (if xslt-process-mode
      (progn
	(xslt-process-setup-minor-mode xslt-process-mode-map
				       xslt-process-mode-line-string)
	(add-submenu
	 nil
	 '("XSLT"
	   ["Run XSLT processor" xslt-process-invoke :active t]
	   ["--:shadowEtchedIn" nil]
	   ["Toggle debug mode" xslt-process-toggle-debug-mode :active t]
	   ["Set breakpoint" xslt-process-set-breakpoint
	    :active (and xslt-process-debug-mode
			 (not (xslt-process-is-breakpoint
			       (xslt-process-new-breakpoint-here))))]
	   ["Delete breakpoint" xslt-process-delete-breakpoint
	    :active (and xslt-process-debug-mode
			 (xslt-process-is-breakpoint
			  (xslt-process-new-breakpoint-here)))]
	   ["Breakpoint enabled" xslt-process-enable/disable-breakpoint
	    :active (and xslt-process-debug-mode
			 (xslt-process-is-breakpoint
			  (xslt-process-new-breakpoint-here)))
	    :style toggle
	    :selected (and xslt-process-debug-mode
			 (xslt-process-breakpoint-is-enabled
			  (xslt-process-new-breakpoint-here)))]
	   ["--:shadowEtchedIn" nil]
	   ["Run debugger" xslt-process-do-run
	    :active xslt-process-debug-mode]
	   ["Step" xslt-process-do-step
	    :active (eq xslt-process-process-state 'stopped)]
	   ["Next" xslt-process-do-next
	    :active (eq xslt-process-process-state 'stopped)]
	   ["Finish" xslt-process-do-finish
	    :active (eq xslt-process-process-state 'stopped)]
	   ["Continue" xslt-process-do-continue
	    :active (eq xslt-process-process-state 'stopped)]
	   ["Stop" xslt-process-do-stop
	    :active (eq xslt-process-process-state 'running)]
	   ["Quit debugger" xslt-process-do-quit
	    :active xslt-process-debugger-process-started]
	   ["--:shadowEtchedIn" nil]
	   ["Speedbar" xslt-process-speedbar-frame-mode
	    :style toggle
	    :selected (and (boundp 'speedbar-frame)
			   (frame-live-p speedbar-frame)
			   (frame-visible-p speedbar-frame))]
	   )))
    (remassoc 'xslt-process-mode minor-mode-alist)
    (remassoc 'xslt-process-mode minor-mode-map-alist)
    (delete-menu-item '("XSLT"))
    (xslt-process-toggle-debug-mode 0))
  ;; Force modeline to redisplay
  (redraw-mode-line))

(defun xslt-process-toggle-debug-mode (arg)
  "*Setup a buffer in the XSLT debugging mode.
This essentially makes the buffer read-only and binds various keys to
different actions for faster operations."
  (interactive "P")
  (block nil
    (let ((filename (file-truename (buffer-file-name))))
      (if (or (and arg (> (prefix-numeric-value arg) 0))
	      (not xslt-process-debug-mode))
	  (progn
	    ;; If debug mode already enabled, don't do anything
	    (if xslt-process-debug-mode
		(return))
	    ;; Enable the debug mode
	    (setq xslt-process-debug-mode t)
	    (toggle-read-only 1)
	    (xslt-process-change-current-line-highlighting t filename)
	    (xslt-process-change-breakpoints-highlighting t filename)
	    (xslt-process-setup-minor-mode xslt-process-debug-mode-map
					   xslt-process-debug-mode-line-string))
	;; If debug mode already disabled, don't do anything
	(if (not xslt-process-debug-mode)
	    (return))
	(toggle-read-only 0)
	(xslt-process-change-current-line-highlighting nil filename)
	(xslt-process-change-breakpoints-highlighting nil filename)
	(xslt-process-setup-minor-mode xslt-process-mode-map
				       xslt-process-mode-line-string)
	;; Disable the debug mode if it's enabled
	(setq xslt-process-debug-mode nil)))))

(defun xslt-process-quit-debug ()
  "*Quit the debugger and exit from the xslt-process mode."
  (interactive)
  (xslt-process-toggle-debug-mode 0))

(put 'Saxon 'additional-params 'xslt-saxon-additional-params)
(put 'Xalan1 'additional-params 'xslt-xalan1-additional-params)
(put 'TrAX 'additional-params 'xslt-trax-additional-params)
(put 'Cocoon1 'additional-params 'xslt-cocoon1-additional-params)

(defun xslt-saxon-additional-params ())
(defun xslt-xalan1-additional-params ())
(defun xslt-trax-additional-params ())

(defun xslt-cocoon1-additional-params ()
  (if (or (null xslt-process-cocoon1-properties-file)
	  (equal xslt-process-cocoon1-properties-file ""))
      (error "No Cocoon properties file specified."))
  (bsh-eval (concat "xslt.Cocoon1.setPropertyFilename(\""
		    xslt-process-cocoon1-properties-file "\");"))
  (setq cocoon-user-agent
	(if (and
	     (local-variable-p 'user-agent (current-buffer))
	     (boundp 'user-agent))
	    (if (stringp user-agent)
		user-agent
	      (symbol-name user-agent))
	  nil))
  (bsh-eval (concat "xslt.Cocoon1.setUserAgent(\""
		    cocoon-user-agent "\");"))
  (makunbound 'user-agent))

(defun xslt-process-find-xslt-directory ()
  "Return the path to the xslt-process directory."
  (file-truename
   (concat (file-name-directory (locate-library "xslt-process")) "../")))

(defun xslt-process-invoke ()
  "This is the main function which invokes the XSLT processor of your
choice on the current buffer."
  (interactive)
  (let* ((temp-directory
	  (or (if (fboundp 'temp-directory) (temp-directory))
	      (if (boundp 'temporary-file-directory) temporary-file-directory)))
	 (classpath
	  (if (boundp 'jde-global-classpath)
	      jde-global-classpath
	    nil))
	 (classpath-env (if (getenv "CLASSPATH")
			    (split-string (getenv "CLASSPATH")
					  jde-classpath-separator)
			  nil))
	 (out-buffer (get-buffer-create "*xslt output*"))
	 (msg-buffer (get-buffer-create "*xslt messages*"))
	 (filename (if (buffer-file-name)
		       (expand-file-name (buffer-file-name))
		     (error "No filename associated with this buffer.")))
	 (xslt-jar (concat
		    (xslt-process-find-xslt-directory) "java/xslt.jar"))
	 (tmpfile (make-temp-name (concat temp-directory "/xsltout")))
	 ; Set the name of the XSLT processor. This is either specified
	 ; in the local variables of the file or is the default one.
	 (xslt-processor
	  (progn
	    ; Force evaluation of local variables
	    (hack-local-variables t)
	    (or
	     (if (and
		  (local-variable-p 'processor (current-buffer))
		  (boundp 'processor))
		 (if (stringp processor)
		     processor
		   (symbol-name processor)))
	     (symbol-name (car xslt-process-default-processor))))))
    (save-excursion
      ; Reset any local variables in the source buffer so the next
      ; time we execute we correctly pick up the default processor
      ; even if the user decides to remove the local variable
      (makunbound 'processor)
      ; Prepare to invoke the Java method to process the XML document
      (setq jde-global-classpath
	    (mapcar 'expand-file-name
		    (union (append jde-global-classpath (list xslt-jar))
			   (union xslt-process-additional-classpath
				  classpath-env))))
      ; Append the additional arguments to the arguments passed to bsh
      (setq bsh-vm-args (union xslt-process-jvm-arguments bsh-vm-args))
      ; Setup additional arguments to the processor
      (setq func (get (intern-soft xslt-processor) 'additional-params))
      (if (not (null func)) (funcall func))
      ; Prepare the buffers
      (save-some-buffers)
      (set-buffer msg-buffer)
      (erase-buffer)
      (set-buffer out-buffer)
      (erase-buffer)
      ; Invoke the processor, displaying the result in a buffer and
      ; any error messages in an additional buffer
      (condition-case nil
	  (progn
	    (setq messages (bsh-eval
			    (concat "xslt." xslt-processor ".invoke(\""
				    filename "\", \"" tmpfile
				    "\");")))
	    (setq jde-global-classpath classpath)
	    (if (file-exists-p tmpfile)
		(progn
		  (set-buffer out-buffer)
		  (insert-file-contents tmpfile)
		  (delete-file tmpfile)
		  (display-buffer out-buffer)
		  (if (not (string= messages ""))
		      (xslt-process-display-messages messages
						     msg-buffer out-buffer))
		  (message "Done invoking %s." xslt-processor))
	      (message (concat "Cannot process "
			       (file-name-nondirectory filename) "."))
	      (xslt-process-display-messages messages msg-buffer out-buffer)))
	(error (progn
		 (message
		  (concat "Could not process file, most probably "
			  xslt-processor
			  " could not be found!"))
		 (setq jde-global-classpath classpath)))))))

(defun xslt-process-display-messages (messages msg-buffer out-buffer)
  (set-buffer msg-buffer)
  (insert messages)
  (let ((msg-window (get-buffer-window msg-buffer))
	(out-window (get-buffer-window out-buffer)))
    (if (not msg-window)
	(split-window out-window))
    (display-buffer msg-buffer)))  

;;;
;;; The last selected position
;;;

(defun xslt-process-last-selected-position-filename (&optional filename)
  "Return the filename of the last selected position."
  (if filename
      (aset xslt-process-last-selected-position 0 filename))
  (aref xslt-process-last-selected-position 0))

(defun xslt-process-last-selected-position-line (&optional position)
  "Return the line of the last selected position."
  (if position
      (aset xslt-process-last-selected-position 1 position))
  (aref xslt-process-last-selected-position 1))

(defun xslt-process-last-selected-position-column (&optional column)
  "Return the column of the last selected position."
  (if column
      (aset xslt-process-last-selected-position 2 column))
  (aref xslt-process-last-selected-position 2))

(defun xslt-process-last-selected-position-extent (&optional extent)
  "Return the extent used to highlight the last selected position."
  (if extent
      (aset xslt-process-last-selected-position 3 extent))
  (aref xslt-process-last-selected-position 3))

(defun xslt-process-last-selected-position-annotation (&optional annotation)
  "Return the extent used to highlight the last selected position."
  (if annotation
      (aset xslt-process-last-selected-position 4 annotation))
  (aref xslt-process-last-selected-position 4))

(defun xslt-process-last-selected-position-enter/exit? (&optional action)
  "Return the extent used to highlight the last selected position. If
ACTION is non-nil, it is set as the new value."
  (if action
      (aset xslt-process-last-selected-position 5 action))
  (aref xslt-process-last-selected-position 5))

;;;
;;; Source and Style Frames
;;;

(defun xslt-process-frame-display-name (frame)
  "Returns the display name of frame."
  (car frame))

(defun xslt-process-frame-file-name (frame)
  "Returns the file name of a frame."
  (cadr frame))

(defun xslt-process-frame-line (frame)
  "Returns the line number of a frame."
  (caddr frame))

;;;
;;; Breakpoints
;;;

(defun xslt-process-new-breakpoint-here ()
  "Returns a breakpoint object at filename and line number of the
current buffer or nil otherwise. By default the breakpoint is enabled."
  (let ((filename (file-truename (buffer-file-name)))
	(line (save-excursion (progn (end-of-line) (count-lines 1 (point))))))
    (cons filename line)))

(defun xslt-process-intern-breakpoint (breakpoint state)
  "Interns BREAKPOINT into the internal hash table that keeps track of
breakpoints. STATE should be either t for an enabled breakpoint, or
nil for a disabled breakpoint."
  (puthash breakpoint (if state 'enabled 'disabled) xslt-process-breakpoints))

(defun xslt-process-is-breakpoint (breakpoint)
  "Checks whether BREAKPOINT is setup in buffer at line."
  (not (eq (gethash breakpoint xslt-process-breakpoints) nil)))

(defun xslt-process-breakpoint-is-enabled (breakpoint)
  "Returns t if BREAKPOINT is enabled, nil otherwise. Use
`xslt-process-is-breakpoint' before calling this method to find out
whether BREAKPOINT is a breakpoint or not. This method returns nil
either when the breakpoint doesn't exist or when the breakpoint is
disabled."
  (eq (gethash breakpoint xslt-process-breakpoints) 'enabled))

(defun xslt-process-remove-breakpoint (breakpoint)
  "Remove BREAKPOINT from the internal data structures."
  (let ((filename (xslt-process-breakpoint-filename breakpoint))
	(line (xslt-process-breakpoint-line breakpoint)))
    (remhash (cons filename line) xslt-process-breakpoints)))

(defun xslt-process-breakpoint-filename (breakpoint)
  "Returns the filename of the BREAKPOINT."
  (car breakpoint))

(defun xslt-process-breakpoint-line (breakpoint)
  "Return the line number of the BREAKPOINT."
  (cdr breakpoint))

(defun xslt-process-set-breakpoint ()
  "*Set a breakpoint at line in the current buffer or print an error
message if a breakpoint is already setup."
  (interactive)
  (let* ((breakpoint (xslt-process-new-breakpoint-here))
	 (filename (xslt-process-breakpoint-filename breakpoint))
	 (line (xslt-process-breakpoint-line breakpoint)))
    (if (xslt-process-is-breakpoint breakpoint)
	(message "Breakpoint already set in %s at %s" filename line)
      (xslt-process-send-command (format "b %s %s" filename line))
      (xslt-process-intern-breakpoint breakpoint t)
      (xslt-process-highlight-breakpoint breakpoint)
      (run-hooks 'xslt-process-breakpoint-set-hooks)
      (message "Set breakpoint in %s at %s." filename line))))

(defun xslt-process-delete-breakpoint ()
  "*Remove the breakpoint at current line in the selected buffer."
  (interactive)
  (let* ((breakpoint (xslt-process-new-breakpoint-here))
	 (filename (xslt-process-breakpoint-filename breakpoint))
	 (line (xslt-process-breakpoint-line breakpoint)))
    (if (xslt-process-is-breakpoint breakpoint)
	(progn
	  (xslt-process-remove-breakpoint breakpoint)
	  ;; Send the command to the XSLT debugger, but don't start it
	  ;; if it's not started.
	  (xslt-process-send-command (format "d %s %s" filename line) t)
	  (xslt-process-unhighlight-breakpoint breakpoint)
	  (run-hooks 'xslt-process-breakpoint-removed-hooks)
	  (message "Removed breakpoint in %s at %s." filename line))
      (message (format "No breakpoint in %s at %s" filename line)))))

(defun xslt-process-enable/disable-breakpoint ()
  "*Enable or disable the breakpoint at the current line in buffer, depending
on its state."
  (interactive)
  (let* ((breakpoint (xslt-process-new-breakpoint-here))
	 (filename (xslt-process-breakpoint-filename breakpoint))
	 (line (xslt-process-breakpoint-line breakpoint)))
    (if (xslt-process-is-breakpoint breakpoint)
	(progn
	  ;; Toggle the state of the breakpoint
	  (xslt-process-intern-breakpoint
	   breakpoint
	   (not (xslt-process-breakpoint-is-enabled breakpoint)))
	  ;; Change the face to visually show the status of the
	  ;; breakpoint and print informative message
	  (xslt-process-unhighlight-breakpoint breakpoint)
	  (xslt-process-highlight-breakpoint breakpoint)
	  (if (xslt-process-breakpoint-is-enabled breakpoint)
	       (progn
		(xslt-process-send-command (format "ena %s %s" filename line))
		(message "Enabled breakpoint in %s at %s" filename line))
	     (progn
	       (xslt-process-send-command (format "dis %s %s" filename line))
	       (message "Disabled breakpoint in %s at %s" filename line)))
	  (run-hooks 'xslt-process-breakpoint-enabled/disabled-hooks))
      (message (format "No breakpoint in %s at %s" filename line)))))

;;;
;;; Debugger commands
;;;

(defun xslt-process-do-run ()
  "*Send the run command to the XSLT debugger."
  (interactive)
  (block nil
    (if (not (eq xslt-process-process-state 'not-running))
	(if (yes-or-no-p-maybe-dialog-box
	     "The XSLT debugger is already running, restart it? ")
	    (xslt-process-do-quit t)
	  (return)))
    (let ((filename (buffer-file-name)))
      (setq xslt-process-process-state 'running)
      (xslt-process-send-command (concat "r " filename))
      (setq xslt-process-execution-context-error-function
	    (lambda ()
	      (setq xslt-process-process-state 'not-running)))
      (speedbar-with-writable
	(let ((buffer (get-buffer xslt-process-results-buffer-name)))
	  (if buffer (erase-buffer buffer))))
      (message "Running the XSLT debugger..."))))

(defun xslt-process-do-step ()
  "*Send a STEP command to the XSLT debugger."
  (interactive)
  (if (eq xslt-process-process-state 'stopped)
      (progn
	(setq xslt-process-process-state 'running)
	(xslt-process-send-command "s"))
    (message "XSLT debugger is not running.")))

(defun xslt-process-do-next ()
  "*Send a NEXT command to the XSLT debugger."
  (interactive)
  (if (eq xslt-process-process-state 'stopped)
      (progn
	(setq xslt-process-process-state 'running)
	(xslt-process-send-command "n"))
    (message "XSLT debugger is not running.")))

(defun xslt-process-do-finish ()
  "*Send a FINISH command to the XSLT debugger."
  (interactive)
  (if (eq xslt-process-process-state 'stopped)
      (progn
	(setq xslt-process-process-state 'running)
	(xslt-process-send-command "f"))
    (message "XSLT debugger is not running.")))

(defun xslt-process-do-continue ()
  "*Send a CONTINUE command to the XSLT debugger."
  (interactive)
  (if (eq xslt-process-process-state 'stopped)
      (progn
	(setq xslt-process-process-state 'running)
	(xslt-process-send-command "c"))
    (message "XSLT debugger is not running.")))

(defun xslt-process-do-stop ()
  "*Send a STOP command to the XSLT debugger, potentially stopping the
debugger from a long processing with no breakpoints setup."
  (interactive)
  (if (eq xslt-process-process-state 'running)
      (xslt-process-send-command "stop")))

(defun xslt-process-do-quit (&optional dont-ask)
  "*Quit the XSLT debugger."
  (interactive)
  (if xslt-process-comint-buffer
      (if (or dont-ask
	      (yes-or-no-p-maybe-dialog-box "Really quit the XSLT debugger? "))
	  (progn
	    (xslt-process-send-command "q" t)
	    (kill-buffer xslt-process-comint-buffer)
	    (setq xslt-process-debugger-process-started nil)
	    ;; Delete maybe the breakpoints?
	    (if (and (not dont-ask)
		      (> (hashtable-fullness xslt-process-breakpoints) 0)
		     (yes-or-no-p-maybe-dialog-box "Delete all breakpoints? "))
		(progn
		  (xslt-process-change-breakpoints-highlighting nil)
		  (clrhash xslt-process-breakpoints)
		  (run-hooks 'xslt-process-breakpoint-removed-hooks)))
	    ;; Reset the source and style frame stacks
	    (setq xslt-process-source-frames-stack nil)
	    (setq xslt-process-style-frames-stack nil)
	    (run-hooks 'xslt-process-source-frames-changed-hooks)
	    (run-hooks 'xslt-process-style-frames-changed-hooks)))
    (message "XSLT debugger not running.")))

;;;
;;; Dealing with the presentation of breakpoints and the current line
;;; indicator
;;;

(defun xslt-process-change-breakpoints-highlighting (flag &optional filename)
  "Highlights or unhighlights, depending on FLAG, all the breakpoints
in the buffer visiting FILENAME. If FILENAME is not specified or is
nil, it changes the highlighting on the breakpoints in all the
buffers. It doesn't affect the current state of the breakpoints."
  (maphash
   (lambda (breakpoint state)
     (let ((fname (xslt-process-breakpoint-filename breakpoint)))
       (if (or (not filename) (equal filename fname))
	   (if flag
	       (xslt-process-highlight-breakpoint breakpoint state)
	     (xslt-process-unhighlight-breakpoint breakpoint)))))
   xslt-process-breakpoints))

(defun xslt-process-change-current-line-highlighting (flag filename)
  "Highlights or unhighlights, depending on FLAG, the current line
indicator."
  (if (and xslt-process-last-selected-position
	   (equal filename (xslt-process-last-selected-position-filename)))
      (save-excursion
	(let* ((buffer (xslt-process-get-file-buffer filename))
	       (line (xslt-process-last-selected-position-line))
	       (column (xslt-process-last-selected-position-column))
	       (action (xslt-process-last-selected-position-enter/exit?))
	       (glyph (if (eq action 'is-entering) xslt-process-enter-glyph
			(if (eq action 'is-exiting) xslt-process-exit-glyph
			  nil))))
	  (set-buffer buffer)
	  (goto-line line)
	  (if flag
	      ;; Highlight the last selected line
	      (let ((extent (xslt-process-highlight-line
			     'xslt-process-current-line-face 2))
		    (annotation
		     (if glyph (make-annotation glyph (point) 'text) nil)))
		(if annotation
		    (progn
		      (set-annotation-face annotation
					   'xslt-process-indicator-face)
		      (set-extent-priority annotation 3)))
		;; Setup the new extent and annotation in the
		;; last-selected-position
		(xslt-process-last-selected-position-extent extent)
		(xslt-process-last-selected-position-annotation annotation))
	    ;; Unhighlight the last selected line
	    (xslt-process-unhighlight-last-selected-line))))))

(defun xslt-process-highlight-breakpoint (breakpoint &optional state)
  "Highlight BREAKPOINT depending on it state."
  (let* ((filename (xslt-process-breakpoint-filename breakpoint))
	 (line (xslt-process-breakpoint-line breakpoint))
	 (buffer (xslt-process-get-file-buffer filename)))
    ;; Signal an error if there's no buffer
    (if (not buffer)
	(error "Cannot find the buffer associated with %s" filename)
      ;; If state was not passed as argument to this function, set
      ;; state to the state of the breakpoint
      (if (not state)
	  (setq state (xslt-process-breakpoint-is-enabled breakpoint)))
      ;; Position to the line we want to be highlighted and invoke the
      ;; xslt-process-highlight-line function
      (save-excursion
	(set-buffer buffer)
	(goto-line line)
	(let ((extent (xslt-process-highlight-line
		       (if (or (not (null state)) (eq state 'enabled))
			   'xslt-process-enabled-breakpoint-face
			 'xslt-process-disabled-breakpoint-face)
		       1)))
	  ;; Intern the extent in the extents table
	  (puthash breakpoint extent xslt-process-breakpoint-extents))))))
      
(defun xslt-process-unhighlight-breakpoint (breakpoint)
  "Remove the highlighting associated with BREAKPOINT."
  (save-excursion
    ;; First remove any extent that exists at this line
    (let* ((filename (xslt-process-breakpoint-filename breakpoint))
	   (line (xslt-process-breakpoint-line breakpoint))
	   (extent (gethash (cons filename line)
			    xslt-process-breakpoint-extents)))
      (if extent
	  (progn
	    (delete-extent extent)
	    (remhash (cons filename line) xslt-process-breakpoint-extents))))))

(defun xslt-process-highlight-line (face &optional priority)
  "Sets the face of the current line to FACE. Returns the extent that
highlights the line."
  (save-excursion
      ;; Don't setup a new extent if the face is 'default
      (if (eq face 'default)
	  nil
	;; Otherwise setup a new a new extent at the current line
	(let* ((to (or (end-of-line) (point)))
	       (from (or (beginning-of-line) (point)))
	       (extent (make-extent from to)))
	  (set-extent-face extent face)
	  (if priority
	      (set-extent-priority extent priority))
	  extent))))

;;;
;;; The interaction with the debugger
;;;

(defun xslt-process-send-command (string &optional dont-start-process?)
  "Sends a command to the XSLT process. Start this process if not
already started."
  ;; Reset the execution-context-error-function so that in case of
  ;; errors we don't get error functions called inadvertently
  (setq xslt-process-execution-context-error-function nil)
  (if (and (not dont-start-process?)
	   (or (null xslt-process-comint-process)
	       (not (eq (process-status xslt-process-comint-process) 'run))))
      (progn
	(xslt-process-start-debugger-process)
	;; Set any breakpoints which happen to be setup in the
	;; breakpoints hash table at this time in the XSLT debugger
	(maphash
	 (lambda (breakpoint status)
	   (let ((filename (xslt-process-breakpoint-filename breakpoint))
		 (line (xslt-process-breakpoint-line breakpoint)))
	     (comint-simple-send xslt-process-comint-process
				 (format "b %s %s" filename line))
	     (if (eq status 'disabled)
		 (comint-simple-send xslt-process-comint-process
				     (format "dis %s %s" filename line)))))
	 xslt-process-breakpoints)))
  (if (and dont-start-process?
	   (null xslt-process-comint-process))
      nil
    (if (eq (process-status xslt-process-comint-process) 'run)
	(comint-simple-send xslt-process-comint-process string))))

(defun xslt-process-start-debugger-process ()
  "*Start the XSLT debugger process."
  (setq xslt-process-comint-buffer
	(make-comint xslt-process-comint-process-name
		     "java" nil "xslt.debugger.cmdline.Controller" "-emacs"))
  (message "Starting XSLT process...")
  (setq xslt-process-comint-process
	(get-buffer-process xslt-process-comint-buffer))
  (save-excursion
    (set-buffer xslt-process-comint-buffer)
    (make-variable-buffer-local 'kill-buffer-hook)
    (add-hook 'kill-buffer-hook 'xslt-process-debugger-buffer-killed)
    ;; Set our own process filter, so we get a chance to remove Emacs
    ;; commands from the output sent to the buffer
    (set-process-filter xslt-process-comint-process
			(function xslt-process-output-from-process))
    (setq comint-prompt-regexp "^xslt> ")
    (setq comint-delimiter-argument-list '(? ))))

(defvar xslt-process-results-process-marker nil
  "Marker to indicate the current position of where text should be
inserted in the output buffer, as specified by
`xslt-process-results-buffer-name'.")

(defun xslt-process-results-process-filter (process string)
  "Function called whenever the XSLT processor sends results to its
output stream. The results come via the `xslt-process-results-process'
process."
  (let ((old-buffer (current-buffer)))
    (unwind-protect
	(let* ((buffer (get-buffer-create xslt-process-results-buffer-name))
	       moving)
	  (set-buffer buffer)
	  (add-hook 'kill-buffer-hook
		    (lambda ()
		      (setq xslt-process-results-process-marker nil)))
	  (if (null xslt-process-results-process-marker)
	      (setq xslt-process-results-process-marker
		    (point-min-marker xslt-process-results-buffer-name)))
	  (setq moving (= (point) xslt-process-results-process-marker))
	  (save-excursion
	    ;; Insert the text, moving the marker.
	    (goto-char xslt-process-results-process-marker)
	    (insert string)
	    (set-marker xslt-process-results-process-marker (point)))
	  (if moving (goto-char xslt-process-results-process-marker))
	  (switch-to-buffer buffer)))))

(defvar xslt-process-partial-command nil
  "Holds partial commands as output by the XSLT debugger.")

(defun xslt-process-output-from-process (process string)
  "This function is called each time output is generated by the XSLT
debugger. It filters out all the Emacs commands and sends the rest of
the output to the XSLT process buffer."
  (while (and string (not (equal string "")))
;    (message "String is now '%s'" string)
    (let* ((l-start (string-match "<<" string))
	   (l-end (if l-start (match-end 0) nil))
	   (g-start (string-match ">>" string))
	   (g-end (if g-start (match-end 0) nil)))
      (cond ((and l-start (null g-start))
	     ;; We have the start of a command which doesn't end in
	     ;; this current string, preceded by some output text
;	     (message "case 1: l-start %s, g-start %s" l-start g-start)
	     (let ((output (substring string 0 l-start)))
	       (if (and output (not (equal output "")))
		   (comint-output-filter process output)))
	     (setq xslt-process-partial-command (substring string l-end))
;	     (message "   xslt-process-partial-command %s"
;		      xslt-process-partial-command)
	     (setq string nil))

	    ((and (null l-start) g-start)
	     ;; We have the end of command followed followed by some
	     ;; output text
;	     (message "case 2: l-start %s, g-start %s" l-start g-start)
	     (setq xslt-process-partial-command
		   (concat xslt-process-partial-command
			   (substring string 0 g-end)))
;	     (message "   xslt-process-partial-command %s"
;		      xslt-process-partial-command)
;	     (message "evaluating xslt-process-partial-command: %s"
;		      xslt-process-partial-command)
	     (eval (read xslt-process-partial-command))
	     (setq xslt-process-partial-command nil)
	     (let ((output (substring string g-end)))
	       (if (and output (not (equal output "")))
		   (comint-output-filter process output)))
	     (setq string nil))

	    ((and (null l-start) (null g-start))
	     ;; We have some text. Append to
	     ;; `xslt-process-partial-command' if it's not null,
	     ;; otherwise just output to the process buffer.
;	     (message "case 3: l-start %s, g-start %s" l-start g-start)
	     (if xslt-process-partial-command
		 (setq xslt-process-partial-command
		       (concat xslt-process-partial-command string))
	       (comint-output-filter process string))
;	     (message "   xslt-process-partial-command %s"
;		      xslt-process-partial-command)
	     (setq string nil))

	    ((< l-start g-start)
	     ;; We have a command embedded into string. Output the
	     ;; preceding text to the process buffer, execute the
	     ;; command and set string to the substring starting at
	     ;; the end of command.
;	     (message "case 4: l-start %s, g-start %s" l-start g-start)
	     (let ((output (substring string 0 l-start))
		   (command (substring string l-end g-start)))
	       (if (and output (not (equal output "")))
		   (comint-output-filter process output))
;	       (message "evaluating command: %s" command)
	       (eval (read command))
	       (setq string (substring string g-end))))

	    ((> l-start g-start)
	     ;; We have the end of previously saved command, some
	     ;; output text and maybe another command.
;	     (message "case 5: l-start %s, g-start %s" l-start g-start)
	     (setq xslt-process-partial-command
		   (concat xslt-process-partial-command
			   (substring string 0 g-start)))
;	     (message "   xslt-process-partial-command %s"
;		      xslt-process-partial-command)
;	     (message "evaluating xslt-process-partial-command: %s"
;		      xslt-process-partial-command)
	     (eval (read xslt-process-partial-command))
	     (setq xslt-process-partial-command nil)
	     (let ((output (substring string g-end l-start)))
	       (if (and output (not (equal output "")))
		   (comint-output-filter process output)))
	     (setq string (substring string l-start)))))))

(defun xslt-process-unhighlight-last-selected-line ()
  "Unselect the last selected line."
  ;; Unselect the last line showing the debugger's position
  (if xslt-process-last-selected-position
      (let ((extent (xslt-process-last-selected-position-extent))
	    (annotation (xslt-process-last-selected-position-annotation)))
	(if extent (delete-extent extent))
	(if annotation (delete-annotation annotation))
	;; Remove extent and annotation from the
	;; last-selected-position. Need to use aset as there is no way
	;; for the setter functions to detect between programmer
	;; passed nil and no argument.
	(aset xslt-process-last-selected-position 3 nil)
	(aset xslt-process-last-selected-position 4 nil))))

;;;
;;; Functions called as result of the XSLT processing
;;;

(defun xslt-process-processor-finished ()
  "Called by the XSLT debugger process when the XSLT processing finishes."
  (setq xslt-process-process-state 'not-running)
  (xslt-process-unhighlight-last-selected-line)
  (setq xslt-process-last-selected-position [nil nil nil nil nil nil])
  (message "XSLT processing finished."))

(defun xslt-process-report-error (message)
  "Called by the XSLT debugger process whenever an error happens."
  (message message)
  (if xslt-process-execution-context-error-function
      (funcall xslt-process-execution-context-error-function)))

(defun xslt-process-debugger-stopped-at (filename line column info)
  "Function called by the XSLT debugger process each time the debugger
hits a breakpoint that causes it to stop."
  (message "Stopped at %s %s" filename line)
  (setq xslt-process-process-state 'stopped)
  ;; Unselect the previous selected line
  (xslt-process-unhighlight-last-selected-line)
  ;; Now select the new line. Create a buffer for the file, if one
  ;; does not exist already, and put it in the debug mode.
  (let ((buffer (xslt-process-get-file-buffer filename))
	(is-entering (string-match "^entering:" info))
	(is-exiting (string-match "^leaving:" info)))
    (if (not buffer)
	(error "Cannot find the buffer associated with %s" filename)
      (progn
	(pop-to-buffer buffer)
	(goto-line line)
	;; Setup the xslt-process-last-selected-position variable so we
	;; can call the xslt-process-change-current-line-highlighting
	;; function
	(xslt-process-last-selected-position-filename filename)
	(xslt-process-last-selected-position-line line)
	(xslt-process-last-selected-position-column column)
	(xslt-process-last-selected-position-enter/exit?
	 (if is-entering 'is-entering
	   (if is-exiting 'is-exiting nil)))
	(xslt-process-change-current-line-highlighting t filename)))))

(defun xslt-process-debugger-process-started ()
  "Called when the debugger process started and is ready to accept
commands."
  (setq xslt-process-debugger-process-started t)
  (message "Starting XSLT process...done"))

(defun xslt-process-debugger-buffer-killed ()
  "Called when the comint buffer running the XSLT debugger is killed
by the user."
  (setq xslt-process-comint-process nil)
  (setq xslt-process-comint-buffer nil)
  (xslt-process-unhighlight-last-selected-line)
  (setq xslt-process-last-selected-position [nil nil nil nil nil nil])
  (setq xslt-process-process-state 'not-running))

(defun xslt-process-source-frames-stack-changed (stack)
  "Called by the debugger process to inform that the source frames
stack has changed. The STACK argument contains the new source frame
stack as a list of (name filename line)."
  (setq xslt-process-source-frames-stack stack)
  (run-hooks 'xslt-process-source-frames-changed-hooks))

(defun xslt-process-style-frames-stack-changed (stack)
  "Called by the debugger process to inform that the style frames
stack has changed. The STACK argument contains the new style frame
stack as a list of (name filename line)."
  (setq xslt-process-style-frames-stack stack)
  (run-hooks 'xslt-process-style-frames-changed-hooks))

(defun xslt-process-set-output-port (port)
  "Called by the XSLT debugger to setup the TCP/IP port number on
which it listens for incoming connections. Emacs has to connect to
this port and use it for receiving the result of the XSLT processing."
  (setq xslt-process-results-process
	(open-network-stream xslt-process-results-process-name
			     nil "localhost" port))
  (set-process-filter xslt-process-results-process
		      'xslt-process-results-process-filter))

;;;
;;; Setup the minor mode
;;;

(defun xslt-process-setup-minor-mode (keymap mode-line-string)
  "Setup the XSLT-process minor mode. KEYMAP specifies the keybindings
to be used. MODE-LINE-STRING specifies the string to be displayed in
the modeline."
  (if (fboundp 'add-minor-mode)
      (add-minor-mode 'xslt-process-mode
		      mode-line-string
		      keymap
		      nil
		      'xslt-process-mode)
    (remassoc 'xslt-process-mode minor-mode-alist)
    (or (assoc 'xslt-process-mode minor-mode-alist)
	(setq minor-mode-alist
	      (cons '(xslt-process-mode mode-line-string)
		    minor-mode-alist)))
    (remassoc 'xslt-process-mode minor-mode-map-alist)
    (or (assoc 'xslt-process-mode minor-mode-map-alist)
	(setq minor-mode-map-alist
	      (cons (cons 'xslt-process-mode keymap)
		    minor-mode-map-alist))))
  (force-mode-line-update))

;;;
;;; Additional functions
;;;

(defun xslt-process-get-file-buffer (filename)
  "Searches through all the current buffers for a buffer whose true
file name is the same as FILENAME. The true file name is the one in
which all the symlinks in the original file name were expanded. We
don't want to use `get-file-buffer' because it doesn't follow links.

If the buffer does not exists, open the file in a new buffer and
return the buffer."
  (let ((true-filename (file-truename filename))
	(buffers-list (buffer-list))
	(found nil))
    (while (and (not found) buffers-list)
      (let* ((buffer (car buffers-list))
	     (filename (buffer-file-name buffer)))
	(if (equal true-filename (if filename (file-truename filename) nil))
	    (setq found buffer)
	  (setq buffers-list (cdr buffers-list)))))
    ;; Return the buffer if found, otherwise open the file and return it
    (if found
	found
      (let ((buffer (find-file true-filename)))
	(if buffer
	    (save-excursion
	      (set-buffer buffer)
	      (xslt-process-mode 1)
	      (xslt-process-toggle-debug-mode 1)))
	buffer))))

(provide 'xslt-process)
