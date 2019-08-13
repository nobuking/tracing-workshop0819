# Chapter01: OpenTracingでの計測基礎

## 内容
この章では簡単なアプリケーションを通じて基本的なトレースの実装方法について学習します。

* Exercise 1: The Hello applicationアプリケーションの説明
* Exercise 2: 最初のトレースを取得する
* Exercise 3: 個々の関数のトレースと複数Spanを1つのトレースに統合する
  * 3a) 個々の関数をトレースする
  * 3b) 処理中のコンテキストを伝播させる
* Exercise 4: 複数プロセス間のトレース
  * 4a) モノリスをマイクロサービスへ変更する
  * 4b) プロセス間のコンテキスト伝播
  * 4c) OpenTracing推奨タグを付与する
* Exercise 5: baggageを利用する
* Exercise 6: オープンソースの自動トレースを適用する

## 環境の準備
* Chapter01の環境に移動します。

```
$ cd .../tracing-workshop0819/Chapter01/java
```

* MySQLを起動します。

```
$ docker run -d --name mysql56 -p 3306:3306 -e MYSQL_ROOT_PASSWORD=mysqlpwd mysql:5.6
$ docker logs mysql56 | tail -2
```
2018-xx-xx 20:01:17 1 [Note] mysqld: ready for connections. 
みたいなログを確認できればOK

* MySQLのテーブルを作成する。

```
$ docker exec -i mysql56 mysql -uroot -pmysqlpwd < ../database.sql
Warning: Using a password on the command line interface can be insecure.
```

* mvnwを使って学習に必要なJavaアプリケーションを構築します。

```
$ ./mvnw install
```

BUILD SUCCESSって出ればOK!

## Exercise 1: The Hello applicationアプリケーションの説明
* 概要の説明
本アプリケーションはSpring Bootで作られたHelloアプリケーションです。
/sayHello/{name} エンドポイントにGETでHTTPアクセスすると、内部でJPAアダプタを利用してMySQLにアクセスし簡単なレスポンスを返します。

nameはMySQLに存在したものだけ有効です。
.../tracing-workshop0819/Chapter01にあるdatabase.sql文に記載した名前が対象です。

今度の演習ではMavenラッパーを利用することで演習間のmain classを切り替えてビルド・起動します。

pom.xmlの中にopentracing-spring-cloud-starterが含まれていますが演習6まではコメントを解除しないようにお願いします。

* exercise1用のmain classでサンプルアプリケーションを起動します。

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

## Exercise 2: 最初のトレースを取得する
この演習では演習1で起動したアプリケーションにJaegerトレーサーを実装します。

トレーサーはシングルトンとしてアプリケーションごとに1つのトレーサーとして利用します。

* Step1: HelloApp.javaにトレーサーを組み込みます
HelloApp.java内に以下をコピペします。
Beanとして宣言し、DIによって他の場所から呼べるようにしておきます。

```
 @Bean
    public io.opentracing.Tracer initTracer() {
        SamplerConfiguration samplerConfig = new SamplerConfiguration()
             .withType('const').withParam(1); //全てのトレースをサンプリングする
        ReporterConfiguration reporterConfig = 
              new ReporterConfiguration().withLogSpans(true); //全てのSspanログを作成する
        return new Configuration('java-2-hello')
             .withSampler(samplerConfig)
             .withReporter(reporterConfig)
             .getTracer(); //'java-2-hello'というサービス名、サンプラーはsamplerConfigを利用、レポーターはreporterConfigを利用、Tracerインスタンス生成
    }
```

* Step2: spanを開始する
トレースを取得するには少なくとも1つ以上のSpanが必要です。

アプリケーションが処理するHTTP要求ごとに新しいトレースを作成するため、トレース用のコードをHTTPハンドラー関数に追加します。

Spanを開始する度に"operation name"を付与する必要があります。Operation nameは後でトレースを分析する際に役に立ちます。同じレイヤで処理したSpanはそのOperation nameで集約をするため、カーディナリティは低くしなければなりません。

今回の演習では /sayHello/{name} 部分の sayHelloが固定なのでこれをoperation nameとしsay-helloとします。

Spanは必ず開始と終了のタイムスタンプを持ちます。明示的に終了をしないとバックエンドにSpanが報告されない可能性があります。

Spanにアノテーション（注釈）をつけます。Spanはその操作が何を表しているのか説明可能になっていなければなりません。

例えば、開発者は以下の情報があると助かります。
 - サーバのリモートアドレス
 - アクセスしたデータベースのID
 - 例外やスタックトレース
 - アクセスしたアカウント名
 - DBから取得したレコード数

タグとログでアノテーションできます。
タグはスパン全体に適用されるキー、値のペアで、主にトレースデータのフィルタに利用される。
ログはポイントインタイムイベントでSpan内での特定時点のイベントを表します。


HelloController.javaを以下のように修正します。

```
(略)
@RestController
public class HelloController {

    @Autowired
    private PersonRepository personRepository;

    @Autowired
    private Tracer tracer; //Tracerイングルトンにアクセス

    @GetMapping("/sayHello/{name}")
    public String sayHello(@PathVariable String name) {
        Span span = tracer.buildSpan("say-hello").start(); //Spanを開始
        try {         //例外でもSpanが常に終了するためにtry-finallyを利用
            Person person = getPerson(name);
            Map<String, String> fields = new LinkedHashMap<>();
            fields.put("name", person.getName());
            fields.put("title", person.getTitle());
            fields.put("description", person.getDescription());
            span.log(fields); //spanにLogを挿入

            String response = formatGreeting(person);
            span.setTag("response", response); //spanにTagを付与

            return response;
        } finally {
            span.finish(); //Spanを終了
        }
    }
(略)
```

* これらを実装したHelloアプリケーションをビルドし起動します。
修正したexercise1をビルドし直しても結果は同じです。

```
$ ./mvnw spring-boot:run -Dmain.class=exercise2.HelloApp
```

* curl で何度かアクセスします。

```
$ curl http://localhost:8080/sayHello/Gru
$ curl http://localhost:8080/sayHello/Nefario
```

* Jaegerバックエンドにブラウザでアクセスして結果を確認します。


## Exercise 3: 個々の関数のトレースと複数Spanを1つのトレースに統合する
演習2ではHTTP要求全体に対してSpanを生成していたため、例えばDB部分のアクセスにどれくらいの時間がかかったかわかりません。

この演習では関数ごとにSpanを生成しそれを1つのトレースとして統合します。

### 3a) 個々の関数をトレースする
DBの読み取りと挨拶のフォーマット生成の関数にSpanを追加します。

しかし演習2と同じようにSpanを生成するだけだと、トレースIDがそれぞれ発行されトレースがまとめられません。

なので、Span間の関係を設定してあげる必要があります。

なお、演習3ではDBアクセスはOR Mapperを利用しているため、SQLステートメントは見えません。

HelloController.java内のgetPerson関数とformatGreeting関数を以下のように修正します。

```
    private Person getPerson(String name, Span parent) {
        Span span = tracer.buildSpan("get-person").asChildOf(parent).start(); //Span開始
        try {
            Optional<Person> personOpt = personRepository.findById(name);
            if (personOpt.isPresent()) {
                return personOpt.get();
            }
            return new Person(name);
        } finally {
            span.finish(); //Span終了
        }
    }
```

```
    private String formatGreeting(Person person, Span parent) {
        Span span = tracer.buildSpan("format-greeting").asChildOf(parent).start(); //Span開始
        try {
            String response = "Hello, ";
            if (!person.getTitle().isEmpty()) {
                response += person.getTitle() + " ";
            }
            response += person.getName() + "!";
            if (!person.getDescription().isEmpty()) {
                response += " " + person.getDescription();
            }
            return response;
        } finally {
            span.finish(); //Span終了
        }
    }
```

* これらを実装したHelloアプリケーションをビルドし起動します。
修正したコードをビルドし直しても結果は同じです。

```
$ ./mvnw spring-boot:run -Dmain.class=exercise3a.HelloApp
```

* curl で何度かアクセスします。

```
$ curl http://localhost:8080/sayHello/Gru
$ curl http://localhost:8080/sayHello/Nefario
```

* Jaegerバックエンドにブラウザでアクセスして結果を確認します。

### 3b) 処理中のコンテキストを伝播させる
正しくトレースが見えている状態になっていますが、Span間の関係を明示的に設定するのは特に大規模アプリケーションになると非現実的です。

OpenTracing API 0.31からこのような関係性を抽象化して実装できるScope Managerが実装されました。
Scope Managerを使うスレッド間でアクティブなSpanの関係性を自動的にまとめることができます。

演習3aのコードを以下のコードに修正します。

```
import io.opentracing.Scope; //Scopeをインポート
```

```
@RestController
public class HelloController {
        
    @Autowired
    private PersonRepository personRepository;
             
    @Autowired
    private Tracer tracer;
    
    @GetMapping("/sayHello/{name}") 
    public String sayHello(@PathVariable String name) {
        Span span = tracer.buildSpan("say-hello").start();
        try (Scope scope = tracer.scopeManager().activate(span, false)) { //scopeManager定義
            Person person = getPerson(name);
            Map<String, String> fields = new LinkedHashMap<>();
            fields.put("name", person.getName());
            fields.put("title", person.getTitle());
            fields.put("description", person.getDescription());
            span.log(fields);

            String response = formatGreeting(person);
            span.setTag("response", response);

            return response;
        } finally {
            span.finish();
        }
    }
```

```
 private Person getPerson(String name) {
        Span span = tracer.buildSpan("get-person").start();
        try (Scope scope = tracer.scopeManager().activate(span, false)) {
            Optional<Person> personOpt = personRepository.findById(name);
            if (personOpt.isPresent()) {
                return personOpt.get();
            }
            return new Person(name);
        } finally { 
            span.finish();
        }
    } 
```

```
private String formatGreeting(Person person) {
        Span span = tracer.buildSpan("format-greeting").start();
        try (Scope scope = tracer.scopeManager().activate(span, false)) {
            String response = "Hello, ";
            if (!person.getTitle().isEmpty()) { 
                response += person.getTitle() + " "; 
            } 
            response += person.getName() + "!";
            if (!person.getDescription().isEmpty()) {
                response += " " + person.getDescription();
            } 
            return response;
        } finally {
            span.finish();
        }
    }
```

* これらを実装したHelloアプリケーションをビルドし起動します。
修正したコードをビルドし直しても結果は同じです。

```
$ ./mvnw spring-boot:run -Dmain.class=exercise3b.HelloApp
```

* curl で何度かアクセスします。

```
$ curl http://localhost:8080/sayHello/Gru
$ curl http://localhost:8080/sayHello/Nefario
```

* Jaegerバックエンドにブラウザでアクセスして結果を確認します。


## Exercise 4: 複数プロセス間のトレース
演習3までは全て1つのプロセスで動くアプリケーションでした。
この演習では、Helloアプリケーションをマイクロサービス化した上で
マイクロサービス間の分散トレーシングを実装します。
またinject, extractの計測ポイントを利用してプロセス間でコンテキスト伝播を行います。

### 4a) モノリスをマイクロサービスへ変更する
以下の機能をマイクロサービス化します。
- データベースから個人の情報を取得する機能を BigBrotherサービスに
- 挨拶のフォーマットを行う機能を Formatterサービスに

BigBrotherサービスはポート8081でリッスンし、getPersonというエンドポイントを持ちます。
パス・パラメーターとして個人の名前を受け取り個人に関する情報をJSONとして返します。

```
$ curl http://localhost:8081/getPerson/Gru
{"Name":"Gru","Title":"Felonius","Description":"Where are the minions?"}
```

Formatterサービスはポート8082でリッスンし、formatGreetingというエンドポイントを持ちます。
URL問い合わせパラメータとしてエンコードされたname、title、descriptionの3つのパラメータを受け取り、プレーン・テキスト文字列で応答します。

```
$ curl 'http://localhost:8082/formatGreeting?name=Smith&title=Agent'
Hello, Agent Smith!
```

* exercice4aのコードを確認します。

```
$ cd .../tracing-workshop0819-mywork/Chapter01/java/src/main/java/exercise4a
$ tree .
.
├── HelloApp.java
├── HelloController.java
├── bigbrother
│   ├── BBApp.java
│   └── BBController.java
└── formatter
    ├── FApp.java
    └── FController.java
```

HelloControllerはまだ同じgetPerson()関数とformatGreeting()関数を持っていますが、それらは2つの新しいサービス（exercise4a.bigbrotherとexercise4a.formatterパッケージの中にある）に対してauto-injectされるSpringのRestTemplateを使って、HTTPリクエストを実行します。



### 4b) プロセス間のコンテキスト伝播
### 4c) OpenTracing推奨タグを付与する
## Exercise 5: baggageを利用する
## Exercise 6: オープンソースの自動トレースを適用する
