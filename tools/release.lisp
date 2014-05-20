(in-package :asdf-tools)

;;; Getting a list of source files in a system

(defun enough-namestring! (base pathname)
  (let ((e (enough-namestring base pathname)))
    (assert (relative-pathname-p e))
    e))

(defun enough-namestrings (base pathnames)
  (loop :with b = (ensure-pathname base :want-absolute t :want-directory t)
        :for p :in pathnames
        :collect (enough-namestring! p b)))

(defun system-source-files (system &key monolithic)
  (let* ((sys (find-system system))
         (components
           (required-components system
                                :other-systems monolithic
                                :goal-operation 'load-op
                                :keep-operation 'load-op
                                :keep-component 'file-component))
         (dir (ensure-pathname
               (system-source-directory sys)
               :want-absolute t :want-directory t))
         (pathnames (mapcar 'component-pathname components)))
    (enough-namestrings dir pathnames)))


;;; Making release tarballs for asdf, asdf/defsystem, uiop.

(defun tarname (name) (strcat name ".tar.gz"))

(defun make-tarball-under-build (name base files)
  (check-type name string)
  (ensure-pathname base :want-absolute t :want-existing t :want-directory t)
  (dolist (f files)
    (check-type f string))
  (let* ((base
           (ensure-pathname
            base
            :want-absolute t :want-directory t
            :want-existing t :truename t))
         (destination
           (ensure-pathname
            name
            :defaults (pn "build/")
            :want-relative t :ensure-absolute t
            :ensure-subpath t :ensure-directory t))
         (tarball
           (ensure-pathname
            (tarname name)
            :defaults (pn "build/")
            :want-relative t :ensure-absolute t
            :ensure-subpath t :want-file t
            :ensure-directories-exist t)))
    (assert (< 6 (length (pathname-directory destination))))
    (when (probe-file* destination)
      (error "Destination ~S already exists, not taking chances - you can delete it yourself."
             destination))
    (ensure-directories-exist destination)
    (run `(cp "-pHux" --parents ,@files ,destination) :directory base :show t)
    (run `(tar "zcfC" ,tarball ,(pn "build/") (,name /)) :show t)
    (delete-directory-tree destination :validate (lambda (x) (equal x destination)))
    (values)))

(defun driver-files ()
  (list* "README" "uiop.asd" "asdf-driver.asd" (system-source-files :uiop)))
(defun driver-name ()
  (format nil "uiop-~A" *version*))
(defun make-driver-tarball ()
  (make-tarball-under-build (driver-name) (pn "uiop/") (driver-files)))

(defun asdf-defsystem-files ()
  (list* "asdf.asd" "build/asdf.lisp" "version.lisp-expr" "header.lisp"
         (system-source-files :asdf/defsystem)))
(defun asdf-defsystem-name ()
  (format nil "asdf-defsystem-~A" *version*))
(defun make-asdf-defsystem-tarball ()
  (build-asdf)
  (make-tarball-under-build (asdf-defsystem-name) (pn) (asdf-defsystem-files)))

(defun asdf-git-name ()
  (strcat "asdf-" *version*))

(defun make-git-tarball ()
  (build-asdf)
  (with-asdf-dir ()
    (run `(tar zcf ("build/" ,(asdf-git-name) ".tar.gz") build/asdf.lisp ,@(run/lines '(git ls-files))
               (asdf-git-name)) :show t))
  t)

(defun asdf-lisp-name ()
  (format nil "asdf-~A.lisp" *version*))

(defun make-asdf-lisp ()
  (build-asdf)
  (concatenate-files (list (pn "build/asdf.lisp"))
                     (pn "build/" (asdf-lisp-name))))

(defun make-archive ()
  (make-driver-tarball)
  (make-asdf-defsystem-tarball)
  (make-git-tarball)
  (make-asdf-lisp)
  t)


;;; Publishing tarballs onto the public repository

(defvar *clnet* "common-lisp.net")
(defvar *clnet-asdf-public* "/project/asdf/public_html/")
(defun public-path (x) (strcat *clnet-asdf-public* x))

(defun publish-archive ()
  (let ((tarballs (mapcar 'tarname (list (driver-name) (asdf-defsystem-name) (asdf-git-name)))))
    (run `(rsync ,@tarballs ,(asdf-lisp-name) (,*clnet* ":" ,(public-path "archives/")))
         :show t :directory (pn "build/")))
  (format t "~&To download the tarballs, point your browser at:~%
        http://common-lisp.net/project/asdf/archives/
~%")
  t)

(defun link-archive ()
  (run (format nil "ln -sf ~S ~S ; ln -sf ~S ~S ; ln -sf ~S ~S ; ln -sf ~S ~S"
               (tarname (driver-name))
               (public-path "archives/uiop.tar.gz")
               (tarname (asdf-defsystem-name))
               (public-path "archives/asdf-defsystem.tar.gz")
               (tarname (asdf-git-name))
               (public-path "archives/asdf.tar.gz")
               (asdf-lisp-name)
               (public-path "archives/asdf.lisp"))
       :show t :host *clnet*)
  t)

(defun make-and-publish-archive ()
  (make-archive)
  (publish-archive)
  (link-archive))

(defun archive () "alias for make-and-publish-archive" (make-and-publish-archive))
(defun install () "alias for make-and-publish-archive" (make-and-publish-archive))


;;; Making a debian package
(defun debian-package (&optional (release "release"))
  (let* ((debian-version (debian-version-from-file release))
         (version (version-from-file release)))
    (unless (equal version (parse-debian-version debian-version))
      (error "Debian version ~A doesn't match asdf version ~A" debian-version version))
    (clean)
    (format t "building package version ~A~%" (debian-version-from-file))
    (run `(git-buildpackage
           ;; --git-ignore-new ;; for testing purpose
           (--git-debian-branch= ,release)
           (--git-upstream-tag="%(version)s")
           ;;--git-upstream-tree=tag ;; if the changelog says 3.1.2, looks at that tag
           ;;(--git-upstream-branch= ,version) ;; if the changelog says 3.1.2, looks at that tag
           --git-tag --git-retag
           ;; --git-no-pristine-tar
           --git-force-create
           --git-ignore-branch)
         :directory (pn) :show t)))

(defun debian-architecture ()
  (run/ss `(dpkg --print-architecture)))

(defun publish-debian-package (&optional release)
  (let ((changes (strcat "cl-asdf_" (debian-version-from-file release)
                         "_" (debian-architecture) ".changes")))
    (run* `(dput mentors ,(pn "../" changes)))))

(deftestcmd release (new-version lisps scripts systems)
  "Release the code (not implemented)"
  (break) ;; for each function, offer to do it or not (?)
  (with-asdf-dir ()
    (let ((log (newlogfile "release" "all"))
          (releasep (= (length (parse-version new-version)) 3)))
      (when releasep
        (let ((debian-version (debian-version-from-file)))
          (unless (equal new-version (parse-debian-version debian-version))
            (error "You're trying to release version ~A but the debian/changelog wasn't properly updated"
                   new-version)))
        (when (nth-value 1 (run '(parse-changelog debian/changelog) :output nil :error-output :lines))
          (error "Malformed debian/changelog entry")))
      (and ;; need a better combinator, that tells us about progress, etc.
       (git-all-committed-p)
       (test-all-no-stop) ;; NEED ARGUMENTS!
       (test-load-systems lisps systems)
       (bump new-version)
       (when releasep
         (and
          (debian-package)
          (publish-debian-package)
          (merge-master-into-release)))
       ;; SUCCESS! now publish more widely
       (%push)
       (archive)
       (website)
       (when releasep
         (log! log t "Don't forget to send a debian mentors request!"))
       (log! log "Don't forget to send announcement to asdf-announce, asdf-devel, etc.")
       (log! log "Don't forget to move all fixed bugs from Fix Committed -> Fix Released on launchpad")))))
