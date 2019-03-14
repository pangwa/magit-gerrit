;;; magit-gerrit2.el --- Magit plugin for Gerrit Code Review
;;
;; Copyright (C) 2013 Brian Fransioli
;;
;; Author: Brian Fransioli <assem@terranpro.org>
;; URL: https://github.com/terranpro/magit-gerrit2
;; Package-Requires: ((magit "2.3.1"))
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see http://www.gnu.org/licenses/.

;;; Commentary:
;;
;; Magit plugin to make Gerrit code review easy-to-use from emacs and
;; without the need for a browser!
;;
;; Currently uses the [deprecated] gerrit ssh interface, which has
;; meant that obtaining the list of reviewers is not possible, only
;; the list of approvals (those who have already verified and/or code
;; reviewed).
;;
;;; To Use:
;;
;; (require 'magit-gerrit2)
;; (setq-default magit-gerrit2-ssh-creds "myid@gerrithost.org")
;;
;;
;; M-x `magit-status'
;; h R  <= magit-gerrit2 uses the R prefix, see help
;;
;;; Workflow:
;;
;; 1) *check out branch => changes => (ma)git commit*
;; 2) R P  <= [ger*R*it *P*ush for review]
;; 3) R A  <= [ger*R*it *A*dd reviewer] (by email address)
;; 4) *wait for verification/code reviews* [approvals shown in status]
;; 5) R S  <= [ger*R*it *S*ubmit review]
;;
;;; Other Comments:
;; `magit-gerrit2-ssh-creds' is buffer local, so if you work with
;; multiple Gerrit's, you can make this a file or directory local
;; variable for one particular project.
;;
;; If your git remote for gerrit is not the default "origin", then
;; `magit-gerrit2-remote' should be adjusted accordingly (e.g. "gerrit")
;;
;; Recommended to auto add reviewers via git hooks (precommit), rather
;; than manually performing 'R A' for every review.
;;
;; `magit-gerrit2' will be enabled automatically on `magit-status' if
;; the git remote repo uses the same creds found in
;; `magit-gerrit2-ssh-creds'.
;;
;; Ex:  magit-gerrit2-ssh-creds == br.fransioli@gerrit.org
;; $ cd ~/elisp; git remote -v => https://github.com/terranpro/magit-gerrit2.git
;; ^~~ `magit-gerrit2-mode' would *NOT* be enabled here
;;
;; $ cd ~/gerrit/prja; git remote -v => ssh://br.fransioli@gerrit.org/.../prja
;; ^~~ `magit-gerrit2-mode' *WOULD* be enabled here
;;
;;; Code:

(require 'magit)
(if (locate-library "magit-popup")
    (require 'magit-popup))
(require 'json)

(eval-when-compile
  (require 'cl-lib))

;; Define a defvar-local macro for Emacs < 24.3
(unless (fboundp 'defvar-local)
  (defmacro defvar-local (var val &optional docstring)
    `(progn
       (defvar ,var ,val ,docstring)
       (make-variable-buffer-local ',var))))

(defvar-local magit-gerrit2-ssh-creds nil
  "Credentials used to execute gerrit commands via ssh of the form ID@Server")

(defvar-local magit-gerrit2-remote "origin"
  "Default remote name to use for gerrit (e.g. \"origin\", \"gerrit\")")

(defcustom magit-gerrit2-popup-prefix (kbd "R")
  "Key code to open magit-gerrit2 popup"
  :group 'magit-gerrit2
  :type 'key-sequence)

(defun gerrit-command (cmd &rest args)
  (let ((gcmd (concat
	       "-x -p 29418 "
	       (or magit-gerrit2-ssh-creds
		   (error "`magit-gerrit2-ssh-creds' must be set!"))
	       " "
	       "gerrit "
	       cmd
	       " "
	       (mapconcat 'identity args " "))))
    ;; (message (format "Using cmd: %s" gcmd))
    gcmd))

(defun gerrit-query (prj &optional status)
  (gerrit-command "query"
		  "--format=JSON"
		  "--all-approvals"
		  "--comments"
		  "--current-patch-set"
		  (concat "project:" prj)
		  (concat "status:" (or status "open"))))

(defun gerrit-review ())

(defun gerrit-ssh-cmd (cmd &rest args)
  (apply #'call-process
	 "ssh" nil nil nil
	 (split-string (apply #'gerrit-command cmd args))))

(defun gerrit-review-abandon (prj rev)
  (gerrit-ssh-cmd "review" "--project" prj "--abandon" rev))

(defun gerrit-review-submit (prj rev &optional msg)
  (gerrit-ssh-cmd "review" "--project" prj "--submit"
		  (if msg msg "") rev))

(defun gerrit-code-review (prj rev score &optional msg)
  (gerrit-ssh-cmd "review" "--project" prj "--code-review" score
		  (if msg msg "") rev))

(defun gerrit-review-verify (prj rev score &optional msg)
  (gerrit-ssh-cmd "review" "--project" prj "--verified" score
		  (if msg msg "") rev))

(defun magit-gerrit2-get-remote-url ()
  (magit-git-string "ls-remote" "--get-url" magit-gerrit2-remote))

(defun magit-gerrit2-get-project ()
 (let* ((regx (rx (zero-or-one ?:) (zero-or-more (any digit)) ?/
		  (group (not (any "/")))
		  (group (one-or-more (not (any "."))))))
	(str (or (magit-gerrit2-get-remote-url) ""))
	(sstr (car (last (split-string str "//")))))
   (when (string-match regx sstr)
     (concat (match-string 1 sstr)
	     (match-string 2 sstr)))))

(defun magit-gerrit2-string-trunc (str maxlen)
  (if (> (length str) maxlen)
      (concat (substring str 0 maxlen)
	      "...")
    str))

(defun magit-gerrit2-create-branch-force (branch parent)
  "Switch 'HEAD' to new BRANCH at revision PARENT and update working tree.
Fails if working tree or staging area contain uncommitted changes.
Succeed even if branch already exist
\('git checkout -B BRANCH REVISION')."
  (cond ((run-hook-with-args-until-success
	  'magit-create-branch-hook branch parent))
	((and branch (not (string= branch "")))
	 (magit-save-repository-buffers)
	 (magit-run-git "checkout" "-B" branch parent))))


(defun magit-gerrit2-pretty-print-reviewer (name email crdone vrdone)
  (let* ((wid (1- (window-width)))
	 (crstr (propertize (if crdone (format "%+2d" (string-to-number crdone)) "  ")
			    'face '(magit-diff-lines-heading
				    bold)))
	 (vrstr (propertize (if vrdone (format "%+2d" (string-to-number vrdone)) "  ")
			    'face '(magit-diff-added-highlight
				    bold)))
	 (namestr (propertize (or name "") 'face 'magit-refname))
	 (emailstr (propertize (if email (concat "(" email ")") "")
			       'face 'change-log-name)))
    (format "%-12s%s %s" (concat crstr " " vrstr) namestr emailstr)))

(defun magit-gerrit2-pretty-print-review (num subj owner-name &optional draft)
  ;; window-width - two prevents long line arrow from being shown
  (let* ((wid (- (window-width) 2))
	 (numstr (propertize (format "%-10s" num) 'face 'magit-hash))
	 (nlen (length numstr))
	 (authmaxlen (/ wid 4))

	 (author (propertize (magit-gerrit2-string-trunc owner-name authmaxlen)
			     'face 'magit-log-author))

	 (subjmaxlen (- wid (length author) nlen 6))

	 (subjstr (propertize (magit-gerrit2-string-trunc subj subjmaxlen)
			      'face
			      (if draft
				  'magit-signature-bad
				'magit-signature-good)))
	 (authsubjpadding (make-string
			   (max 0 (- wid (+ nlen 1 (length author) (length subjstr))))
			   ? )))
    (format "%s%s%s%s\n"
	    numstr subjstr authsubjpadding author)))

(defun magit-gerrit2-wash-approval (approval)
  (let* ((approver (cdr-safe (assoc 'by approval)))
	 (approvname (cdr-safe (assoc 'name approver)))
	 (approvemail (cdr-safe (assoc 'email approver)))
	 (type (cdr-safe (assoc 'type approval)))
	 (verified (string= type "Verified"))
	 (codereview (string= type "Code-Review"))
	 (score (cdr-safe (assoc 'value approval))))

    (magit-insert-section (section approval)
      (insert (magit-gerrit2-pretty-print-reviewer approvname approvemail
						  (and codereview score)
						  (and verified score))
	      "\n"))))

(defun magit-gerrit2-wash-approvals (approvals)
  (mapc #'magit-gerrit2-wash-approval approvals))

(defun magit-gerrit2-wash-review ()
  (let* ((beg (point))
	 (jobj (json-read))
	 (end (point))
	 (num (cdr-safe (assoc 'number jobj)))
	 (subj (cdr-safe (assoc 'subject jobj)))
	 (owner (cdr-safe (assoc 'owner jobj)))
	 (owner-name (cdr-safe (assoc 'name owner)))
	 (owner-email (cdr-safe (assoc 'email owner)))
	 (patchsets (cdr-safe (assoc 'currentPatchSet jobj)))
	 ;; compare w/t since when false the value is => :json-false
	 (isdraft (eq (cdr-safe (assoc 'isDraft patchsets)) t))
	 (approvs (cdr-safe (if (listp patchsets)
				(assoc 'approvals patchsets)
			      (assoc 'approvals (aref patchsets 0))))))
    (if (and beg end)
	(delete-region beg end))
    (when (and num subj owner-name)
      (magit-insert-section (section subj)
	(insert (propertize
		 (magit-gerrit2-pretty-print-review num subj owner-name isdraft)
		 'magit-gerrit2-jobj
		 jobj))
	(unless (oref (magit-current-section) hidden)
	  (magit-gerrit2-wash-approvals approvs))
	(add-text-properties beg (point) (list 'magit-gerrit2-jobj jobj)))
      t)))

(defun magit-gerrit2-wash-reviews (&rest args)
  (magit-wash-sequence #'magit-gerrit2-wash-review))

(defun magit-gerrit2-section (section title washer &rest args)
  (let ((magit-git-executable "ssh")
	(magit-git-global-arguments nil))
    (magit-insert-section (section title)
      (magit-insert-heading title)
      (magit-git-wash washer (split-string (car args)))
      (insert "\n"))))

(defun magit-gerrit2-remote-update (&optional remote)
  nil)

(defun magit-gerrit2-review-at-point ()
  (get-text-property (point) 'magit-gerrit2-jobj))

(defsubst magit-gerrit2-process-wait ()
  (while (and magit-this-process
	      (eq (process-status magit-this-process) 'run))
    (sleep-for 0.005)))

(defun magit-gerrit2-view-patchset-diff ()
  "View the Diff for a Patchset"
  (interactive)
  (let ((jobj (magit-gerrit2-review-at-point)))
    (when jobj
      (let ((ref (cdr (assoc 'ref (assoc 'currentPatchSet jobj))))
	    (dir default-directory))
	(let* ((magit-proc (magit-fetch magit-gerrit2-remote ref)))
	  (message (format "Waiting a git fetch from %s to complete..."
			   magit-gerrit2-remote))
	  (magit-gerrit2-process-wait))
	(message (format "Generating Gerrit Patchset for refs %s dir %s" ref dir))
	(magit-diff "FETCH_HEAD~1..FETCH_HEAD")))))

(defun magit-gerrit2-download-patchset ()
  "Download a Gerrit Review Patchset"
  (interactive)
  (let ((jobj (magit-gerrit2-review-at-point)))
    (when jobj
      (let ((ref (cdr (assoc 'ref (assoc 'currentPatchSet jobj))))
	    (dir default-directory)
	    (branch (format "review/%s/%s"
			    (cdr (assoc 'username (assoc 'owner jobj)))
			    (cdr (or (assoc 'topic jobj) (assoc 'number jobj))))))
	(let* ((magit-proc (magit-fetch magit-gerrit2-remote ref)))
	  (message (format "Waiting a git fetch from %s to complete..."
			   magit-gerrit2-remote))
	  (magit-gerrit2-process-wait))
	(message (format "Checking out refs %s to %s in %s" ref branch dir))
	(magit-gerrit2-create-branch-force branch "FETCH_HEAD")))))

(defun magit-gerrit2-browse-review ()
  "Browse the Gerrit Review with a browser."
  (interactive)
  (let ((jobj (magit-gerrit2-review-at-point)))
    (if jobj
	(browse-url (cdr (assoc 'url jobj))))))

(defun magit-gerrit2-copy-review (with-commit-message)
  "Copy review url and commit message."
  (let ((jobj (magit-gerrit2-review-at-point)))
    (if jobj
      (with-temp-buffer
        (insert
         (concat (cdr (assoc 'url jobj))
                 (if with-commit-message
                     (concat " " (car (split-string (cdr (assoc 'commitMessage jobj)) "\n" t))))))
        (clipboard-kill-region (point-min) (point-max))))))

(defun magit-gerrit2-copy-review-url ()
  "Copy review url only"
  (interactive)
  (magit-gerrit2-copy-review nil))

(defun magit-gerrit2-copy-review-url-commit-message ()
  "Copy review url with commit message"
  (interactive)
  (magit-gerrit2-copy-review t))

(defun magit-insert-gerrit-reviews ()
  (magit-gerrit2-section 'gerrit-reviews
			"Reviews:" 'magit-gerrit2-wash-reviews
			(gerrit-query (magit-gerrit2-get-project))))

(defun magit-gerrit2-add-reviewer ()
  (interactive)
  "ssh -x -p 29418 user@gerrit gerrit set-reviewers --project toplvlroot/prjname --add email@addr"

  (gerrit-ssh-cmd "set-reviewers"
		  "--project" (magit-gerrit2-get-project)
		  "--add" (read-string "Reviewer Name/Email: ")
		  (cdr-safe (assoc 'id (magit-gerrit2-review-at-point)))))

(defun magit-gerrit2-popup-args (&optional something)
  (or (magit-gerrit2-arguments) (list "")))

(defun magit-gerrit2-verify-review (args)
  "Verify a Gerrit Review"
  (interactive (magit-gerrit2-popup-args))

  (let ((score (completing-read "Score: "
				    '("-2" "-1" "0" "+1" "+2")
				    nil t
				    "+1"))
	(rev (cdr-safe (assoc
		      'revision
		      (cdr-safe (assoc 'currentPatchSet
				       (magit-gerrit2-review-at-point))))))
	(prj (magit-gerrit2-get-project)))
    (gerrit-review-verify prj rev score args)
    (magit-refresh)))

(defun magit-gerrit2-code-review (args)
  "Perform a Gerrit Code Review"
  (interactive (magit-gerrit2-popup-args))
  (let ((score (completing-read "Score: "
				    '("-2" "-1" "0" "+1" "+2")
				    nil t
				    "+1"))
	(rev (cdr-safe (assoc
		      'revision
		      (cdr-safe (assoc 'currentPatchSet
				       (magit-gerrit2-review-at-point))))))
	(prj (magit-gerrit2-get-project)))
    (gerrit-code-review prj rev score args)
    (magit-refresh)))

(defun magit-gerrit2-submit-review (args)
  "Submit a Gerrit Code Review"
  ;; "ssh -x -p 29418 user@gerrit gerrit review REVISION  -- --project PRJ --submit "
  (interactive (magit-gerrit2-popup-args))
  (gerrit-ssh-cmd "review"
		  (cdr-safe (assoc
			     'revision
			     (cdr-safe (assoc 'currentPatchSet
					      (magit-gerrit2-review-at-point)))))
		  "--project"
		  (magit-gerrit2-get-project)
		  "--submit"
		  args)
  (magit-fetch-from-upstream ""))

(defun magit-gerrit2-push-review (status)
  (let* ((branch (or (magit-get-current-branch)
		     (error "Don't push a detached head.  That's gross")))
	 (commitid (or (when (eq (oref (magit-current-section) type)
				 'commit)
			 (oref (magit-current-section) value))
		       (error "Couldn't find a commit at point")))
	 (rev (magit-rev-parse (or commitid
				   (error "Select a commit for review"))))

	 (branch-remote (and branch (magit-get "branch" branch "remote"))))

    ;; (message "Args: %s "
    ;;	     (concat rev ":" branch-pub))

    (let* ((branch-merge (if (or (null branch-remote)
				 (string= branch-remote "."))
			     (completing-read
			      "Remote Branch: "
			      (let ((rbs (magit-list-remote-branch-names)))
				(mapcar
				 #'(lambda (rb)
				     (and (string-match (rx bos
							    (one-or-more (not (any "/")))
							    "/"
							    (group (one-or-more any))
							    eos)
							rb)
					  (concat "refs/heads/" (match-string 1 rb))))
				 rbs)))
			   (and branch (magit-get "branch" branch "merge"))))
	   (branch-pub (progn
			 (string-match (rx "refs/heads" (group (one-or-more any)))
				       branch-merge)
			 (format "refs/%s%s/%s" status (match-string 1 branch-merge) branch))))


      (when (or (null branch-remote)
		(string= branch-remote "."))
	(setq branch-remote magit-gerrit2-remote))

      (magit-run-git-async "push" "-v" branch-remote
			   (concat rev ":" branch-pub)))))

(defun magit-gerrit2-create-review ()
  (interactive)
  (magit-gerrit2-push-review 'publish))

(defun magit-gerrit2-create-draft ()
  (interactive)
  (magit-gerrit2-push-review 'drafts))

(defun magit-gerrit2-publish-draft ()
  (interactive)
  (let ((prj (magit-gerrit2-get-project))
	(id (cdr-safe (assoc 'id
		     (magit-gerrit2-review-at-point))))
	(rev (cdr-safe (assoc
			'revision
			(cdr-safe (assoc 'currentPatchSet
					 (magit-gerrit2-review-at-point)))))))
    (gerrit-ssh-cmd "review" "--project" prj "--publish" rev))
  (magit-refresh))

(defun magit-gerrit2-delete-draft ()
  (interactive)
  (let ((prj (magit-gerrit2-get-project))
	(id (cdr-safe (assoc 'id
		     (magit-gerrit2-review-at-point))))
	(rev (cdr-safe (assoc
			'revision
			(cdr-safe (assoc 'currentPatchSet
					 (magit-gerrit2-review-at-point)))))))
    (gerrit-ssh-cmd "review" "--project" prj "--delete" rev))
  (magit-refresh))

(defun magit-gerrit2-abandon-review ()
  (interactive)
  (let ((prj (magit-gerrit2-get-project))
	(id (cdr-safe (assoc 'id
		     (magit-gerrit2-review-at-point))))
	(rev (cdr-safe (assoc
			'revision
			(cdr-safe (assoc 'currentPatchSet
					 (magit-gerrit2-review-at-point)))))))
    ;; (message "Prj: %s Rev: %s Id: %s" prj rev id)
    (gerrit-review-abandon prj rev)
    (magit-refresh)))

(defun magit-gerrit2-read-comment (&rest args)
  (format "\'\"%s\"\'"
	  (read-from-minibuffer "Message: ")))

(defun magit-gerrit2-create-branch (branch parent))

(magit-define-popup magit-gerrit2-popup
  "Popup console for magit gerrit commands."
  'magit-gerrit2
  :actions '((?P "Push Commit For Review"                          magit-gerrit2-create-review)
	     (?W "Push Commit For Draft Review"                    magit-gerrit2-create-draft)
	     (?p "Publish Draft Patchset"                          magit-gerrit2-publish-draft)
	     (?k "Delete Draft"                                    magit-gerrit2-delete-draft)
	     (?A "Add Reviewer"                                    magit-gerrit2-add-reviewer)
	     (?V "Verify"                                          magit-gerrit2-verify-review)
	     (?C "Code Review"                                     magit-gerrit2-code-review)
	     (?d "View Patchset Diff"                              magit-gerrit2-view-patchset-diff)
	     (?D "Download Patchset"                               magit-gerrit2-download-patchset)
	     (?S "Submit Review"                                   magit-gerrit2-submit-review)
	     (?B "Abandon Review"                                  magit-gerrit2-abandon-review)
	     (?b "Browse Review"                                   magit-gerrit2-browse-review))
  :options '((?m "Comment"                      "--message "       magit-gerrit2-read-comment)))

;; Attach Magit Gerrit to Magit's default help popup
(magit-define-popup-action 'magit-dispatch-popup (string-to-char magit-gerrit2-popup-prefix) "Gerrit"
  'magit-gerrit2-popup)

;; (transient-append-suffix 'magit-dispatch "z"
;;  '("-1" "review" "--review"))

(transient-append-suffix 'magit-dispatch "z"
  '("p" "push commit for review" magit-gerrit2-create-review))


(magit-define-popup magit-gerrit2-copy-review-popup
  "Popup console for copy review to clipboard."
  'magit-gerrit2
  :actions '((?C "url and commit message" magit-gerrit2-copy-review-url-commit-message)
             (?c "url only" magit-gerrit2-copy-review-url)))

(magit-define-popup-action 'magit-gerrit2-popup ?c "Copy Review"
  'magit-gerrit2-copy-review-popup)

(defvar magit-gerrit2-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map magit-gerrit2-popup-prefix 'magit-gerrit2-popup)
    map))

(define-minor-mode magit-gerrit2-mode "Gerrit support for Magit"
  :lighter " Gerrit" :require 'magit-topgit :keymap 'magit-gerrit2-mode-map
  (or (derived-mode-p 'magit-mode)
      (error "This mode only makes sense with magit"))
  (or magit-gerrit2-ssh-creds
      (error "You *must* set `magit-gerrit2-ssh-creds' to enable magit-gerrit2-mode"))
  (or (magit-gerrit2-get-remote-url)
      (error "You *must* set `magit-gerrit2-remote' to a valid Gerrit remote"))
  (cond
   (magit-gerrit2-mode
    (magit-add-section-hook 'magit-status-sections-hook
			    'magit-insert-gerrit-reviews
			    'magit-insert-stashes t t)
    (add-hook 'magit-create-branch-command-hook
	      'magit-gerrit2-create-branch nil t)
    ;(add-hook 'magit-pull-command-hook 'magit-gerrit2-pull nil t)
    (add-hook 'magit-remote-update-command-hook
	      'magit-gerrit2-remote-update nil t)
    (add-hook 'magit-push-command-hook
	      'magit-gerrit2-push nil t))

   (t
    (remove-hook 'magit-after-insert-stashes-hook
		 'magit-insert-gerrit-reviews t)
    (remove-hook 'magit-create-branch-command-hook
		 'magit-gerrit2-create-branch t)
    ;(remove-hook 'magit-pull-command-hook 'magit-gerrit2-pull t)
    (remove-hook 'magit-remote-update-command-hook
		 'magit-gerrit2-remote-update t)
    (remove-hook 'magit-push-command-hook
		 'magit-gerrit2-push t)))
  (when (called-interactively-p 'any)
    (magit-refresh)))

(defun magit-gerrit2-detect-ssh-creds (remote-url)
  "Derive magit-gerrit2-ssh-creds from remote-url.
Assumes remote-url is a gerrit repo if scheme is ssh
and port is the default gerrit ssh port."
  (let ((url (url-generic-parse-url remote-url)))
    (when (and (string= "ssh" (url-type url))
	       (eq 29418 (url-port url)))
      (set (make-local-variable 'magit-gerrit2-ssh-creds)
	   (format "%s@%s" (url-user url) (url-host url)))
      (message "Detected magit-gerrit2-ssh-creds=%s" magit-gerrit2-ssh-creds))))

(defun magit-gerrit2-check-enable ()
  (let ((remote-url (magit-gerrit2-get-remote-url)))
    (when (and remote-url
	       (or magit-gerrit2-ssh-creds
		   (magit-gerrit2-detect-ssh-creds remote-url))
	       (string-match magit-gerrit2-ssh-creds remote-url))
      ;; update keymap with prefix incase it has changed
      (define-key magit-gerrit2-mode-map magit-gerrit2-popup-prefix 'magit-gerrit2-popup)
      (magit-gerrit2-mode t))))

;; Hack in dir-local variables that might be set for magit gerrit
(add-hook 'magit-status-mode-hook #'hack-dir-local-variables-non-file-buffer t)

;; Try to auto enable magit-gerrit2 in the magit-status buffer
(add-hook 'magit-status-mode-hook #'magit-gerrit2-check-enable t)
(add-hook 'magit-log-mode-hook #'magit-gerrit2-check-enable t)

(provide 'magit-gerrit2)

;;; magit-gerrit2.el ends here
