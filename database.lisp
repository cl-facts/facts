;;
;;  lowh-facts  -  facts database
;;
;;  Copyright 2011,2012 Thomas de Grivel <billitch@gmail.com>
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

(in-package :lowh-facts)

;;  Database

(defstruct db
  (index-spo (llrbtree:make-tree :lessp #'fact-spo-lessp))
  (index-pos (llrbtree:make-tree :lessp #'fact-pos-lessp))
  (index-osp (llrbtree:make-tree :lessp #'fact-osp-lessp)))

(defun db-fact (db fact)
  (index-get (db-index-spo db) fact))

;;  Database operations on indexes

(defun db-indexes-insert (db fact)
  (with-rollback*
    (index-insert (db-index-spo db) fact)
    (index-insert (db-index-pos db) fact)
    (index-insert (db-index-osp db) fact)))

(defun db-indexes-delete (db fact)
  (with-rollback*
    (index-delete (db-index-spo db) fact)
    (index-delete (db-index-pos db) fact)
    (index-delete (db-index-osp db) fact)))

(setf (rollback-function 'db-indexes-insert) 'db-indexes-delete)
(setf (rollback-function 'db-indexes-delete) 'db-indexes-insert)

;;  High level database operations

(defvar *db* (make-db))

(defun clear-package (package)
  (let ((pkg (typecase package
	       (package package)
	       (t (find-package package)))))
    (do-symbols (sym pkg)
      (unintern sym pkg))))

(defun clear ()
  (setf *db* (make-db))
  (clear-package :lowh-facts.anon))

(defun db-get (s p o &optional (db *db*))
  (db-fact db (make-fact/v s p o)))

(defun db-insert (subject predicate object &optional (db *db*))
  (let ((fact (make-fact/v subject predicate object)))
    (or (db-fact db fact)
	(db-indexes-insert db fact))))

(defun db-delete (fact &optional (db *db*))
  (let ((fact (db-fact db fact)))
    (when fact
      (db-indexes-delete db fact))))

(defmacro db-map ((var-s var-p var-o) (tree &key start end) &body body)
  (let ((g!fact (gensym "FACT-"))
	(g!value (gensym "VALUE-")))
    `(llrbtree:map-tree (lambda (,g!fact ,g!value)
			  (declare (ignore ,g!value))
			  (let ((,var-s (fact/v-subject   ,g!fact))
				(,var-p (fact/v-predicate ,g!fact))
				(,var-o (fact/v-object    ,g!fact)))
			    ,@body))
			(,tree *db*)
			,@(when start `(:start ,start))
			,@(when end   `(:end ,end)))))
