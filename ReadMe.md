# インストール
ターミナルでannotatorを置いたディレクトリへ移動

%brew install mongo
%brew install imagemagick
%brew link imagemagick
%bundle install


以上で，インストールは完了
imagemagickをリンクするときに，既にあるシステムコマンド(/use/bin/convert)とのコンフリクトが起きる．システムコマンドの方をconvert_origにrenameするなどしてよしなに対応する必要がある．

# 初期設定
1. 作業対象のblobの設置
2. オントロジーの設置
3. コンフィグファイルの設定
  development mode: config_dev.yml
  production mode: config.yml

# 起動
1. アノテーションされたデータを記録するデータベース・サーバを起動する．

%mongod --dbpath ./db/

2. 別ターミナルでsinatraを起動

%ruby config.ru


# 作業をする
ウェブブラウザでsinatraアプリケーションにアクセス
http://localhost:4567/
