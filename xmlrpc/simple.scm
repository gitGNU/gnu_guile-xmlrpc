;;; (xmlrpc simple) --- Guile XMLRPC implementation.

;; Copyright (C) 2013 Aleix Conchillo Flaque <aconchillo at gmail dot com>
;;
;; This file is part of guile-xmlrpc.
;;
;; guile-xmlrpc is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3 of
;; the License, or (at your option) any later version.
;;
;; guile-xmlrpc is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 59 Temple Place - Suite 330        Fax:    +1-617-542-2652
;; Boston, MA  02111-1307,  USA       gnu@gnu.org

;;; Commentary:

;; XMLRPC module for Guile

;;; Code:

(define-module (xmlrpc simple)
  #:use-module (xmlrpc base64)
  #:use-module (rnrs bytevectors)
  #:use-module (sxml simple)
  #:use-module (sxml xpath)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:export (sxmlrpc->scm
            xmlrpc->scm
            xmlrpc-string->scm
            xmlrpc-request-method
            xmlrpc-request-params
            xmlrpc-response-params
            xmlrpc-response-fault?
            xmlrpc-response-fault-code
            xmlrpc-response-fault-message))

;;
;; sxmlrpc->scm helpers
;;

(define (sxmlrpc-array->scm sxml)
  (map
   (lambda (v) (sxmlrpc-all->scm (second v)))
   ((sxpath '(// data value)) sxml)))

(define (sxmlrpc-struct->scm sxml)
  (let ((table (make-hash-table)))
    (map
     (lambda (n v)
       (hash-set! table
                  (string->symbol (second n))
                  (sxmlrpc-all->scm (second v))))
     ((sxpath '(// member name)) sxml)
     ((sxpath '(// member value)) sxml))
    table))

(define (sxmlrpc-request->scm sxml)
  (let ((method (cadar ((sxpath '(// methodName)) sxml)))
        (params ((sxpath '(// params param value)) sxml)))
    (list (cons 'method (string->symbol method))
          (cons 'params
                (map (lambda (v) (sxmlrpc-all->scm (second v)))
                     params)))))

(define (sxmlrpc-response->scm sxml)
  (let ((params ((sxpath '(// params param value)) sxml))
        (fault ((sxpath '(// fault value struct member)) sxml)))
    (cond
     ((not (null? params))
      (list (cons 'params
                  (map (lambda (v) (sxmlrpc-all->scm (second v)))
                       params))))
     ((not (null? fault))
      (let ((faultCode (cadar ((sxpath '(name)) (car fault))))
            (faultString (cadar ((sxpath '(name)) (cdr fault)))))
        (cond
         ((and (string=? faultCode "faultCode")
               (string=? faultString "faultString"))
          (let ((code (cadar ((sxpath '(value)) (car fault))))
                (message (cadar ((sxpath '(value)) (cdr fault)))))
            (list (cons 'fault
                        (list (cons 'code (sxmlrpc-all->scm code))
                              (cons 'message (sxmlrpc-all->scm message)))))))
         (else (throw 'xmlrpc-invalid)))))
     ;; If we don't have params or fault, we hit some error.
     (else (throw 'xmlrpc-invalid)))))

(define (sxmlrpc-all->scm sxml)
  (let-values (((type value) (car+cdr sxml)))
    (case type
      ((i4 int double) (if (null? value) 0 (string->number (car value))))
      ((string) (if (null? value) "" (car value)))
      ((base64) (if (null? value) "" (utf8->string
                                      (base64-decode (car value)))))
      ((boolean) (if (null? value)
                     #f
                     (not (zero? (string->number (car value))))))
      ((dateTime.iso8601) (if (null? value)
                              (current-date)
                              (string->date (car value)
                                            "~Y~m~dT~H:~M:~S")))
      ((array) (sxmlrpc-array->scm sxml))
      ((struct) (sxmlrpc-struct->scm sxml))
      (else
       (let ((request ((sxpath '(// methodCall)) sxml))
             (response ((sxpath '(// methodResponse)) sxml)))
         (cond
          ((not (null? request)) (sxmlrpc-request->scm request))
          ((not (null? response)) (sxmlrpc-response->scm response))
          (else (throw 'xmlrpc-invalid))))))))

;;
;; Public procedures
;;

(define (xmlrpc-request-method request)
  (assq-ref request 'method))

(define (xmlrpc-request-params request)
  (assq-ref request 'params))

(define (xmlrpc-response-params response)
  (assq-ref response 'params))

(define (xmlrpc-response-fault? response)
  (if (assq-ref response 'fault) #t #f))

(define (xmlrpc-response-fault-code response)
  (assq-ref (assq-ref response 'fault) 'code))

(define (xmlrpc-response-fault-message response)
  (assq-ref (assq-ref response 'fault) 'message))

(define (sxmlrpc->scm sxml)
  (define (remove-whitespace-nodes sxml)
    (define (node-fix node)
      (cond ((symbol? node) node)
            ((string? node) (if (string-null? (string-trim node))
                                #nil
                                node))
            (else (remove-whitespace-nodes node))))
    (delete #nil (map node-fix sxml)))
  (sxmlrpc-all->scm (remove-whitespace-nodes sxml)))

(define (xmlrpc->scm port)
  (sxmlrpc->scm (xml->sxml port)))

(define (xmlrpc-string->scm str)
  (call-with-input-string str (lambda (p) (xmlrpc->scm p))))

;;; (xmlrpc simple) ends here
