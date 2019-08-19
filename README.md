# 分散トレーシングワークショップ 

## 前提
このワークショップで用いるコードは、Mastering Distributed Tracingという書籍からのものを一部加工して利用しています。

## 環境事前準備
NSXICのOpenStack環境を利用します。
下記に参加者ごとのマシン割当を記載しているので確認して踏み台サーバ経由で接続してください。

<https://sysrdc.app.box.com/file/502061380587>

* 踏み台サーバへ接続する

ホスト： 172.30.210.249
ポート； 13122
アカウント： 上記boxの通り
パスワード：　ユーザー名と同じ

* ワークショップ用マシンへjaegerユーザで接続する

```shell
$ ssh jaeger@192.168.153.xx
```

* JDKの導入
JDK 1.8以上をインストールします。

```
$ sudo yum install -y java-1.8.0-openjdk-devel
```

* JAVA_HOMEを設定します。

```
$ export JAVA_HOME=/usr/lib/jvm/java-openjdk
$ export PATH=$JAVA_HOME/bin:$PATH
```

* jaegeユーザにdockerコマンドの実行権限を付与

```shell
$ sudo usermod -g docker jaeger
$ sudo /bin/systemctl restart docker.service

$ exit
```

* Jaegerコンテナの起動

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

* treeコマンドのインストール

```shell
$ sudo yum -y install tree
```


## 本ワークショップの内容

* [Chapter01:OpenTracingの計測基礎](./Chapter01)
* [Chapter02:非同期アプリケーションの計測](./Chapter02)
* [Chapter03:サービスメッシュでのトレーシング](./Chapter03)
* [Chapter04:メトリックやログとの統合](./Chapter04)

