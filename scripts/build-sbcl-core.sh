#!/bin/bash
# scripts/build-sbcl-core.sh
#
# Compiles the MCP server and all Quicklisp dependencies into a single
# self-contained SBCL executable. Run this on the build host before
# building the Buildroot image.
#
# Output: prebuilt/mcp-server  (executable, ~25MB)
#
# Requirements:
#   - SBCL installed on build host
#   - Quicklisp installed for the current user
#   - All Quicklisp deps loadable (dexador, hunchentoot, yason, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MCP_SERVER_LISP="/share/projects/mcp-server/mcp-server.lisp"
PREBUILT_DIR="${PROJECT_DIR}/prebuilt"
OUTPUT="${PREBUILT_DIR}/mcp-server"
BUILD_SCRIPT="${PREBUILT_DIR}/build-core.lisp"

mkdir -p "${PREBUILT_DIR}"

echo "=== Octopus: Building SBCL core ==="
echo "  Source : ${MCP_SERVER_LISP}"
echo "  Output : ${OUTPUT}"
echo ""

if [ ! -f "${MCP_SERVER_LISP}" ]; then
    echo "ERROR: mcp-server.lisp not found at ${MCP_SERVER_LISP}"
    exit 1
fi

cat > "${BUILD_SCRIPT}" << 'LISP'
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
LISP

echo "Building SBCL core (this may take a minute)..."

SBCL_CORE_OUTPUT="${OUTPUT}" \
MCP_SERVER_LISP="${MCP_SERVER_LISP}" \
sbcl --noinform \
     --disable-debugger \
     --load "${BUILD_SCRIPT}"

if [ -f "${OUTPUT}" ]; then
    chmod +x "${OUTPUT}"
    SIZE=$(du -sh "${OUTPUT}" | cut -f1)
    echo ""
    echo "=== Build successful ==="
    echo "  Output : ${OUTPUT}"
    echo "  Size   : ${SIZE}"
    cp "${PROJECT_DIR}/overlay/etc/octopus.env" \
       "${PREBUILT_DIR}/mcp-server.env.example"
else
    echo "ERROR: Build failed — output not found at ${OUTPUT}"
    exit 1
fi
