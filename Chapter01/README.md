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
* Exercise 5: baggageを利用する
* Exercise 6: オープンソースの自動トレースを適用する

## 環境の準備
* Chapter01の環境に移動します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
```

* MySQLを起動します。

```shell
$ docker run -d --name mysql56 -p 3306:3306 -e MYSQL_ROOT_PASSWORD=mysqlpwd mysql:5.6
$ docker logs mysql56 | tail -2
```
MySQL init process done. Ready for start up.
というログを確認すること。

* MySQLのテーブルを作成する。

```shell
$ docker exec -i mysql56 mysql -uroot -pmysqlpwd < ../database.sql
Warning: Using a password on the command line interface can be insecure.
```

* mvnwを使って学習に必要なJavaアプリケーションを構築します。

```shell
$ ./mvnw install
```

Exception in thread "main" java.net.UnknownHostException: repo.maven.apache.org
って出て失敗します。

* 失敗するのでmavenのプロキシを設定します。

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

* もう一度mvnw installを実行します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java/
$ ./mvnw install
```

BUILD SUCCESSって出ればOK!

## Exercise 1: The Hello applicationアプリケーションの説明
* 概要の説明

本アプリケーションはSpring Bootで作られたHelloアプリケーションです。
/sayHello/{name} エンドポイントにGETでHTTPアクセスすると、内部でJPAアダプタを利用してMySQLにアクセスし簡単なレスポンスを返します。
nameはMySQLに存在したものだけ有効です。
/home/jaeger/tracing-workshop0819/Chapter01にあるdatabase.sql文に記載した名前が対象です。

ディレクトリ構造は以下のコマンドで確認できます。

```shell
$ tree -A /home/jaeger/tracing-workshop0819/Chapter01
```

今度の演習ではMavenラッパーを利用することで演習間のmain classを切り替えてビルド・起動します。

pom.xmlの中にopentracing-spring-cloud-starterが含まれていますが演習6まではコメントを解除しないようにお願いします。

* exercise1用のmain classでサンプルアプリケーションを起動します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise1.HelloApp
[... a lot of logs ...]
INFO 57474 --- [main] exercise1.HelloApp: Started HelloApp in 3.844 seconds
```

* アプリケーションが起動したことを確認する。

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
Hello, Felonius Gru! Where are the minions?
```

## Exercise 2: 最初のトレースを取得する
この演習では演習1で起動したアプリケーションにJaegerトレーサーを実装します。

トレーサーはシングルトンとしてアプリケーションごとに1つのトレーサーとして利用します。

* exercise1 ディレクトリに移動します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java/src/main/java/exercise1
$ ls -l
```

* Step1: HelloApp.javaにトレーサーを組み込みます

HelloApp.java内に以下をコピペします。
Beanとして宣言し、DIによって他の場所から呼べるようにしておきます。

```java
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

```java
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

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise2.HelloApp
```

* curl で何度かアクセスします。

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
$ curl --noproxy localhost http://localhost:8080/sayHello/Nefario
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

```java
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

```java
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

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise3a.HelloApp
```

* curl で何度かアクセスします。

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
$ curl --noproxy localhost http://localhost:8080/sayHello/Nefario
```

* Jaegerバックエンドにブラウザでアクセスして結果を確認します。

### 3b) 処理中のコンテキストを伝播させる
正しくトレースが見えている状態になっていますが、Span間の関係を明示的に設定するのは特に大規模アプリケーションになると非現実的です。

OpenTracing API 0.31からこのような関係性を抽象化して実装できるScope Managerが実装されました。
Scope Managerを使うスレッド間でアクティブなSpanの関係性を自動的にまとめることができます。

演習3aのコードを以下のコードに修正します。

```java
import io.opentracing.Scope; //Scopeをインポート
```

```java
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

```java
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

```java
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

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise3b.HelloApp
```

* curl で何度かアクセスします。

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
$ curl --noproxy localhost http://localhost:8080/sayHello/Nefario
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

```shell
$ curl --noproxy localhost http://localhost:8081/getPerson/Gru
{"Name":"Gru","Title":"Felonius","Description":"Where are the minions?"}
```

Formatterサービスはポート8082でリッスンし、formatGreetingというエンドポイントを持ちます。
URL問い合わせパラメータとしてエンコードされたname、title、descriptionの3つのパラメータを受け取り、プレーン・テキスト文字列で応答します。

```shell
$ curl --noproxy localhost 'http://localhost:8082/formatGreeting?name=Smith&title=Agent'
Hello, Agent Smith!
```

* exercice4aのコードを確認します。

```shell
$ cd /home/jaeger/tracing-workshop0819-mywork/Chapter01/java/src/main/java/exercise4a
$ tree -A .
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

各サブパッケージにはAppクラス(BBAppとFApp)とコントローラクラスがあります。すべてのAppクラスは、トレース内のサービスを分離できるように、固有の名前を持つ独自のトレーサーをインスタンス化します。JPAアノテーションはデータベースにアクセスする唯一のアノテーションであるため、HelloAppからBBAppに移動されます。2つの新しいサービスを異なるポートで実行する必要があるため、それぞれがサーバを上書きします。

* HelloApp.java, BBApp.java, FApp.java, HelloController.java, BBController.java, FController.javaのコードを確認します。


* HelloApp, BBApp, FAppを起動します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise4a.bigbrother.BBApp
$ ./mvnw spring-boot:run -Dmain.class=exercise4a.formatter.FApp
$ ./mvnw spring-boot:run -Dmain.class=exercise4a.HelloApp
```

* curl でエンドポイントにアクセスしてみて下さい。

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
```

* Jaegerでjava-4-*というサービス名でトレースを確認してみて下さい。

上記で確認すると、各マイクロサービスのトレースがそれぞれ表示されていて一つのトレースとして見えていないと思います。

この段階では、Jaegerはこれらのトレースが一連のトランザクションと認識できていません。プロセス間でコンテキストを伝播させる設定がないからです。


### 4b) プロセス間のコンテキスト伝播
Javaの場合、HTTPヘッダを表現するための標準的な規約がないため、TracedControllerクラスを定義して、他のControllerクラスにてTracedControllerクラスを継承して使います。

まずはTracedControllerクラスのコードを確認します。

```java
public class TracedController {
    @Autowired
    protected Tracer tracer;

    /**
    * コントローラ内のHTTPハンドラによって実装される受信HTTP要求に対して、get()の逆を実行するstartServerSpan()メソッドを実装します。このメソッドは、spanコンテキストをヘッダーから抽出し、新しいサーバー側のspanを起動するときにそれを親として渡します。
    */
    protected Span startServerSpan(String operationName, HttpServletRequest request) { //startServerSpanメソッドを定義
        HttpServletRequestExtractAdapter carrier = new HttpServletRequestExtractAdapter(request);
        SpanContext parent = tracer.extract(Format.Builtin.HTTP_HEADERS, carrier);
        Span span = tracer.buildSpan(operationName).asChildOf(parent).start();
        Tags.SPAN_KIND.set(span, Tags.SPAN_KIND_SERVER);
        return span;
    }

    /**
     * 送信HTTP要求の実行に使用されます。トレース・コンテキストを要求ヘッダーに注入する必要があるため、SpringのHttpHeadersオブジェクトを使用し、それをアダプター・クラスHttpHeaderInjectAdapterにラップして、OpenTracingのTextMapインターフェースの実装のようにします。
     */
    protected <T> T get(String operationName, URI uri, Class<T> entityClass, RestTemplate restTemplate) {  //getメソッドを定義
        Span span = tracer.buildSpan(operationName).start();
        try (Scope scope = tracer.scopeManager().activate(span, false)) {
            Tags.SPAN_KIND.set(span, Tags.SPAN_KIND_CLIENT);
            Tags.HTTP_URL.set(span, uri.toString());
            Tags.HTTP_METHOD.set(span, "GET");

            HttpHeaders headers = new HttpHeaders();
            HttpHeaderInjectAdapter carrier = new HttpHeaderInjectAdapter(headers);
            tracer.inject(span.context(), Format.Builtin.HTTP_HEADERS, carrier);
            HttpEntity<String> entity = new HttpEntity<>(headers);
            return restTemplate.exchange(uri, HttpMethod.GET, entity, entityClass).getBody();
        } finally {
            span.finish();
        }
    }

    private static class HttpServletRequestExtractAdapter implements TextMap {
        private final Map<String, String> headers;

        HttpServletRequestExtractAdapter(HttpServletRequest request) {
            this.headers = new LinkedHashMap<>();
            Enumeration<String> keys = request.getHeaderNames();
            while (keys.hasMoreElements()) {
                String key = keys.nextElement();
                String value = request.getHeader(key);
                headers.put(key, value);
            }
        }

        @Override
        public Iterator<Entry<String, String>> iterator() {
            return headers.entrySet().iterator();
        }

        @Override
        public void put(String key, String value) {
            throw new UnsupportedOperationException();
        }
    }

    private static class HttpHeaderInjectAdapter implements TextMap {
        private final HttpHeaders headers;

        HttpHeaderInjectAdapter(HttpHeaders headers) {
            this.headers = headers;
        }
        @Override
        public Iterator<Entry<String, String>> iterator() {
            throw new UnsupportedOperationException();
        }

        @Override
        public void put(String key, String value) {
            headers.set(key, value);
        }
    }

}
```

また、OpenTracing推奨のタグであるSpan.kind, http.url, http.methodを使用しています。

* exercie4bのコードをもとにアプリケーションを起動してみます。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise4b.bigbrother.BBApp
$ ./mvnw spring-boot:run -Dmain.class=exercise4b.formatter.FApp
$ ./mvnw spring-boot:run -Dmain.class=exercise4b.HelloApp
```

* curlでアプリケーションのエンドポイントにアクセスします。 

```shell
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
```

今度はJaeger上で一つのトレース見えているはずです。

## Exercise 5: baggageを利用する
演習4までで、トレースの基本的な実装は完了しています。

演習5ではBaggage ItemというOpenTracingの持つもうひとつの機能について演習します。

演習4でわかった通り、OpenTracingではTraceidなどの分散トレーシングのメタデータをプロセス間で伝播させることができます。
Baggage Itemはこれを分散トレーシングメタデータ固有のものではなく、トランザクションに任意のデータを渡すための概念です。
（TagやLogはあくまでもSpan内の情報に閉じています。）

Baggage Itemをうまく使うことで前回の解説編でお伝えしたように様々なユースケースに分散トレーシングを応用できます。
というか、Baggage Itemをうまく使うことが分散トレーシングの本質的な価値かも
しれません。

この演習では、FormatterサービスのFormatGreeting()関数を変更し、greetingという名前のbaggage項目からgreetingという単語を読み取ります。そのbaggage項目が設定されていない場合は、引き続きデフォルトの単語を使用します。

* exercice5のFController.javaを確認します。

```java
 @GetMapping('/formatGreeting')
    public String formatGreeting(
            @RequestParam String name, 
            @RequestParam String title,
            @RequestParam String description, 
            HttpServletRequest request) 
    {
        Scope scope = startServerSpan('/formatGreeting', request);
        try {
            String greeting = tracer
                .activeSpan().getBaggageItem('greeting');
            if (greeting == null) {
                greeting = 'Hello';
            }
            String response = greeting + ', ';
            ...
            return response;
        finally {
            scope.close();
        }
    }
(略)
```

JaegerのgetBaggageItemメソッドはkeyがgreetingである値を取得します。

* exercie5のコードをもとにアプリケーションを起動してみます。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise5.bigbrother.BBApp
$ ./mvnw spring-boot:run -Dmain.class=exercise5.formatter.FApp
$ ./mvnw spring-boot:run -Dmain.class=exercise5.HelloApp
```

* 以下を実行します。

```shell
$ curl --noproxy localhost -H 'jaeger-baggage: greeting=Bonjour'  http://localhost:8080/sayHello/Kevin
Bonjour, Kevin!
```

* Jaegerでトレースを見てみてください。

## Exercise 6: オープンソースの自動トレースを適用する
演習6では、OpenTracing contribで提供されているopentracing-spring-cloud-starterを使って計測コードなしでトレースを可能にする方法を体験します。

* pom.xmlのコメントアウトされている部分を解除します。

```xml
 <dependency>
     <groupId>io.opentracing.contrib</groupId>
     <artifactId>opentracing-spring-cloud-starter</artifactId>
     <version>0.1.13</version>
 </dependency>
```

* excrcise6のコードでアプリケーションを起動します。

```shell
$ cd /home/jaeger/tracing-workshop0819/Chapter01/java
$ ./mvnw spring-boot:run -Dmain.class=exercise6.bigbrother.BBApp
$ ./mvnw spring-boot:run -Dmain.class=exercise6.formatter.FApp
$ ./mvnw spring-boot:run -Dmain.class=exercise6.HelloApp
$ curl --noproxy localhost http://localhost:8080/sayHello/Gru
```

* Jaegerでトレースを見てください。
ほとんどゼロタッチでトレースを取得することができました。
とはいえ、Spanを取得するための一部のコードは残されたままです。

java-traceresolver, java-spring-tracer-configuration, java-spring-jaegerなどのcontribを使用するとゼロタッチでトレースを取得することもできます。
これらは自学習用にしておくので試してみて下さい。

## 最後に
Spring BootによるJavaアプリケーションでのJaegerを用いた分散トレーシングを体験してもらいました。
自分たちのアプリケーションを理解して十分にJaegerに精通している場合は自前で実装することによるその強力さがわかるはずです。

一方、特にSIerの場合は、すでに完成されているアプリケーションに対して商用APMを用いて自動で分散トレーシングを行うことも強力なソリューションになりえます。
商用APMは自動でトレースコードを埋め込むだけではなく、そのバックエンドのUIも便利なものが多いです。
これらを理解して使い分けていくためにも手動による分散トレーシングの学習は有効なはずです。

ではこれにてChapter01は終わりにします。

Happy Tracing!!

