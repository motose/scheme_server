#!r6rs
(import (chezscheme))

(load-shared-object "./libbridge.so")

;; C関数のバインディング
(define start-http (foreign-procedure "start_http_server" () void))
(define fetch-by-zip (foreign-procedure "fetch_by_zip" (string) string))
(define fetch-by-addr (foreign-procedure "fetch_by_addr" (string) string))
(define set-response-html (foreign-procedure "set_response_html" (string) void))

(define get-request-ready (foreign-procedure "get_request_ready" () int))
(define clear-request-ready! (foreign-procedure "clear_request_ready" () void))
(define get-zip-btn (foreign-procedure "get_request_zip_btn" () int))
(define get-addr-btn (foreign-procedure "get_request_addr_btn" () int))
(define get-zip (foreign-procedure "get_request_zip" () string))
(define get-addr (foreign-procedure "get_request_addr" () string))

;; string-join の自作
(define (string-join lst sep)
  (if (null? lst)
      ""
      (let loop ((rest (cdr lst)) (result (car lst)))
        (if (null? rest)
            result
            (loop (cdr rest) (string-append result sep (car rest)))))))

;; string-split の自作
(define (string-split str ch)
  (let loop ((chars (string->list str)) (current '()) (result '()))
    (cond
      ((null? chars)
       (reverse (cons (list->string (reverse current)) result)))
      ((char=? (car chars) ch)
       (loop (cdr chars) '() (cons (list->string (reverse current)) result)))
      (else
       (loop (cdr chars) (cons (car chars) current) result)))))

;; 検索結果のHTMLテーブルを生成
(define (render-results result)
  (if (or (string=? result "") (string=? result "\n"))
      "<div class='card'>該当なし</div>"
      (let* ((lines (string-split result #\newline))
             (rows
              (map
               (lambda (line)
                 (let ((cols (string-split line #\tab)))
                   (if (= (length cols) 4)
                       (let* ((zip (list-ref cols 0))
                              (zip1 (substring zip 0 3))
                              (zip2 (substring zip 3 (string-length zip)))
                              (addr (string-append (list-ref cols 1) (list-ref cols 2) (list-ref cols 3))))
                         (format
"<tr>
  <td>
    <span class='zip'>〒~a-~a</span>
    <span class='addr'>~a</span>
  </td>
  <td>
    <div class='btn-box'>
      <button onclick=\"openMap('~a')\" class='action-btn maps-btn'>MAP</button>
      <button onclick=\"openAI('~a')\" class='action-btn ai-btn'>AI</button>
    </div>
  </td>
</tr>"
                                 zip1 zip2 addr addr addr))
                       "")))
               lines)))
        (string-append "<div class='card'><h2>検索結果</h2><table>"
                       (string-join rows "")
                       "</table></div>"))))

;; HTML全体を生成
(define (generate-html zip addr zip-btn addr-btn)
  (let ((form-html
"<html>
<head>
  <meta charset='UTF-8'>
  <title>Scheme DB サービス</title>
  <link rel='icon' href='https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Lambda_lc.svg/330px-Lambda_lc.svg.png' type='image/svg+xml'>
  <style>
    body { margin: 0; font-family: sans-serif; background-color: #1a1a1a; color: #eee; }
    .header {
      background-color: #ffffff;
      color: #333;
      padding: 0 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      height: 65px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .container { padding: 40px; max-width: 1000px; margin: 0 auto; }
    .search-row { display: flex; gap: 20px; margin-bottom: 20px; }
    .card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); flex: 1; color: #000; }
    .btn-box { display: flex; gap: 8px; justify-content: flex-end; }
    .action-btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 6px; text-decoration: none; font-size: 13px; font-weight: bold; cursor: pointer; color: white; border: none; }
    .maps-btn { background-color: #ea4335; }
    .ai-btn { background-color: #10a37f; }
    input[type='text'] { width: 100%; box-sizing: border-box; padding: 12px; border: 1px solid #ddd; border-radius: 4px; }
    button.search-btn {
      width: 100%;
      padding: 12px;
      background-color: #339933;
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-weight: bold;
      margin-top: 10px;
      transition: background-color 0.2s;
    }
    button.search-btn:hover {
      background-color: #2b822b;
    }
    .nav-btn {
      display: inline-flex;
      align-items: center;
      padding: 6px 16px;
      margin-right: 12px;
      border-radius: 20px;
      text-decoration: none;
      font-size: 13px;
      font-weight: bold;
      color: white;
      border: 1px solid rgba(255, 255, 255, 0.4);
      background-color: rgba(0, 0, 0, 0.4);
      transition: all 0.2s ease;
    }
    .nav-btn:hover {
      background-color: white;
      color: #007d9c;
      transform: translateY(-1px);
    }
    .zip { font-family: monospace; font-weight: bold; color: #5e5086; }
    .addr { font-size: 1.1rem; color: #000; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; table-layout: fixed; }
    td { border-bottom: 1px solid #eee; padding: 12px; vertical-align: middle; }
    td:last-child { width: 160px; text-align: right; }
  </style>
  <script>
    function openMap(addr) {
      window.open('https://www.google.com/maps/search/' + encodeURIComponent(addr), '_blank');
    }
    function openAI(addr) {
      window.open('https://chatgpt.com/?q=' + encodeURIComponent(addr + ' について詳しく教えて'),'_blank');
    }
  </script>
</head>
<body>
  <div class='header'>
    <div style='display:flex; align-items:center;'>
      <img src='https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Lambda_lc.svg/330px-Lambda_lc.svg.png' style='height:40px;margin-right:15px;' alt='Lambda'>
      <span style='font-size:2rem; font-weight:bold; margin-right:30px;'>Scheme DB サービス</span>
    </div>
    <div style='display:flex; align-items:center;'>
      <a href='https://ja.wikipedia.org/wiki/Gauche' target='_blank' class='nav-btn'>Info</a>
      <a href='/docs/readme.html' class='nav-btn'>ReadMe</a>
      <img src='https://sv1.etech21.net/assets/eTech21.png' style='height:35px;margin:0 10px;' alt='e-Tech21 Logo'>
      <span style='font-size:1.5rem;color:#666;'>e-Tech21.net</span>
    </div>
  </div>

  <div class='container'>
    <div class='search-row'>
      <div class='card'>
        <h2>住所検索</h2>
        <form action='/' method='GET'>
          <input type='text' name='addr' placeholder='新宿区歌舞伎町' value='~a'>
          <button type='submit' name='addr-btn' value='1' class='search-btn'>住所から調べる</button>
        </form>
      </div>
      <div class='card'>
        <h2>郵便番号検索</h2>
        <form action='/' method='GET'>
          <input type='text' name='zip' placeholder='1000001' maxlength='7' value='~a'>
          <button type='submit' name='zip-btn' value='1' class='search-btn'>番号から調べる</button>
        </form>
      </div>
    </div>"))
    (cond
      ((= zip-btn 1)
       (let ((result (fetch-by-zip zip)))
         (format "~a~a</body></html>" (format form-html addr zip) (render-results result))))
      ((= addr-btn 1)
       (let ((result (fetch-by-addr addr)))
         (format "~a~a</body></html>" (format form-html addr zip) (render-results result))))
      (else
       (format "~a</body></html>" (format form-html addr zip))))))

;; メインループ
(define (main-loop)
  (let loop ()
    (when (= (get-request-ready) 1)
      (let* ([zip (get-zip)]
             [addr (get-addr)]
             [zip-btn (get-zip-btn)]
             [addr-btn (get-addr-btn)]
             [html (generate-html zip addr zip-btn addr-btn)])
        (set-response-html html)
        (clear-request-ready!)))
    (sleep (make-time 'time-duration 10000000 0))
    (loop)))

;; 実行！
(start-http)
(main-loop)

