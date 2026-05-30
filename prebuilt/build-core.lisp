;;; build-core.lisp — run by build-sbcl-core.sh

;; Bootstrap Quicklisp — search common locations
(let ((ql-init (or (probe-file (merge-pathnames "quicklisp/setup.lisp"
                                                (user-homedir-pathname)))
                   (probe-file (merge-pathnames ".quicklisp/setup.lisp"
                                                (user-homedir-pathname)))
                   (probe-file "/share2/sean/.quicklisp/setup.lisp")
                   (probe-file "/root/quicklisp/setup.lisp")
                   (when (uiop:getenv "QUICKLISP_PATH")
                     (probe-file (uiop:getenv "QUICKLISP_PATH"))))))
  (unless ql-init
    (error "Quicklisp not found. Set QUICKLISP_PATH env var to your setup.lisp"))
  (format t "~&[BUILD] Loading Quicklisp from ~A~%" ql-init)
  (load ql-init))

;; Load all dependencies
(ql:quickload '(:dexador :hunchentoot :yason :ironclad :cl-base64
                :cl-ppcre :uiop :bordeaux-threads :usocket :local-time)
              :silent nil)

(format t "~&[BUILD] All dependencies loaded~%")

;; Load the MCP server — strip the trailing (main) call so we control startup
(let ((src (uiop:read-file-string
             (or (uiop:getenv "MCP_SERVER_LISP")
                 "/share/projects/mcp-server/mcp-server.lisp"))))
  (let ((patched (cl-ppcre:regex-replace "\\(main\\)\\s*$" src "")))
    (with-input-from-string (s patched)
      (loop for form = (read s nil :eof)
            until (eq form :eof)
            do (eval form)))))

(format t "~&[BUILD] MCP server loaded~%")
(format t "~&[BUILD] Saving executable to ~A~%"
        (or (uiop:getenv "SBCL_CORE_OUTPUT") "mcp-server"))

(sb-ext:save-lisp-and-die
  (or (uiop:getenv "SBCL_CORE_OUTPUT") "mcp-server")
  :toplevel (lambda ()
              (setf *random-state* (make-random-state t))
              (main))
  :executable t
  :compression t
  :save-runtime-options t)
