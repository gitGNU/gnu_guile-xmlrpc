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
  #:use-module (sxml simple)
  #:use-module (sxml xpath)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:export (sxmlrpc->scm

            sxmlrpc-request-method
            sxmlrpc-request-params

            xml->sxmlrpc-request
            sxml->sxmlrpc-request))

(define (sxmlrpc-request-method request)
  (assq-ref request 'method))

(define (sxmlrpc-request-params request)
  (assq-ref request 'params))

(define (sxmlrpc->scm x)
  (define (native-type t)
    (let-values (((type value) (car+cdr t)))
      (case type
        ((i4) (if (null? value) 0 (string->number (car value))))
        ((int) (if (null? value) 0 (string->number (car value))))
        ((double) (if (null? value) 0.0 (string->number (car value))))
        ((string) (if (null? value) "" (car value)))
        ((base64) (if (null? value) "" (car value)))
        ((boolean) (if (null? value)
                       #f
                       (not (zero? (string->number (car value))))))
        ((dateTime.iso8601) (if (null? value)
                                (current-date)
                                (string->date (car value)
                                              "~Y~m~dT~H:~M:~S")))
        ((struct)
         (map
          (lambda (n v) (cons (string->symbol (second n))
                              (native-type (second v))))
          ((sxpath '(name)) value)
          ((sxpath '(value)) value)))
        ((array)
         (list->vector
          (map
           (lambda (v) (native-type (second v)))
           ((sxpath '(value)) value)))))))
  (list (cons 'method
              (string->symbol (cadar ((sxpath '(methodCall methodName)) x))))
        (cons 'params
              (map
               (lambda (v) (native-type (second v)))
               ((sxpath '(// params param value)) x)))))

(define (xmlrpc->scm str)
  (define (remove-whitespace-nodes sxml)
    (define (node-fix node)
      (cond ((symbol? node) node)
            ((string? node) (if (string-null? (string-trim node))
                                #nil
                                node))
            (else (remove-whitespace-nodes node))))
    (delete #nil (map node-fix sxml)))
  (let ((sxml (with-input-from-string str xml->sxml)))
    (sxmlrpc->scm (remove-whitespace-nodes sxml))))

;;; (xmlrpc simple) ends here
