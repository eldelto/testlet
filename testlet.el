;;; testlet.el --- A language-agnostic test runner. -*- lexical-binding: t -*-

;; Copyright (C) 2025 Dominic Aschauer

;; Author: Dominic Aschauer <eldelto77@gmail.com>
;; Maintainer: Dominic Aschauer <eldelto77@gmail.com>
;; Created: 2025-07-15
;; Version: 0.2.0
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

(defvar testlet--buffer-under-test nil)
(defvar testlet--last-test-command nil)
(defvar testlet--watching? nil)
(defvar testlet--project-root nil)

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

(setq watch-test-files-go-mode '("go"))


;; elixir-ts-mode

(setq run-test-project-elixir-ts-mode (lambda () "mix test"))

(setq run-test-file-elixir-ts-mode
	  (lambda () (concat "mix test " (buffer-file-name (current-buffer)))))

(setq run-test-at-point-elixir-ts-mode
	  (lambda () (when-let* ((file-name (buffer-file-name (current-buffer)))
							 (line-number
							  (nth 1 (match-before-point "test\s\".*\".*do$"))))
				   (concat "mix test " file-name
						   ":" (number-to-string line-number)))))

(setq watch-test-files-elixir-ts-mode '("ex" "exs"))


(defun testlet--get-mode-var (prefix)
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

(defun testlet-run-test (prefix)
  "Resolves the variable <prefix> + <major-mode-name> and runs the
stored value as shell command in the project root."
  (if-let* ((command-func (testlet--get-mode-var prefix))
			(command (funcall command-func))
			(full-command (concat "cd " (projectile-project-root) " && " command))
			(test-func (lambda ()
						 (async-shell-command full-command "*testlet*" "*testlet*"))))

	  (progn
		(setq testlet--buffer-under-test (current-buffer))
		(setq testlet--last-test-command test-func)
		(setq testlet--project-root (projectile-project-root))
		(testlet-stop-watching)
		(funcall test-func)
		(with-current-buffer "*testlet*" (testlet-mode)))

	(message "no test found")))

(defun testlet-watch-test (prefix)
  (testlet-run-test prefix)
  (setq testlet--watching? 't))

(defun testlet--relevant-file? ()
  (when-let* ((saved-file-name (buffer-file-name))
			  (saved-extension (file-name-extension saved-file-name))
			  (extension-list (testlet--get-mode-var "watch-test-files-")))
	(member saved-extension extension-list)))

(defun testlet--file-watch-hook ()
  (when (and testlet--watching? (testlet--relevant-file?))
	(testlet-rerun-test)))

;;;###autoload
(defun testlet-run-test-project ()
  "Tests the current project."
  (interactive)
  (testlet-run-test "run-test-project-"))

;;;###autoload
(defun testlet-run-test-file ()
  "Runs the tests in the current file."
  (interactive)
  (testlet-run-test "run-test-file-"))

;;;###autoload
(defun testlet-run-test-at-point ()
  "Runs the test at point."
  (interactive)
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
  (if testlet--last-test-command
	  (progn
		(funcall testlet--last-test-command)
		(with-current-buffer "*testlet*" (testlet-mode)))

	(message "no previous test command saved")))

;;;###autoload
(defun testlet-stop-watching ()
  (interactive)
  (setq testlet--watching? nil))

;;;###autoload
(defun testlet-switch-to-buffer-under-test ()
  (interactive)
  (if testlet--buffer-under-test
	  (switch-to-buffer testlet--buffer-under-test)
	(message "no test buffer saved")))

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

  (add-hook 'kill-buffer-hook 'testlet-stop-watching nil t)
  (add-hook 'after-save-hook 'testlet--file-watch-hook))

(provide 'testlet)
;;; testlet.el ends here
