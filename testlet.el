;;; testlet.el --- A language-agnostic test runner. -*- lexical-binding: t -*-

;; Copyright (C) 2025 Dominic Aschauer

;; Author: Dominic Aschauer <eldelto77@gmail.com>
;; Maintainer: Dominic Aschauer <eldelto77@gmail.com>
;; Created: 2025-07-15
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.3") (projectile "2.9.0"))
;; URL: https://github.com/eldelto/testlet
;; Keywords: convenience, programming, testing

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Testlet is a language-agnostic test-runner, aiming to provide a
;; consistent workflow across programming languages and keeping the
;; required configuration to a minimum.

;;; Code:

(require 'filenotify)
(require 'projectile)

(defun matches-in-buffer (regexp &optional buffer)
  "Returns a list of matches in the current or given buffer."
  (let ((matches) (case-fold-search nil))
    (save-match-data
      (save-excursion
        (with-current-buffer (or buffer (current-buffer))
          (save-restriction
            (widen)
            (goto-char 1)
            (while (search-forward-regexp regexp nil t 1)
              (push (match-string 0) matches)))))
      matches)))

(defun match-before-point (regexp &optional buffer)
  "Returns the first match before point in the current or given buffer."
  ;; TODO: Should also search on the current line
  (let ((case-fold-search nil))
    (save-match-data
      (save-excursion
        (with-current-buffer (or buffer (current-buffer))
          (save-restriction
            (widen)
            (if (search-backward-regexp regexp nil t 1)
				(list (match-string 0) (line-number-at-pos)))))))))

(defun testlet-list-files (regexp)
  (directory-files-recursively (projectile-project-root) regexp))


;; go-mode

(setq run-test-project-go-mode (lambda () "go test ./..."))

(setq run-test-file-go-mode
	  (lambda ()
		(let* ((test-functions (matches-in-buffer "Test[^\\(]+"))
			   (module (file-relative-name default-directory
										   (projectile-project-root))))
		  (concat
		   "go test ./"
		   module
		   " -run '("
		   (mapconcat 'identity test-functions "|")
		   ")'"))))

(setq run-test-at-point-go-mode
	  (lambda ()
		(when-let* ((test-function (car (match-before-point "Test[^\\(]+")))
					(module (file-relative-name default-directory
												(projectile-project-root))))
		  (concat
		   "go test ./"
		   module
		   " -run '("
		   test-function
		   ")'"))))

(setq watch-test-files-go-mode (lambda () (testlet-list-files ".*\\.go$")))


;; elixir-mode

(setq run-test-project-elixir-mode (lambda () "mix test"))

(setq run-test-file-elixir-mode
	  (lambda () (concat "mix test " (buffer-file-name (current-buffer)))))

(setq run-test-at-point-elixir-mode
	  (lambda () (when-let* ((file-name (buffer-file-name (current-buffer)))
							 (line-number
							  (nth 1 (match-before-point "test\s\".*\"\sdo"))))
				   (concat "mix test " file-name
						   ":" (number-to-string line-number)))))

;; TODO: Only search in <project>/(lib|test) otherwise there are too
;; many files returned.
(setq watch-test-files-elixir-mode (lambda ()
									 (testlet-list-files ".*\\.\\(ex\\|exs\\)$")))


(defun testlet-get-mode-func (prefix)
  (if-let* ((symbol (intern (concat prefix (symbol-name major-mode))))
			(bound (boundp symbol))
			(func (symbol-value symbol))
			(functionp func))
	  func
	(progn
	  (message (concat
				"no test command configured for major-mode "
				(symbol-name major-mode)))
	  nil)))

(defun testlet-register-file-watchers (files func)
  (with-current-buffer "*testlet*"
	(dolist (file files)
	  (push (file-notify-add-watch file '(change)
								   (lambda (event)
									 (if (eq 'changed (nth 1 event))
										 (funcall func))))
			file-watchers))))

(defun testlet-remove-file-watchers ()
  (when (get-buffer "*testlet*")
	  (with-current-buffer "*testlet*"
		(dolist (watcher file-watchers)
		  (file-notify-rm-watch watcher)))))

(defun testlet-run-test (prefix)
  "Resolves the variable <prefix> + <major-mode-name> and runs the
stored value as shell command in the project root."
  (if-let* ((command-func (testlet-get-mode-func prefix))
			(command (funcall command-func))
			(full-command (concat "cd " (projectile-project-root) " && " command))
			(test-func (lambda () 
						 (async-shell-command full-command
											  "*testlet*"
											  "*testlet*"))))
	  
	  (progn
		(funcall test-func)
		(with-current-buffer "*testlet*"
		  (testlet-mode)
		  (setq last-test-command test-func)))
	
	(message "no test found")))

(defun testlet-watch-test (prefix)
  (testlet-remove-file-watchers)
  (testlet-run-test prefix)
  (if-let* ((files-func (testlet-get-mode-func "watch-test-files-"))
			(files (funcall files-func)))
	  (testlet-register-file-watchers files 'testlet-rerun-test)))

;;;###autoload
(defun testlet-run-test-project ()
  "Tests the current project."
  (interactive)
  (testlet-remove-file-watchers)
  (testlet-run-test "run-test-project-"))

;;;###autoload
(defun testlet-run-test-file ()
  "Runs the tests in the current file."
  (interactive)
  (testlet-remove-file-watchers)
  (testlet-run-test "run-test-file-"))

;;;###autoload
(defun testlet-run-test-at-point ()
  "Runs the test at point."
  (interactive)
  (testlet-remove-file-watchers)
  (testlet-run-test "run-test-at-point-"))

;;;###autoload
(defun testlet-watch-test-project ()
  "Tests the current project on file change."
  (interactive)
  (testlet-watch-test "run-test-project-"))

;;;###autoload
(defun testlet-watch-test-file ()
  "Runs the tests in the current file on file change."
  (interactive)
  (testlet-watch-test "run-test-file-"))

;;;###autoload
(defun testlet-watch-test-at-point ()
  "Runs the test at point on file change."
  (interactive)
  (testlet-watch-test "run-test-at-point-"))

;;;###autoload
(defun testlet-rerun-test ()
  (interactive)
  (with-current-buffer "*testlet*"
	(let ((test-func last-test-command)
		  (watchers file-watchers))
	  (if test-func
		  (progn
			(funcall test-func)
			(testlet-mode)
			(setq last-test-command test-func)
			(setq file-watchers watchers))

		(message "no previous test command saved")))))

(defvar-keymap testlet-mode-map
  "g" #'testlet-rerun-test
  "q" #'kill-current-buffer)

;;;###autoload
(define-derived-mode testlet-mode
  shell-mode "Testlet"
  "Major mode for running tests.

  \\{testlet-mode-map}"

  (defvar-local last-test-command nil)
  (defvar-local file-watchers '())

  (add-hook 'kill-buffer-hook 'testlet-remove-file-watchers nil t))

(provide 'testlet)
;;; testlet.el ends here
