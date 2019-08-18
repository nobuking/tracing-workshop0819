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

* maven のプロキシを設定します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java/.mvn
$ cat <<EOF > jvm.config
-Dhttp.proxyHost=192.168.190.241
-Dhttp.proxyPort=9000
-Dhttp.proxyUser=btw01_pid230
-Dhttp.proxyPassword=btw01_pass
-Dhttps.proxyHost=192.168.190.241
-Dhttps.proxyPort=9000
-Dhttps.proxyUser=btw01_pid230
-Dhttps.proxyPassword=btw01_pass
-Djdk.http.auth.tunneling.disabledSchemes=
EOF
$ cd ~/.m2
$ cat <<EOF > settings.xml
<settings>
  <proxies>
   <proxy>
      <id>btw01></id>
      <active>true</active>
      <protocol>http</protocol>
      <host>192.168.190.241</host>
      <port>9000</port>
      <username>btw01_pid230</username>
      <password>btw01_pass</password>
      <nonProxyHosts></nonProxyHosts>
    </proxy>
  </proxies>
</settings>
EOF
```


## 本ワークショップの内容

* [Chapter01:OpenTracingの計測基礎](./Chapter01)
* [Chapter02:非同期アプリケーションの計測](./Chapter02)
* [Chapter03:サービスメッシュでのトレーシング](./Chapter03)
* [Chapter04:メトリックやログとの統合](./Chapter04)

