(add-load-path "../lib/" :relative)

(define-module Check
  (export type-check)
  (use srfi-1)
  (use srfi-9)
  (use Util)
  (use util.match)

  (define-record-type signature
    (sign typ expr)
    signature?
    (typ  sig-type)
    (expr sig-expr))

  (define (generics-cons/index f gen)
    (if gen
        (let1 xs (get-signatures gen)
              (generic-signatures (cons (f (length xs)) xs)))
        (generic-signatures (list (f 0)))))


  (define (proper-def? def)
    (and (pair? def) (eq? (car def) '=)))

  ;;[expr] -> {'name => [signature]}
  ;;e.g. (= (car (List a) a) xs (xs true))
  (define (type-check program binding)
    (let* ([types
            (fold (fn [def binding]
                      (let* ([def    (if (proper-def? def) def `(= (main a) ,def))]
                             [name   (caadr def)]
                             [sig    (cdadr def)]
                             [params (zip  (drop-right (cddr def) 1) sig)] ;;[(xs (List a))]
                             [expr   (list (last def) (last sig))])        ;;((xs true) a)
                        (hash-table-put! binding name
                                         (sign (cons 'Fn sig) (cons expr params)))
                        binding))
                  binding
                  program)]
           [main (hash-table-get types 'main #f)])
      (if main
          (begin (format #t "FIN: ~S\n" (check-fn (sig-expr main) types))
                 types)
          types)))


  ;; atom    -> 'Name
  ;; symbol  -> x | [signature]
  ;; (^ x y) -> [(Fn 'a 'b)]
  ;; (f x)   -> [signature]
  (define (check-fn fn types)
    (let* ([expr (caar fn)] ;;(xs true)
           [rett (cadar fn)] ;;a
           [env  (cdr fn)]
           [expt (type-of expr env types)]) ;;[(xs (List a))]
      (call/cc (unify rett expt))))

  (define (type-of expr env types)
    (let ([x (cond
              [(string?  expr) 'String]
              [(number?  expr) 'Number]
              [(char?    expr) 'Char]
              [(keyword? expr) 'Keyword]
              [(symbol?  expr)
               (let1 x (assoc expr env)
                     (if x x (ref types expr)))]
              [(quote-expr? expr) 'Symbol]
              [(lambda-expr? expr)
               (sign `(Fn ,(gensym) ,(gensym)) '())]
              [(pair?    expr)
               (call/cc (unify (type-of (car expr) env types)
                               (map (^x (type-of x env types)) (cdr expr))))])])
      (if (not x) (format #t "type is false: ~S\n" expr))
      x))

  (define (primitive? t)
    (case t
      [(String Number Char Keyword Symbol) #t]
      [else #f]))
  (define (type-var? t)
    (and (symbol? t) (not (primitive? t))
         ;(char-lower-case? (string->list (symbol->string t)))
         ))
  (define (datatype? t)
    (pair? t))

  (define (replace-type-var sigs var t)
    (if (null? sigs) '()
        (cons (cond [(eq? (car sigs) var) t]
                    [(pair? (car sigs)) (replace-type-var (car sigs) var t)]
                    [else (car sigs)])
              (replace-type-var (cdr sigs) var t))))

  (define (f-type? x)
    (and (pair? x) (eq? (car x) 'Fn)))


  (define (unify-app t1 t2)
    (let* ([sigt (cdr (sig-type t1))] ;;cdr to remove 'Fn
           [binding (call/cc (unify (car sigt) (car t2)))]
           [rest-sigt (fold (fn [b sigt]
                                (replace-type-var sigt (car b) (cdr b)))
                            (cdr sigt) binding)])
      (cond [(null? rest-sigt) (last sigt)] ;;too many args
            [(= 1 (length rest-sigt)) (last rest-sigt)] ;;fully applied
            [(null? (cdr t2)) (sign (cons 'Fn rest-sigt) '())] ;;too few args
            [else (call/cc (unify (sign (cons 'Fn rest-sigt) '()) (cdr t2)))])))


  (define (show-signature s)
    (if (signature? s) (sig-type s) s))

  ;;a Number -> ((a Number))
  (define (unify t1 t2)
    (fn [cont]
        (format #t "~14S ≡? ~S\n" (show-signature t1) (show-signature t2))
        (cond
         [(and (primitive? t1) (primitive? t2))
          (if (eq? t1 t2) '() (cont #f))]
         [(and (f-type? t1) (signature? t2)) ;;match fn type as datatype
          (call/cc (unify t1 (sig-type t2)))]
         [(and (datatype? t1) (datatype? t2))
          (if (eq? (car t1) (car t2))
              (apply append (map (fn [tx ty] ((unify tx ty) cont)) (cdr t1) (cdr t2))))]
         [(type-var? t1) (list (cons t1 t2))]
         [(type-var? t2) (list (cons t2 t1))]
         [(and (signature? t1) (pair? t2))
          (unify-app t1 t2)]
         [else (cont #f)]))))
