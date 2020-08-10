;;
;;  facts - in-memory graph database
;;  Copyright 2011,2012,2014,2015,2017-2020 Thomas de Grivel <thoxdg@gmail.com>
;;
;;  Permission to use, copy, modify, and distribute this software for any
;;  purpose with or without fee is hereby granted, provided that the above
;;  copyright notice and this permission notice appear in all copies.
;;
;;  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;;  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;;  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;;  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;;  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;;  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;;  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
;;

(in-package :facts)

;;  Transactions

(defvar *transaction* nil)
(defvar *db-path* nil)
(defvar *db-path-defaults* (make-pathname :type "facts"))
(defvar *db-log-path-defaults* (make-pathname :type "facts-log"))
(defvar *transaction-vars* nil)
(defvar *transaction-mutex* (sb-thread:make-mutex :name "transaction-mutex"))

(defun transaction-var (value name)
  (let ((cell (rassoc name *transaction-vars* :test #'eq)))
    (if cell
        (setf (car cell) value)
        (push (cons value name) *transaction-vars*))))

(defun transaction-vars ()
  *transaction-vars*)

(defstruct transaction
  (completed nil :type (member nil t))
  (log () :type list))

(defmacro log-transaction-operation (op &rest args)
  (unless (rollback-function op)
    (warn "Undefined rollback function for ~S" op))
  `(when *transaction*
     (push (list ',op ,@args)
           (transaction-log *transaction*))))

(defun db-path ()
  (and *db-path*
       (merge-pathnames *db-path* *db-path-defaults*)))

(defun db-log-path ()
  (and *db-path*
       (merge-pathnames *db-path* *db-log-path-defaults*)))

(defun commit-transaction (tx)
  (let ((path (db-log-path)))
    (when path
      (ensure-directories-exist path)
      (with-open-file (out path
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create)
        (dolist (operation (reverse (transaction-log tx)))
          (write (sublis (transaction-vars) operation)
                 :stream out
                 :readably t
                 :pretty nil)
          (fresh-line out)))))
  (setf (transaction-completed tx) t))

(defun rollback-transaction (tx)
  (dolist (operation (transaction-log tx))
    (apply #'rollback operation)))

(defmacro with-mutex ((mutex timeout) &body body)
  (let ((g!mutex (gensym "MUTEX-"))
        (g!result (gensym "RESULT-")))
    `(let ((,g!mutex ,mutex)
           ,g!result)
       (if (sb-thread:with-mutex (,g!mutex :wait-p t)
             (setf ,g!result (progn ,@body))
             t)
           ,g!result
           (error "Could not acquire ~S for ~D seconds."
                  ,g!mutex ,timeout)))))

(defmacro with-transaction (&body body)
  `(if *transaction*
       (progn ,@body)
       (with-mutex (*transaction-mutex* 1)
         (let ((*transaction* (make-transaction)))
           (unwind-protect (prog1 (progn ,@body)
                             (commit-transaction *transaction*))
             (unless (transaction-completed *transaction*)
               (rollback-transaction *transaction*)))))))
