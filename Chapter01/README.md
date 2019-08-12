# Chapter01: OpenTracingでの計測基礎

## 環境の準備
* Chapter01配下の環境に移動します


* mvnwを使って学習に必要なJavaアプリケーションを構築します。

```
$ cd .../java
$ ./mvnw install
```

* すべての演習は同じモジュールで定義されているため、main()関数を定義する複数のクラスがあります。したがって、次のように、実行する主クラスをSpringに指定する必要があります。

```
$ ./mvnw spring-boot:run -Dmain.class=exercise1.HelloApp
[... a lot of logs ...]
INFO 57474 --- [main] exercise1.HelloApp: Started HelloApp in 3.844 seconds
```

* アプリケーションが起動したことを確認する。

```
$ curl http://localhost:8080/sayHello/Gru
Hello, Felonius Gru! Where are the minions?
```


## 環境の説明
* アプリケーションはSpring Bootフレームワーク (http://spring.io/projects/spring-boot)を使っています。アプリケーションをビルドして実行するためにMavenラッパーを使用しています。依存関係は、pom.xmlファイルに定義されており、Spring Boot用のアーティファクト、データベースにアクセスするためのJPAアダプタ、MySQLコネクション、そして最後にJaegerクライアントライブラリが含まれます。

* pom.xmlの中にopentracing-spring-cloud-starterが含まれていますが、Exercise 6まではコメントを解除しないこと。

* 

## 内容
この章では簡単なアプリケーションを通じて基本的なトレースの実装方法について学習します。

* Exercise 1: The Hello application
* Exercise 2: The first trace
* Exercise 3: Tracing functions and passing context
  * 3a) tracing individual functions
  * 3b) combining spans into a single trace
  * 3c) propagating context in-process
* Exercise 4: Tracing RPC requests
  * 4a) breaking up the monolith
  * 4b) passing context between processes
  * 4c) applying OpenTracing-recommended tags
* Exercise 5: Using "baggage"
* Exercise 6: Applying open-source auto-instrumentation
