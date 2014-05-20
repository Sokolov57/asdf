(defsystem "asdf-tools"
  :description "tools to build, test, maintain and release ASDF itself"
  :depends-on ((:version "asdf" "3.1.2")
               (:version "inferior-shell" "2.0.0")
               (:version "cl-ppcre" "2.0.4")
               (:version "lisp-invocation" "1.0.2")
               (:feature :sbcl "sb-introspect"))
  :components
  ((:file "package")
   (:file "pathnames" :depends-on ("package"))
   (:file "git" :depends-on ("package"))
   (:file "build" :depends-on ("pathnames"))
   (:file "version" :depends-on ("pathnames"))
   (:file "invoke-lisp" :depends-on ("package"))
   (:file "test-environment" :depends-on ("pathnames" "invoke-lisp"))
   (:file "test-basic" :depends-on ("test-environment"))
   (:file "test-scripts" :depends-on ("test-environment"))
   (:file "test-upgrade" :depends-on ("test-environment" "git"))
   (:file "test-all" :depends-on ("test-environment"))
   (:file "release" :depends-on ("version" "test-environment"))
   (:file "main" :depends-on ("package"))))
