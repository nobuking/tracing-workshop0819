# 分散トレーシングワークショップ 

## 前提
このワークショップで用いるコードは、Mastering Distributed Tracingという書籍からのものを一部加工して利用しています。

## 事前準備
* JDKの準備
JDK 1.8以上をインストールする

```
yum install openjdk
```

* MySQLの準備
dockerにてMySQL 5.6を起動する

```
$ docker run -d --name mysql56 -p 3306:3306 -e MYSQL_ROOT_PASSWORD=mysqlpwd mysql:5.6
$ docker logs mysql56 | tail -2
```
2018-xx-xx 20:01:17 1 [Note] mysqld: ready for connections. で出ればOK

ユーザー、パスワードを作成する

```
$ docker exec -i mysql56 mysql -uroot -pmysqlpwd < $CH04/database.sql
Warning: Using a password on the command line interface can be insecure.

```

* Jaegerの準備
以下を実行する

```
$ docker run -d --name jaeger \
    -p 6831:6831/udp \
    -p 16686:16686 \
    -p 14268:14268 \
    jaegertracing/all-in-one:1.6
```


## 本ワークショップの内容

* [Chapter01:OpenTracingの計測基礎](./Chapter01)
* [Chapter02:非同期アプリケーションの計測](./Chapter02))
* [Chapter03:サービスメッシュでのトレーシング](./Chapter03)
* [Chapter04:メトリックやログとの統合](./Chapter04)

