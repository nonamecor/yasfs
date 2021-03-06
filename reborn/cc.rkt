#lang racket            

;;-----------------------compiler---------------------------
(define meaning
  (lambda (e r tail?)
    (if (atom? e)
        (if (symbol? e) (meaning-reference e r tail?)
            (meaning-quotation e r tail?))
        (let ((syntax (car e)))
          (cond
            ((eq? syntax 'quote)  (meaning-quotation (cadr e) r tail?))
            ((eq? syntax 'lambda) (meaning-abstraction (cadr e) (cddr e) r tail?))
            ((eq? syntax 'if)     (meaning-alternative (cadr e) (caddr e) (cadddr e) r tail?))
            ((eq? syntax 'begin)  (meaning-sequence (cdr e) r tail?))
            ((eq? syntax 'set!)   (meaning-assignment (cadr e) (caddr e) r tail?))
            ((eq? syntax 'define) (meaning-define (cadr e) (caddr e) r tail?))
            ((eq? syntax 'let)    (meaning (rewrite-let (cdr e)) r tail?))
            ((eq? syntax 'let*)   (meaning (rewrite-let* (reverse (cadr e)) (caddr e)) r tail?))
            ((eq? syntax 'cond)   (meaning (rewrite-cond (cdr e)) r tail?))
            (else     (meaning-application syntax (cdr e) r tail?)))))))

(define meaning-reference
  (lambda (n r tail?)
    (let ((kind (compute-kind r n)))
      (if kind
          (cond
            ((eq? (car kind) 'local)
             (let ((i (cadr kind))
                   (j (cddr kind)) )
               (if (= i 0)
                   (SHALLOW-ARGUMENT-REF j)
                   (DEEP-ARGUMENT-REF i j) ) ) )
            ((eq? (car kind) 'global)
             (let ((i (cdr kind)))
               (CHECKED-GLOBAL-REF i) ) )
            ((eq? (car kind) 'predefined)
             (let ((i (cdr kind)))
               (PREDEFINED i) ) ) )
          (CHECKED-GLOBAL-REF (adjoint n))))))

(define meaning-quotation
  (lambda (v r tail?)
    (CONSTANT v)))

(define meaning-alternative
  (lambda (e1 e2 e3 r tail?)
    (let ((m1 (meaning e1 r #f))
          (m2 (meaning e2 r tail?))
          (m3 (meaning e3 r tail?)))
      (ALTERNATIVE m1 m2 m3))))

(define meaning-assignment
  (lambda (n e r tail?)
    (let ((m (meaning e r #f))
          (kind (compute-kind r n)))
      (if kind
          (cond
            ((eq? (car kind) 'local)
             (let ((i (cadr kind))
                   (j (cddr kind)) )
               (if (= i 0)
                   (SHALLOW-ARGUMENT-SET! j m)
                   (DEEP-ARGUMENT-SET! i j m))))
            ((eq? (car kind) 'global)
             (let ((i (cdr kind)))
               (GLOBAL-SET! i m)))
            ((eq? (car kind) 'predefined)
             (static-wrong "Immutable predefined variable" n)))
          (static-wrong "No such variable" n)))))

(define meaning-define
  (lambda (n e r tail?)
    (if (global-variable? g.current n)
        (if (memq n *defined*)
            (begin
              (set! *defined* (filter (lambda (v) (not (eq? v n))) *defined*))
              (meaning-assignment n e r tail?))
            (static-wrong "Cannot redefine variable" n))
        (begin (g.current-extend! n)
               (meaning-assignment n e r tail?)))))

(define meaning-sequence
  (lambda (e+ r tail?)
    (if (pair? e+)
        (if (pair? (cdr e+))
            (meaning*-multiple-sequence (car e+) (cdr e+) r tail?)
            (meaning*-single-sequence (car e+) r tail?))
        (static-wrong "Illegal syntax: (begin)"))))

(define meaning*-single-sequence
  (lambda (e r tail?) 
    (meaning e r tail?)))

(define meaning*-multiple-sequence
  (lambda (e e+ r tail?)
    ((lambda (m1 m+)
       (SEQUENCE m1 m+))
     (meaning e r #f)
     (meaning-sequence e+ r tail?))))

(define meaning-abstraction
  (lambda (nn* e+ r tail?)
    (let parse ((n* nn*)
                (regular '()))
      (cond
        ((pair? n*) (parse (cdr n*) (cons (car n*) regular)))
        ((null? n*) (meaning-fix-abstraction nn* e+ r tail?))
        (else       (meaning-dotted-abstraction 
                     (reverse regular) n* e+ r tail?))))))

(define meaning-fix-abstraction
  (lambda (n* e+ r tail?)
    (let* ((arity (length n*))
           (r2 (r-extend* r n*))
           (m+ (meaning-sequence e+ r2 #t)))
      (FIX-CLOSURE m+ arity))))

(define meaning-dotted-abstraction
  (lambda (n* n e+ r tail?)
    (let* ((arity (length n*))
           (r2 (r-extend* r (append n* (list n))))
           (m+ (meaning-sequence e+ r2 #t)))
      (NARY-CLOSURE m+ arity))))

(define meaning-application
  (lambda (e e* r tail?)
    (cond ((and (symbol? e)
                (let ((kind (compute-kind r e)))
                  (and (pair? kind)
                       (eq? 'predefined (car kind))
                       (let ((desc (get-description e)))
                         (and desc
                              (eq? 'function (car desc))
                              (or (= (caddr desc) (length e*))
                                  (static-wrong 
                                   "Incorrect arity for primitive" e )))))))
           (meaning-primitive-application e e* r tail?))
          ((and (pair? e)
                (eq? 'lambda (car e)) )
           (meaning-closed-application e e* r tail?) )
          (else (meaning-regular-application e e* r tail?)))))

;;; Parse the variable list to check the arity and detect wether the
;;; abstraction is dotted or not.
(define meaning-closed-application
  (lambda (e ee* r tail?)
    (let ((nn* (cadr e)))
      (let parse ((n* nn*)
                  (e* ee*)
                  (regular '()) )
        (cond
          ((pair? n*) 
           (if (pair? e*)
               (parse (cdr n*) (cdr e*) (cons (car n*) regular))
               (static-wrong "Too less arguments" e)))
          ((null? n*)
           (if (null? e*)
               (meaning-fix-closed-application 
                nn* (cddr e) ee* r tail? )
               (static-wrong "Too much arguments" e ee*) ) )
          (else (meaning-dotted-closed-application 
                 (reverse regular) n* (cddr e) ee* r tail? )))))))

(define meaning-fix-closed-application
  (lambda (n* body e* r tail?)
    (let* ((m* (meaning* e* r (length e*) #f))
           (r2 (r-extend* r n*))
           (m+ (meaning-sequence body r2 tail?)))
      (if tail? (TR-FIX-LET m* m+) 
          (FIX-LET m* m+)))))

(define meaning-dotted-closed-application
  (lambda (n* n body e* r tail?)
    (let* ((m* (meaning-dotted* e* r (length e*) (length n*) #f))
           (r2 (r-extend* r (append n* (list n))))
           (m+ (meaning-sequence body r2 tail?)) )
      (if tail? (TR-FIX-LET m* m+)
          (FIX-LET m* m+)))))

;;; Handles a call to a predefined primitive. The arity is already checked.
;;; The optimization is to avoid the allocation of the activation frame.
;;; These primitives never change the *env* register nor have control effect.
(define meaning-primitive-application
  (lambda (e e* r tail?)
    (let* ((desc (get-description e))
           ;; desc = (function address . variables-list)
           (address (cadr desc))
           (size (length e*)) )
      (cond
        ((eq? size 0) (CALL0 address))
        ((eq? size 1)
         (let ((m1 (meaning (car e*) r #f)))
           (CALL1 address m1) ) )
        ((eq? size 2)
         (let ((m1 (meaning (car e*) r #f))
               (m2 (meaning (cadr e*) r #f)) )
           (CALL2 address m1 m2) ) )
        ((eq? size 3)
         (let ((m1 (meaning (car e*) r #f))
               (m2 (meaning (cadr e*) r #f))
               (m3 (meaning (caddr e*) r #f)) )
           (CALL3 address m1 m2 m3) ) )
        (else (meaning-regular-application e e* r tail?))))))

(define meaning-regular-application
  (lambda (e e* r tail?)
    (let* ((m (meaning e r #f))
           (m* (meaning* e* r (length e*) #f)) )
      (if tail? (TR-REGULAR-CALL m m*) (REGULAR-CALL m m*)))))

(define meaning* 
  (lambda (e* r size tail?)
    (if (pair? e*)
        (meaning-some-arguments (car e*) (cdr e*) r size tail?)
        (meaning-no-argument r size tail?))))

(define meaning-dotted*
  (lambda (e* r size arity tail?)
    (if (pair? e*)
        (meaning-some-dotted-arguments (car e*) (cdr e*) 
                                       r size arity tail? )
        (meaning-no-dotted-argument r size arity tail?) ) ))

(define meaning-some-arguments
  (lambda (e e* r size tail?)
    (let ((m (meaning e r #f))
          (m* (meaning* e* r size tail?))
          (rank (- size (+ (length e*) 1))) )
      (STORE-ARGUMENT m m* rank))))

(define meaning-some-dotted-arguments
  (lambda (e e* r size arity tail?)
    (let ((m (meaning e r #f))
          (m* (meaning-dotted* e* r size arity tail?))
          (rank (- size (+ (length e*) 1))) )
      (if (< rank arity) (STORE-ARGUMENT m m* rank)
          (CONS-ARGUMENT m m* arity)))))

(define meaning-no-argument
  (lambda (r size tail?)
    (ALLOCATE-FRAME size)))

(define meaning-no-dotted-argument
  (lambda (r size arity tail?)
    (ALLOCATE-DOTTED-FRAME arity)))
;;;-------------------------------------------------------------

;;;------------------------utility-----------------------------------
(define atom?
  (lambda (v)
    (not (pair? v))))

(define list
  (lambda (a . b)
    (cons a b)))

(define myappend1
  (lambda (a b)
    (if (null? a)
        b
        (cons (car a) (myappend1 (cdr a) b)))))

(define myappend2
  (lambda (a b)
    (cond
      ((null? b) a)
      ((null? (cdr b)) 
       (myappend1 a (car b)))
      (else
       (myappend1 a (myappend2 (car b) (cdr b)))))))

(define append
  (lambda (a . b)
    (myappend2 a b)))

(define length
  (lambda (ls)
    (if (null? ls)
        0
        (+ 1 (length (cdr ls))))))

(define filter
  (lambda (fn ls)
    (if (null? ls)
        '()
        (let ((v (car ls)))
          (if (fn v)
              (cons v (filter fn (cdr ls)))
              (filter fn (cdr ls)))))))

(define map
  (lambda (fn ls)
    (if (null? ls)
        '()
        (cons 
         (fn (car ls)) 
         (map fn (cdr ls))))))

(define memq
  (lambda (s ls)
    (cond
      ((null? ls) #f)
      ((eq? (car ls) s) ls)
      (else
       (memq s (cdr ls))))))

#|
(define assq
  (lambda (s ls)
    (cond
      ((null? ls) #f)
      ((eq? (caar ls) s) ls)
      (else
       (assq s (cdr ls))))))
|#

(define cddr (lambda (ls) (cdr (cdr ls))))
(define caar (lambda (ls) (car (car ls))))
(define caddr (lambda (ls) (car (cdr (cdr ls)))))
(define cadr (lambda (ls) (car (cdr ls))))
(define cadar (lambda (ls) (car (cdr (car ls)))))

(define reverse2
  (lambda (ls ret)
    (if (null? ls)
        ret
        (reverse2 (cdr ls) (cons (car ls) ret)))))
         
(define reverse
  (lambda (ls)
    (reverse2 ls '())))

(define static-wrong 
  (lambda (msg v)
    (display msg)
    (display v)
    (newline)))

(define rewrite-cond
  (lambda (e*)
    (cond ((null? e*) (static-wrong "bad syntax in" "cond"))
          ((null? (cdr e*))
           (if (eq? (caar e*) 'else)
               (cadar e*)
               (list 'if (caar e*) (cadar e*) #f)))
          (else 
           (list 'if (caar e*) (cadar e*) (rewrite-cond (cdr e*)))))))

(define rewrite-let
  (lambda (e)
    (if (pair? (car e))
        (rewrite-let-normal (car e) (cadr e))
        (rewrite-let-loop (car e) (cadr e) (caddr e)))))

(define rewrite-let-normal
  (lambda (bind body)
    (let ((n* (map car bind))
          (e* (map cadr bind)))
      (cons (list 'lambda n*
                  body) e*))))

(define rewrite-let-loop
  (lambda (name bind body)
    (let ((n* (map car bind))
          (e* (map cadr bind)))
      (cons (list (cond
                    ((eq? (length n*) 1) 'Y1)
                    ((eq? (length n*) 2) 'Y2)
                    ((eq? (length n*) 3) 'Y3))
                  (list 'lambda (list name)
                        (list 'lambda n*
                              body)))
            e*))))

(define rewrite-let*
  (lambda (rbind body)
    (if (null? rbind)
        body
        (rewrite-let* (cdr rbind)
                      (list (list 'lambda (list (caar rbind)) body) (cadar rbind))))))
      
(define Y1
    (lambda (F)
      ((lambda (u) (u u))
       (lambda (x) (F (lambda (v) ((x x) v)))))))

(define Y2
    (lambda (F)
      ((lambda (u) (u u))
       (lambda (x) (F (lambda (v1 v2) ((x x) v1 v2)))))))

(define Y3
    (lambda (F)
      ((lambda (u) (u u))
       (lambda (x) (F (lambda (v1 v2 v3) ((x x) v1 v2 v3)))))))

(define compute-kind
  (lambda (r n)
    (or (local-variable? r 0 n)
        (global-variable? g.current n)
        (global-variable? g.init n))))

(define *defined* '())
(define adjoint
  (lambda (n)
    (set! *defined* (cons n *defined*))
    (g.current-extend! n)))

(define r-extend* 
  (lambda (r n*)
    (cons n* r)))

(define local-variable? 
  (lambda (r i n)
    (and (pair? r)
         (let scan ((names (car r))
                    (j 0) )
           (cond ((pair? names) 
                  (if (eq? n (car names))
                      (cons 'local (cons i j))
                      (scan (cdr names) (+ 1 j)) ) )
                 ((null? names)
                  (local-variable? (cdr r) (+ i 1) n) )
                 ((eq? n names) (cons 'local (cons i j))))))))

(define g.current-extend! 
  (lambda (n)
    (let ((level (length g.current)))
      (set! g.current 
            (cons (cons n (cons 'global level)) g.current))
      level)))

(define global-variable? 
  (lambda (g n)
    (let ((var (assq n g)))
      (and (pair? var)
           (cdr var) ) ) ))

(define global-fetch 
  (lambda (i)
    (vector-ref sg.current i) ))

(define global-update! 
  (lambda (i v)
    (vector-set! sg.current i v) ))

(define g.init-extend! 
  (lambda (n)
    (let ((level (length g.init)))
      (set! g.init
            (cons (cons n (cons 'predefined level)) g.init))
      level )))

(define defprimitive
  (lambda (name value num)
    (begin
      (g.init-extend! name)
      (description-extend! name (list 'function name num)))))

(define get-description 
  (lambda (name)
    (let ((p (assq name desc.init)))
      (and (pair? p) (cdr p)) ) ))

(define description-extend! 
  (lambda (name description)
    (set! desc.init 
          (cons (cons name description) desc.init))))

(define ALTERNATIVE
  (lambda (m1 m2 m3)
    (let ((mm2 (append m2 (GOTO (length m3)))))
      (append m1 (JUMP-FALSE (length mm2)) mm2 m3))))

(define SHALLOW-ARGUMENT-SET!
  (lambda (j m)
    (append m (SET-SHALLOW-ARGUMENT! j))))

(define DEEP-ARGUMENT-SET!
  (lambda (i j m)
    (append m (SET-DEEP-ARGUMENT! i j))))

(define GLOBAL-SET!
  (lambda (i m)
    (append m (SET-GLOBAL! i))))

(define SEQUENCE 
  (lambda (m m+)
    (append m m+)))

(define FIX-CLOSURE
  (lambda (m+ arity)
    (let* ((the-function (append (ARITY=? (+ arity 1)) (EXTEND-ENV)
                                 m+  (RETURN) ))
           (the-goto (GOTO (length the-function))) )
      (append (CREATE-CLOSURE (length the-goto)) the-goto the-function) ) ))

(define TR-FIX-LET
  (lambda (m* m+)
    (append m* (EXTEND-ENV) m+)))

(define FIX-LET 
  (lambda (m* m+)
    (append m* (EXTEND-ENV) m+ (UNLINK-ENV))))

(define CALL1
  (lambda (address m1)
    (append m1 (INVOKE1 address) ) ))

(define CALL2
  (lambda (address m1 m2)
    (append m1 (PUSH-VALUE) m2 (POP-ARG1) (INVOKE2 address))))

(define CALL3
  (lambda (address m1 m2 m3)
    (append m1 (PUSH-VALUE) 
            m2 (PUSH-VALUE) 
            m3 (POP-ARG2) (POP-ARG1) (INVOKE3 address))))

(define TR-REGULAR-CALL
  (lambda (m m*)
    (append m (PUSH-VALUE) m* (POP-FUNCTION) (FUNCTION-INVOKE))))

(define REGULAR-CALL 
  (lambda (m m*)
    (append m (PUSH-VALUE) m* (POP-FUNCTION) 
            (PRESERVE-ENV) (FUNCTION-INVOKE) (RESTORE-ENV))))

(define NARY-CLOSURE
  (lambda (m+ arity)
    (let* ((the-function (append (ARITY>=? (+ arity 1)) (PACK-FRAME! arity)
                                 (EXTEND-ENV) m+ (RETURN) ))
           (the-goto (GOTO (length the-function))) )
      (append (CREATE-CLOSURE (length the-goto)) the-goto the-function) ) ))

(define STORE-ARGUMENT
  (lambda (m m* rank)
    (append m (PUSH-VALUE) m* (POP-FRAME! rank))))

(define CONS-ARGUMENT
  (lambda (m m* arity)
    (append m (PUSH-VALUE) m* (POP-CONS-FRAME! arity))))
;;;---------------------------------------------------

;;;--------------------initialize--------------------------
(define r.init '())
(define sg.current (make-vector 100))
(define sg.init (make-vector 100))
(define g.current '())
(define g.init '())
(define desc.init '())
;;;oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
;;; Describe a predefined value.
;;; The description language only represents primitives with their arity:
;;;          (FUNCTION address . variables-list)
;;; with variables-list := () | (a) | (a b) | (a b c)
;;; Only the structure of the VARIABLES-LIST is interesting (not the
;;; names of the variables). ADDRESS is the address of the primitive
;;; to use when inlining an invokation to it. This address is
;;; represented by a Scheme procedure.
(defprimitive 'cons cons 2)
(defprimitive 'car car 1)
(defprimitive 'cdr cdr 1)
(defprimitive 'pair? pair? 1)
(defprimitive 'symbol? symbol? 1)
(defprimitive 'eq? eq? 2)
;;(defprimitive set-car! set-car! 2)
;;(defprimitive set-cdr! set-cdr! 2)
(defprimitive '+ + 2)
(defprimitive '- - 2)
(defprimitive '= = 2)
(defprimitive '< < 2)
(defprimitive '> > 2)
(defprimitive '* * 2)
(defprimitive '<= <= 2)
(defprimitive '>= >= 2)
(defprimitive 'remainder remainder 2)
(defprimitive 'display display 1)
(defprimitive 'read read 0)
(defprimitive 'primitive? primitive? 1)
(defprimitive 'continuation? continuation? 1)
(defprimitive 'null? null? 1)
(defprimitive 'newline newline 0)
(defprimitive 'eof-object? eof-object? 1)
(defprimitive 'Y1 Y1 1)
(defprimitive 'Y2 Y2 1)
(defprimitive 'Y3 Y3 1)
(defprimitive 'make-vector make-vector 1)
(defprimitive 'vector-set! vector-set! 3)
(defprimitive 'vector-ref vector-ref 2)
(defprimitive 'not not 1)
(defprimitive 'atom? atom? 1)

;;;------------------------------------------------

;;;---------------------interface---------------------
(define (SHALLOW-ARGUMENT-REF j) 'wait)
(define (DEEP-ARGUMENT-REF i j) 'wait)
(define (SET-DEEP-ARGUMENT! i j) 'wait)
(define (CHECKED-GLOBAL-REF i) 'wait)
(define (CONSTANT v) 'wait)
(define (GOTO offset) 'wait)
(define (UNLINK-ENV) 'wait)
(define (INVOKE1 address) 'wait)
(define (POP-ARG1) 'wait)
(define (POP-ARG2) 'wait)
(define (CREATE-CLOSURE offset) 'wait)
(define (RETURN) 'wait)
(define (ARITY>=? arity+1) 'wait)
(define (FUNCTION-INVOKE) 'wait)
(define (RESTORE-ENV) 'wait)
(define (POP-CONS-FRAME! arity) 'wait)
(define (ALLOCATE-DOTTED-FRAME arity) 'wait)
(define (PREDEFINED i) 'wait)
(define (SET-SHALLOW-ARGUMENT! j) 'wait)
(define (GLOBAL-REF i) 'wait)
(define (SET-GLOBAL! i) 'wait)
(define (JUMP-FALSE offset) 'wait)
(define (EXTEND-ENV) 'wait)
(define (CALL0 address) 'wait)
(define (PUSH-VALUE) 'wait)
(define (INVOKE2 address) 'wait)
(define (INVOKE3 address) 'wait)
(define (ARITY=? arity+1) 'wait)
(define (PACK-FRAME! arity) 'wait)
(define (POP-FUNCTION) 'wait)
(define (PRESERVE-ENV) 'wait)
(define (POP-FRAME! rank) 'wait)
(define (ALLOCATE-FRAME size) 'wait)
(define (FINISH) 'wait)

;;;----------------------assemble provider-------------------
(define (assemble-provider)
      (set! SHALLOW-ARGUMENT-REF (lambda (j) (list 'SHALLOW-ARGUMENT-REF j)))
      (set! DEEP-ARGUMENT-REF (lambda (i j) (list 'DEEP-ARGUMENT-REF i j)))
      (set! SET-DEEP-ARGUMENT! (lambda (i j) (list 'SET-DEEP-ARGUMENT! i j)))
      (set! CHECKED-GLOBAL-REF (lambda (i) (list 'CHECKED-GLOBAL-REF i)))
      (set! CONSTANT (lambda (v) (list 'CONSTANT v)))
      (set! GOTO (lambda (offset) (list 'GOTO offset)))
      (set! UNLINK-ENV (lambda () (list 'UNLINK-ENV)))
      (set! INVOKE1 (lambda (address) (list 'INVOKE1 address)))
      (set! POP-ARG1 (lambda () (list 'POP-ARG1)))
      (set! POP-ARG2 (lambda () (list 'POP-ARG2)))
      (set! CREATE-CLOSURE (lambda (offset) (list 'CREATE-CLOSURE offset)))
      (set! RETURN (lambda () (list 'RETURN)))
      (set! ARITY>=? (lambda (arity+1) (list 'ARITY>=? arity+1)))
      (set! FUNCTION-INVOKE (lambda () (list 'FUNCTION-INVOKE)))
      (set! RESTORE-ENV (lambda () (list 'RESTORE-ENV)))
      (set! POP-CONS-FRAME! (lambda (arity) (list 'POP-CONS-FRAME! arity)))
      (set! ALLOCATE-DOTTED-FRAME (lambda (arity) (list 'ALLOCATE-DOTTED-FRAME arity)))
      (set! PREDEFINED (lambda (i) (list 'PREDEFINED i)))
      (set! SET-SHALLOW-ARGUMENT! (lambda (j) (list 'SET-SHALLOW-ARGUMENT! j)))
      (set! GLOBAL-REF (lambda (i) (list 'GLOBAL-REF i)))
      (set! SET-GLOBAL! (lambda (i) (list 'SET-GLOBAL! i)))
      (set! JUMP-FALSE (lambda (offset) (list 'JUMP-FALSE offset)))
      (set! EXTEND-ENV (lambda () (list 'EXTEND-ENV)))
      (set! CALL0 (lambda (address) (list 'CALL0 address)))
      (set! PUSH-VALUE (lambda () (list 'PUSH-VALUE)))
      (set! INVOKE2 (lambda (address) (list 'INVOKE2 address)))
      (set! INVOKE3 (lambda (address) (list 'INVOKE3 address)))
      (set! ARITY=? (lambda (arity+1) (list 'ARITY=? arity+1)))
      (set! PACK-FRAME! (lambda (arity) (list 'PACK-FRAME! arity)))
      (set! POP-FUNCTION (lambda () (list 'POP-FUNCTION)))
      (set! PRESERVE-ENV (lambda () (list 'PRESERVE-ENV)))
      (set! POP-FRAME! (lambda (rank) (list 'POP-FRAME! rank)))
      (set! ALLOCATE-FRAME (lambda (size) (list 'ALLOCATE-FRAME size)))
      (set! FINISH (lambda () (list 'FINISH)))
)
;;;--------------------------------------------


;;;--------------opcode provider----------------------
(define (check-byte j)
  (or (and (<= 0 j) (<= j 255))
      (static-wrong "Cannot pack this number within a byte" j) ) )
(define (INVOKE0 address)
  (case address
    ((read)    (list 89))
    ((newline) (list 88))
    (else (static-wrong "Cannot integrate" address)) ) )
(define EXPLICIT-CONSTANT 'wait)
(define (opcode-provider)
  (set! CHECKED-GLOBAL-REF (lambda (i) (list 8 i)))
  (set! SHALLOW-ARGUMENT-REF (lambda (j)
                               (check-byte j)
                               (case j
                                 ((0 1 2 3) (list (+ 1 j)))
                                 (else (list 5 j)))))
  (set! SET-GLOBAL! (lambda (i) (list 27 i)))
  (set! CALL0 (lambda (address) (INVOKE0 address) ))
  (set! CALL1 (lambda (address m1)
                (append m1 (INVOKE1 address))))
  (set! INVOKE3 
        (lambda (address)
          (static-wrong "No ternary integrated procedure" address)))
  (set! ALLOCATE-DOTTED-FRAME (lambda (arity) (list 56 (+ arity 1))))
  
  (set! PREDEFINED
        (lambda (i)
          (check-byte i)
          (case i
            ;; 0=\#t, 1=\#f, 2=(), 3=cons, 4=car, 5=cdr, 6=pair?, 7=symbol?, 8=eq?
            ((0 1 2 3 4 5 6 7 8) (list (+ 10 i)))
            (else (list 19 i)))))
  (set! DEEP-ARGUMENT-REF (lambda (i j) (list 6 i j)))
  (set! SET-SHALLOW-ARGUMENT! 
        (lambda (j)
          (case j
            ((0 1 2 3) (list (+ 21 j)))
            (else      (list 25 j)))))
  (set! SET-DEEP-ARGUMENT! (lambda (i j) (list 26 i j)))
  (set! GLOBAL-REF (lambda (i) (list 7 i)))
  (set! GOTO 
        (lambda (offset)
          (cond ((< offset 255) (list 30 offset))
                ((< offset (+ 255 (* 255 256))) 
                 (let ((offset1 (modulo offset 256))
                       (offset2 (quotient offset 256)) )
                   (list 28 offset1 offset2) ) )
                (else (static-wrong "too long jump" offset)))))
  (set! CONSTANT 
        (lambda (value)
          (cond ((eq? value #t)    (list 10))
                ((eq? value #f)    (list 11))
                ((eq? value '())   (list 12))
                ((equal? value -1) (list 80))
                ((equal? value 0)  (list 81))
                ((equal? value 1)  (list 82))
                ((equal? value 2)  (list 83))
                ((equal? value 3)  (list 84))
                ((and (integer? value)  ; immediate value
                      (>= value 0)
                      (< value 255) )
                 (list 79 value) )
                (else (EXPLICIT-CONSTANT value)))))  
  ;;; All gotos have positive offsets (due to the generation)
  (set! JUMP-FALSE
        (lambda (offset)
          (cond ((< offset 255) (list 31 offset))
                ((< offset (+ 255 (* 255 256))) 
                 (let ((offset1 (modulo offset 256))
                       (offset2 (quotient offset 256)) )
                   (list 29 offset1 offset2) ) )
                (else (static-wrong "too long jump" offset)))))
  (set! CREATE-CLOSURE (lambda (offset) (list 40 offset)))
  (set! EXTEND-ENV (lambda () (list 32)))
  (set! UNLINK-ENV (lambda () (list 33)))
  (set! INVOKE1 
        (lambda (address)
          (case address
            ((car)     (list 90))
            ((cdr)     (list 91))
            ((pair?)   (list 92))
            ((symbol?) (list 93))
            ((display) (list 94))
            ((primitive?) (list 95))
            ((null?)   (list 96))
            ((continuation?) (list 97))
            ((eof-object?)   (list 98))
            (else (static-wrong "Cannot integrate" address)))))
  (set! POP-CONS-FRAME! (lambda (arity) (list 47 arity)))
  (set! PACK-FRAME! (lambda (arity) (list 44 arity)))
  (set! ARITY>=? (lambda (arity+1) (list 78 arity+1)))
  (set! PUSH-VALUE (lambda () (list 34)))
  (set! POP-ARG1 (lambda () (list 35)))
  (set! INVOKE2
        (lambda (address)
          (case address
            ((cons)     (list 100))
            ((eq?)      (list 101))
            ((set-car!) (list 102))
            ((set-cdr!) (list 103))
            ((+)        (list 104))
            ((-)        (list 105))
            ((=)        (list 106))
            ((<)        (list 107))
            ((>)        (list 108))
            ((*)        (list 109))
            ((<=)       (list 110))
            ((>=)       (list 111))
            ((remainder)(list 112))
            (else (static-wrong "Cannot integrate" address)))))
  (set! POP-ARG2 (lambda () (list 36)))
  (set! FUNCTION-INVOKE (lambda () (list 45)))  
  (set! PRESERVE-ENV (lambda () (list 37)))  
  (set! RESTORE-ENV (lambda () (list 38)))
  (set! ARITY=? 
        (lambda (arity+1)
          (case arity+1
            ((1 2 3 4) (list (+ 70 arity+1)))
            (else        (list 75 arity+1)))))  
  (set! RETURN (lambda () (list 43)))
  (set! POP-FUNCTION (lambda () (list 39)))
  (set! POP-FRAME! 
        (lambda (rank)
          (case rank
            ((0 1 2 3) (list (+ 60 rank)))
            (else      (list 64 rank)))))
  (set! FINISH (lambda () (list 20)))
  (set! ALLOCATE-FRAME
        (lambda (size)
          (case size
            ((0 1 2 3 4) (list (+ 50 size)))
            (else        (list 55 (+ size 1))))))
  )
;;;-----------------------------------------

;;;---------------interpret provider-------------
#|
(define *val* 'wait)
(define *env* '())
(define *pc* '())
(define *stack* (make-vector 100))
(define *stack-index* 0)
(define *arg1* 'wait)
(define *arg2* 'wait)
(define *fun* 'wait)
(define *exit* 'wait)
(define undefined-value 'undefined)

(define (activation-frame-argument sr i)
  (vector-ref (car sr) i))
(define activation-frame-next cdr)
(define (set-activation-frame-argument! sr j v)
  (vector-set! sr j v))
(define (activation-frame-argument-length v*)
  (vector-length v*))
(define allocate-activation-frame make-vector)
(define (sr-extend* sr v*)
  (cons v* sr))
(define (predefined-fetch i)
  (vector-ref sg.init i) )
(define environment-next cdr)
(define (deep-fetch sr i j)
  (if (= i 0)
      (activation-frame-argument sr j)
      (deep-fetch (environment-next sr) (- i 1) j) ) )
(define (deep-update! sr i j v)
  (if (= i 0)
      (set-activation-frame-argument! sr j v)
      (deep-update! (environment-next sr) (- i 1) j v) ) )
(define (stack-push v)
  (vector-set! *stack* *stack-index* v)
  (set! *stack-index* (+ *stack-index* 1)) )
(define (stack-pop)
  (set! *stack-index* (- *stack-index* 1))
  (vector-ref *stack* *stack-index*) )
(define (restore-stack copy)
  (set! *stack-index* (vector-length copy))
  (vector-copy! copy *stack* 0 *stack-index*) )
(define wrong display)
(define make-closure cons)
(define closure-closed-environment cdr)
(define closure-code car)
(define closure? pair?)
(define continuation-stack 'wait)
(define (listify! v* arity)
  (let loop ((index (- (activation-frame-argument-length v*) 1))
             (result '()) )
    (if (= arity index)
        (set-activation-frame-argument! v* arity result)
        (loop (- index 1)
              (cons (activation-frame-argument v* (- index 1))
                    result ) ) ) ) )
(define (invoke f)
  (cond ((closure? f)
         (stack-push *pc*)
         (set! *env* (closure-closed-environment f))
         (set! *pc* (closure-code f)) )
        ((primitive? f)
         ((primitive-address f)) )
        ((continuation? f)
         (if (= (+ 1 1) (activation-frame-argument-length *val*))
             (begin
               (restore-stack (continuation-stack f))
               (set! *val* (activation-frame-argument *val* 0))
               (set! *pc* (stack-pop)) )
             (wrong "Incorrect arity" 'continuation) ) )
        (else (wrong "Not a function" f)) ) )
(define primitive-address (lambda (v) v))

(define (interpret-provider)
  (set! SHALLOW-ARGUMENT-REF 
        (lambda (j)
          (list (lambda () (set! *val* (activation-frame-argument *env* j)))) ))
  (set! PREDEFINED (lambda (i)
                     (list (lambda () (set! *val* (predefined-fetch i)))) ))
  (set! DEEP-ARGUMENT-REF 
        (lambda (i j)
          (list (lambda () (set! *val* (deep-fetch *env* i j))))))
  (set! SET-SHALLOW-ARGUMENT! 
        (lambda (j)
          (list (lambda () (set-activation-frame-argument! *env* j *val*)))))
  (set! SET-DEEP-ARGUMENT! 
        (lambda (i j)
          (list (lambda () (deep-update! *env* i j *val*)))))
  (set! GLOBAL-REF 
        (lambda (i)
          (list (lambda () (set! *val* (global-fetch i))))))
  (set! CHECKED-GLOBAL-REF 
        (lambda (i)
          (list (lambda () (set! *val* (global-fetch i))
                  (when (eq? *val* undefined-value)
                    (wrong "Uninitialized variable") ))) ))
  (set! SET-GLOBAL! 
        (lambda (i)
          (list (lambda () (global-update! i *val*)))))
  (set! CONSTANT (lambda (value)
                   (list (lambda () (set! *val* value)))))
  (set! JUMP-FALSE 
        (lambda (i)
          (list (lambda () (and (not *val*) (set! *pc* (list-tail *pc* i)))))))
  (set! GOTO (lambda (i)
               (list (lambda () (set! *pc* (list-tail *pc* i))))))
  (set! EXTEND-ENV 
        (lambda ()
          (list (lambda () (set! *env* (sr-extend* *env* *val*))))))
  (set! UNLINK-ENV 
        (lambda ()
          (list (lambda () (set! *env* (activation-frame-next *env*))))))
  (set! CALL0 
        (lambda (address)
          (list (lambda () (set! *val* (address))))))
  (set! INVOKE1 
        (lambda (address)
          (list (lambda () (set! *val* (address *val*))))))
  (set! PUSH-VALUE (lambda ()
                     (list (lambda () (stack-push *val*)))))
  (set! POP-ARG1 (lambda ()
                   (list (lambda () (set! *arg1* (stack-pop))))))
  (set! INVOKE2 (lambda (address)
                  (list (lambda () (set! *val* (address *arg1* *val*))))))
  (set! POP-ARG2 (lambda ()
                   (list (lambda () (set! *arg2* (stack-pop)))) ))
  (set! INVOKE3 (lambda (address)
                  (list (lambda () (set! *val* (address *arg1* *arg2* *val*))))))
  (set! CREATE-CLOSURE 
        (lambda (offset)
          (list (lambda () (set! *val* (make-closure (list-tail *pc* offset) 
                                                     *env* )))) ))
  (set! ARITY=? (lambda (arity+1)
                  (list (lambda () 
                          (unless (= (activation-frame-argument-length *val*) arity+1)
                            (wrong "Incorrect arity") ) )) ))
  (set! RETURN (lambda ()
                 (list (lambda () (set! *pc* (stack-pop))))))
  (set! PACK-FRAME! (lambda (arity)
                      (list (lambda () (listify! *val* arity)))))
  (set! ARITY>=? 
        (lambda (arity+1)
          (list (lambda () 
                  (unless (>= (activation-frame-argument-length *val*) arity+1)
                    (wrong "Incorrect arity") ) )) ))
  (set! POP-FUNCTION (lambda ()
                       (list (lambda () (set! *fun* (stack-pop)))) ))
  (set! FUNCTION-INVOKE (lambda ()
                          (list (lambda () (invoke *fun*))) ))
  (set! PRESERVE-ENV (lambda ()
                       (list (lambda () (stack-push *env*))) ))
  (set! RESTORE-ENV (lambda ()
                      (list (lambda () (set! *env* (stack-pop))))))
  (set! POP-FRAME! 
        (lambda (rank)
          (list (lambda () (set-activation-frame-argument! *val* rank (stack-pop))))))
  (set! POP-CONS-FRAME! 
        (lambda (arity)
          (list (lambda () 
                  (set-activation-frame-argument! 
                   *val* arity (cons (stack-pop)
                                     (activation-frame-argument *val* arity)))))))
  (set! ALLOCATE-FRAME 
        (lambda (size)
          (let ((size+1 (+ size 1)))
            (list (lambda () (set! *val* (allocate-activation-frame size+1)))))))
  (set! ALLOCATE-DOTTED-FRAME 
        (lambda (arity)
          (let ((arity+1 (+ arity 1)))
            (list (lambda ()
                    (let ((v* (allocate-activation-frame arity+1)))
                      (set-activation-frame-argument! v* arity '())
                      (set! *val* v*) ) )) ) ))
  (set! FINISH (lambda ()
                 (list (lambda () (*exit* *val*)))))
  )
|#

;;--------------------------begin------------------------------

(define compiler-generator
  (lambda (provider)
    (provider)
    (lambda (e)
      (set! *defined* '())
      (set! g.current '())
      (let ((result (meaning e '() #t)))
        (if (null? *defined*)
            result
            (static-wrong "undefined" *defined*))))))

(define compile-debug
  (compiler-generator assemble-provider))

(define compile
  (lambda (e)
    (let ((cc (compiler-generator opcode-provider)))
      (let ((code (cc e)))
        (if (pair? code)
            (list (list->vector code)
                  (map (lambda (x)
                         (cons (car x) (cddr x))) g.current))
            code)))))
            
           
      
    