#lang typed/racket/base

(require (only-in typed/mred/mred Snip% Frame%)
         (only-in racket/gui/base get-display-backing-scale)
         typed/racket/draw typed/racket/class racket/match
         plot/utils
         plot/private/common/parameter-group
         plot/private/common/draw
         plot/private/common/deprecation-warning
         plot/private/common/type-doc
         plot/private/common/utils
         plot/private/plot2d/plot-area
         plot/private/no-gui/plot2d
         plot/private/no-gui/plot2d-utils
         "lazy-snip-typed.rkt"
         typed/racket/unsafe)

(unsafe-provide plot-snip
                plot-frame
                plot)

(require/typed plot/utils
  (anchor/c (-> Any Boolean))
  (plot-color/c (-> Any Boolean))
  (plot-file-format/c (-> Any Boolean)))

;; ===================================================================================================
;; Plot to a snip

(:: plot-snip
    (->* [(Treeof (U renderer2d nonrenderer))]
         [#:x-min (U Real #f) #:x-max (U Real #f)
          #:y-min (U Real #f) #:y-max (U Real #f)
          #:width Positive-Integer
          #:height Positive-Integer
          #:title (U String #f)
          #:x-label (U String #f)
          #:y-label (U String #f)
          #:legend-anchor Anchor]
         (Instance Snip%)))
(define (plot-snip renderer-tree
                   #:x-min [x-min #f] #:x-max [x-max #f]
                   #:y-min [y-min #f] #:y-max [y-max #f]
                   #:width [width (plot-width)]
                   #:height [height (plot-height)]
                   #:title [title (plot-title)]
                   #:x-label [x-label (plot-x-label)]
                   #:y-label [y-label (plot-y-label)]
                   #:legend-anchor [legend-anchor (plot-legend-anchor)])
  (define fail/kw (make-raise-keyword-error 'plot-snip))
  (cond
    [(and x-min (not (rational? x-min)))  (fail/kw "#f or rational" '#:x-min x-min)]
    [(and x-max (not (rational? x-max)))  (fail/kw "#f or rational" '#:x-max x-max)]
    [(and y-min (not (rational? y-min)))  (fail/kw "#f or rational" '#:y-min y-min)]
    [(and y-max (not (rational? y-max)))  (fail/kw "#f or rational" '#:y-max y-max)]
    [else
     (parameterize ([plot-title          title]
                    [plot-x-label        x-label]
                    [plot-y-label        y-label]
                    [plot-legend-anchor  legend-anchor])
       (define saved-plot-parameters (plot-parameters))
       (define renderer-list (get-renderer-list renderer-tree))
       (define bounds-rect (get-bounds-rect renderer-list x-min x-max y-min y-max))
       
       (: make-bm (-> Boolean Rect Positive-Integer Positive-Integer
                      (Values (Instance Bitmap%) (U #f (Instance 2D-Plot-Area%)))))
       (define (make-bm anim? bounds-rect width height)
         (: area (U #f (Instance 2D-Plot-Area%)))
         (define area #f)
         (define bm (make-bitmap
                     width height #t
                     #:backing-scale (or (get-display-backing-scale) 1.0)))
         (parameterize/group ([plot-parameters  saved-plot-parameters]
                              [plot-animating?  (if anim? #t (plot-animating?))])
           (define dc (make-object bitmap-dc% bm))
           (define-values (x-ticks x-far-ticks y-ticks y-far-ticks)
             (get-ticks renderer-list bounds-rect))
           (define new-area
             (make-object 2d-plot-area%
                          bounds-rect x-ticks x-far-ticks y-ticks y-far-ticks
                          dc 0 0 width height))
           (set! area new-area)
           (plot-area new-area renderer-list))
         (values bm area))
       
       (define-values (bm area) (make-bm #f bounds-rect width height))
       
       (make-2d-plot-snip bm saved-plot-parameters make-bm bounds-rect area width height))]))

;; ===================================================================================================
;; Plot to a frame

(:: plot-frame
    (->* [(Treeof (U renderer2d nonrenderer))]
         [#:x-min (U Real #f) #:x-max (U Real #f)
          #:y-min (U Real #f) #:y-max (U Real #f)
          #:width Positive-Integer
          #:height Positive-Integer
          #:title (U String #f)
          #:x-label (U String #f)
          #:y-label (U String #f)
          #:legend-anchor Anchor]
         (Instance Frame%)))
(define (plot-frame renderer-tree
                    #:x-min [x-min #f] #:x-max [x-max #f]
                    #:y-min [y-min #f] #:y-max [y-max #f]
                    #:width [width (plot-width)]
                    #:height [height (plot-height)]
                    #:title [title (plot-title)]
                    #:x-label [x-label (plot-x-label)]
                    #:y-label [y-label (plot-y-label)]
                    #:legend-anchor [legend-anchor (plot-legend-anchor)])
  (define fail/kw (make-raise-keyword-error 'plot-frame))
  (cond
    [(and x-min (not (rational? x-min)))  (fail/kw "#f or rational" '#:x-min x-min)]
    [(and x-max (not (rational? x-max)))  (fail/kw "#f or rational" '#:x-max x-max)]
    [(and y-min (not (rational? y-min)))  (fail/kw "#f or rational" '#:y-min y-min)]
    [(and y-max (not (rational? y-max)))  (fail/kw "#f or rational" '#:y-max y-max)]
    [else
     ;; make-snip will be called in a separate thread, make sure the
     ;; parameters have the correct values in that thread as well.
     (define saved-plot-parameters (plot-parameters))
     (cond ;; check arguments because function is provided unsafely
      [(not (and (integer? width) (positive? width))) (fail/kw "positive integer" '#:width width)]
      [(not (and (integer? height) (positive? height))) (fail/kw "positive integer" '#:height height)]
      [(and title (not (string? title))) (fail/kw "#f or string" '#:title title)]
      [(and x-label (not (string? x-label))) (fail/kw "#f or string" '#:x-label x-label)]
      [(and y-label (not (string? y-label))) (fail/kw "#f or string" '#:y-label y-label)]
      [(not (anchor/c legend-anchor)) (fail/kw "anchor/c" '#:legend-anchor legend-anchor)])
     (: make-snip (-> Positive-Integer Positive-Integer (Instance Snip%)))
     (define (make-snip width height)
       (parameterize/group ([plot-parameters  saved-plot-parameters])
         (plot-snip
          renderer-tree
          #:x-min x-min #:x-max x-max #:y-min y-min #:y-max y-max #:width width #:height height
          #:title title #:x-label x-label #:y-label y-label #:legend-anchor legend-anchor)))
           (make-snip-frame make-snip width height (if title (format "Plot: ~a" title) "Plot"))]))

;; ===================================================================================================
;; Plot to a frame or a snip, depending on (plot-new-window?)

(:: plot
    (->* [(Treeof (U renderer2d nonrenderer))]
         [#:x-min (U Real #f) #:x-max (U Real #f)
          #:y-min (U Real #f) #:y-max (U Real #f)
          #:width Positive-Integer
          #:height Positive-Integer
          #:title (U String #f)
          #:x-label (U String #f)
          #:y-label (U String #f)
          #:legend-anchor Anchor
          #:out-file (U Path-String Output-Port #f)
          #:out-kind (U 'auto Image-File-Format)
          #:fgcolor Plot-Color
          #:bgcolor Plot-Color
          #:lncolor Plot-Color]
         (U (Instance Snip%) Void)))
(define (plot renderer-tree
              #:x-min [x-min #f] #:x-max [x-max #f]
              #:y-min [y-min #f] #:y-max [y-max #f]
              #:width [width (plot-width)]
              #:height [height (plot-height)]
              #:title [title (plot-title)]
              #:x-label [x-label (plot-x-label)]
              #:y-label [y-label (plot-y-label)]
              #:legend-anchor [legend-anchor (plot-legend-anchor)]
              #:out-file [out-file #f]
              #:out-kind [out-kind 'auto]
              #:fgcolor [fgcolor #f]
              #:bgcolor [bgcolor #f]
              #:lncolor [lncolor #f])  ; unused
  (when fgcolor
    (deprecation-warning "the plot #:fgcolor keyword argument" "plot-foreground"))
  (when bgcolor
    (deprecation-warning "the plot #:bgcolor keyword argument" "plot-background"))
  (when lncolor
    (deprecation-warning "the plot #:lncolor keyword argument"))
  
  (define fail/kw (make-raise-keyword-error 'plot))
  (cond
    [(and x-min (not (rational? x-min)))  (fail/kw "#f or rational" '#:x-min x-min)]
    [(and x-max (not (rational? x-max)))  (fail/kw "#f or rational" '#:x-max x-max)]
    [(and y-min (not (rational? y-min)))  (fail/kw "#f or rational" '#:y-min y-min)]
    [(and y-max (not (rational? y-max)))  (fail/kw "#f or rational" '#:y-max y-max)]
    [else
     (cond ;; check arguments because function is provided unsafely
      [(and out-kind (not (plot-file-format/c out-kind)))
       (fail/kw "plot-file-format/c" '#:out-kind out-kind)]
      [(and fgcolor (not (plot-color/c fgcolor)))
       (fail/kw "plot-color/c" '#:fgcolor fgcolor)]
      [(and bgcolor (not (plot-color/c bgcolor)))
       (fail/kw "plot-color/c" '#:bgcolor bgcolor)])
     (parameterize ([plot-foreground  (if fgcolor fgcolor (plot-foreground))]
                    [plot-background  (if bgcolor bgcolor (plot-background))])
       (when out-file
         (plot-file
          renderer-tree out-file out-kind
          #:x-min x-min #:x-max x-max #:y-min y-min #:y-max y-max #:width width #:height height
          #:title title #:x-label x-label #:y-label y-label #:legend-anchor legend-anchor))
       
       (cond [(plot-new-window?)
              (define frame
                (plot-frame
                 renderer-tree
                 #:x-min x-min #:x-max x-max #:y-min y-min #:y-max y-max #:width width #:height height
                 #:title title #:x-label x-label #:y-label y-label #:legend-anchor legend-anchor))
              (send frame show #t)
              (void)]
             [else
              (plot-snip
               renderer-tree
               #:x-min x-min #:x-max x-max #:y-min y-min #:y-max y-max #:width width #:height height
               #:title title #:x-label x-label #:y-label y-label #:legend-anchor legend-anchor)]))]))
