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

* JAVA_HOMEを設定します。

```
$ export JAVA_HOME=/usr/lib/jvm/jre-1.8.0-openjdk-1.8.0.222.b10-0.el7_6.x86_64
$ export PATH=$JAVA_HOME/bin:$PATH
```

* dockerグループにjaegerユーザを追加。extして再度ログイン。

```shell
$ sudo usermod -g docker jaeger
$ sudo /bin/systemctl restart docker.service

$ exit
```

* Jaegerの準備
以下を実行します

```shell
$ docker run -d --name jaeger \
    -p 6831:6831/udp \
    -p 16686:16686 \
    -p 14268:14268 \
    jaegertracing/all-in-one:1.6
```

http://localhost:16686
へアクセスしてJaegerへの接続を確認します。
NSXICの場合はポート転送が必要になりますので適宜設定下さい。

* gitにプロキシ設定を追加

```shell
$ git config --global http.proxy https://btw01_pid230:btw01_pass@192.168.190.241:9000
$ git config --global https.proxy https://btw01_pid230:btw01_pass@192.168.190.241:9000
```

* 演習アプリケーションをローカルにコピー

```shell
$ git clone https://github.com/nobuking/tracing-workshop0819.git
```

* maven のプロキシを設定します。
https://maven.apache.org/guides/mini/guide-proxies.html


## 本ワークショップの内容

* [Chapter01:OpenTracingの計測基礎](./Chapter01)
* [Chapter02:非同期アプリケーションの計測](./Chapter02)
* [Chapter03:サービスメッシュでのトレーシング](./Chapter03)
* [Chapter04:メトリックやログとの統合](./Chapter04)

