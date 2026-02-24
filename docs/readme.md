## Sheme DB サービス (sheme_server)

Shemeを使用してDB連携のサーバーサイドWEBアプリケーションが実現可能かの実験サイト。  
住所から郵便番号の検索、郵便番号から住所の検索の機能を有し、結果として得た住所のマップ（Google Maps）とAI（ChatGPT）による詳細情報の表示が行える。

### DB連携
MySQLに日本郵便のKEN_ALL.CSV（約12万件）を取り込み検索可能にした。  
MySQL C API  libmysqlclient-dev  

### WEB連携
libmicrohttpd (MHD)  

### ビルド
gcc -fPIC -shared -o libbridge.so bridge.c     `mysql_config --cflags --libs`     -lmicrohttpd -ldl -pthread  
scheme --program scheme_server.ss --compile-imported-libraries  


   
### 公開
本サービスはhttp://127.0.0.1:8108/で稼働している。  
OpenRestyでSSL化してサブドメインにリバースプロキシで接続し  
https://sheme.etech21.net/として公開している。    
systemdサービスにより常駐化している。  




