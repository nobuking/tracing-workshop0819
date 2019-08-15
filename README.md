# 分散トレーシングワークショップ 

## 前提
このワークショップで用いるコードは、Mastering Distributed Tracingという書籍からのものを一部加工して利用しています。

## 環境事前準備
* マシンへの接続
NSXICのOpenStack環境を利用します。
下記に参加者ごとのマシン割当を記載しているので確認して踏み台サーバ経由で接続してください。

<https://sysrdc.app.box.com/file/502061380587>

* JDKの準備
JDK 1.8以上をインストールします。

```
$ sudo yum install java-1.8.0-openjdk
```
* dockerグループにjaegerユーザを追加。extして再度ログイン。

```
$ sudo usermod -g docker jaeger
$ sudo /bin/systemctl restart docker.service

$ exit
```

* Jaegerの準備
以下を実行します

```
$ docker run -d --name jaeger \
    -p 6831:6831/udp \
    -p 16686:16686 \
    -p 14268:14268 \
    jaegertracing/all-in-one:1.6
```

http://localhost:16686
へアクセスしてJaegerへの接続を確認します。
NSXICの場合はポート転送が必要になりますので適宜設定下さい。

* 演習アプリケーションをローカルにコピー

```
$ git clone https://github.com/nobuking/tracing-workshop0819.git
```


## 本ワークショップの内容

* [Chapter01:OpenTracingの計測基礎](./Chapter01)
* [Chapter02:非同期アプリケーションの計測](./Chapter02)
* [Chapter03:サービスメッシュでのトレーシング](./Chapter03)
* [Chapter04:メトリックやログとの統合](./Chapter04)

