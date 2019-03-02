# Lesson 1 - Hello World

## Objectives

Learn how to:

* Instantiate a Tracer
* Create a simple trace
* Annotate the trace

## Walkthrough

### A simple Hello-World program

Let's create a simple Ruby program `lesson01/exercise/hello.rb` that takes an argument and prints "Hello, #{arg}!".

```
mkdir lesson01/exercise
touch lesson01/exercise/hello.rb
```

```ruby
# lesson01/exercise/hello.rb

def say_hello(hello_to)
  hello_str = "Hello, #{hello_to}!"
  puts hello_str
end

raise ArgumentError, 'Expecting one argument' unless ARGV.count == 1

hello_to = ARGV[0]
say_hello(hello_to)
```

Run it:
```
$ ruby lesson01/exercise/hello.rb Bryan
Hello, Bryan!
```

### Create a trace

A trace is a directed acyclic graph of spans. A span is a logical representation of some work done in your application.
Each span has these minimum attributes: an operation name, a start time, and a finish time.

Let's create a trace that consists of just a single span. To do that we need an instance of the `OpenTracing::Tracer`.
We can use a global instance stored in `OpenTracing.global_tracer`.

```ruby
require 'opentracing'

OpenTracing.global_tracer = OpenTracing::Tracer.new

def say_hello(hello_to)
  span = OpenTracing.start_span('say-hello')
  hello_str = "Hello, #{hello_to}!"
  puts hello_str
  span.finish
end
```

We are using the following basic features of the OpenTracing API:
  * a `Tracer` instance is used to start new spans via the `start_span` method
  * each `span` is given an _operation name_, `'say-hello'` in this case
  * each `span` must be finished by calling its `finish` method
  * the start and end timestamps of the span will be captured automatically by the tracer implementation

However, there's two issues with the above example: 
1. In an application there can be many spans and we want our span to be the "active" one.
2. It's a bit tedious to close the span manually, we take advantage Ruby's blocks to group statements and have the span automatically finish.

The block form of `start_active_span' fixes both issues:

```ruby
def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello') do |scope|
    hello_str = "Hello, #{hello_to}!"
    puts hello_str
  end
end
```

If we run this program, we will see no difference, and no traces in the tracing UI.
That's because `OpenTracing.global_tracer` points to a no-op tracer by default.

### Initialize a real tracer

Let's create an instance of a real tracer, such as [Jaeger](https://github.com/salemove/jaeger-client-ruby).

```ruby
require 'jaeger/client'
require 'time'

def init_tracer(service)
	Jaeger::Client.build(
		host: 'localhost', 
		service_name: service,
		reporter: Jaeger::Reporters::LoggingReporter.new
	)
end
```

To use this instance, let's replace `OpenTracing.global_tracer` with `init_tracer(...)`:

```ruby
OpenTracing.global_tracer = init_tracer('hello-world')
```

Note that we are passing a string `'hello-world'` to the init method. It is used to mark all spans emitted by
the tracer as originating from a `hello-world` service:

```ruby

# set a short `flush_interval` (the default is 10)
def init_tracer(service)
  Jaeger::Client.build(
    host: 'localhost', 
    service_name: service,
    reporter: Jaeger::Reporters::LoggingReporter.new
  )
end
```

The complete program should now look like:

```ruby
require 'opentracing'
require 'jaeger/client'
require 'time'

def init_tracer(service)
  Jaeger::Client.build(
    host: 'localhost',
    service_name: service,
    reporter: Jaeger::Reporters::LoggingReporter.new
  )
end

OpenTracing.global_tracer = init_tracer('hello-world')

def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello') do |scope|
    hello_str = "Hello, #{hello_to}!"
    puts hello_str
  end
end

raise ArgumentError, 'Expecting one argument' unless ARGV.count == 1

hello_to = ARGV[0]
say_hello(hello_to)
```

If we run the program now, we should see a span logged:

```
$ bundle exec ruby lesson01/exercise/hello.rb Bryan
Hello, Bryan!
I, [2019-03-02T11:03:44.192442 #512]  INFO -- : Span reported: {:operation_name=>"say-hello", :start_time=>"2019-03-02T11:03:44-08:00", :end_time=>"2019-03-02T11:03:44-08:00", :trace_id=>"b01f2f524ad470c8", :span_id=>"b01f2f524ad470c8"}
```

If you have Jaeger backend running, you may be confused as to why spans are not being recorded in our sample thus far.
This is because we're using `Jaeger::Reporters::LoggingReporter`, rather than one of the remote reporters.
There are two remote reporters the client can use, the default `UdpSender` or the `HttpSender`. 
To use the default reporter we can remove the `reporter:` from the client's configuration:


In addition since the Jaeger Tracer is primarily designed for long-running server processes,
it has an internal buffer of spans that is flushed in the background. Since our program exists immediately,
it may not have time to flush the spans to Jaeger backend. We'll lower the default flush interval and sleep for two seconds
to ensure it has time to flush the spans:

```ruby
def init_tracer(service)
  Jaeger::Client.build(
    host: 'localhost',
    service_name: service,
    flush_interval: 1
  )
end

# ...
 
sleep 2
```

The complete program should now look like:

```ruby
require 'opentracing'
require 'jaeger/client'
require 'time'

def init_tracer(service)
  Jaeger::Client.build(
    host: 'localhost',
    service_name: service,
    flush_interval: 1
  )
end

OpenTracing.global_tracer = init_tracer('hello-world')

def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello') do |scope|
    hello_str = "Hello, #{hello_to}!"
    puts hello_str
  end
end

raise ArgumentError, 'Expecting one argument' unless ARGV.count == 1

hello_to = ARGV[0]
say_hello(hello_to)

sleep 2
```

A local version of the Jaeger stack, including the backend and the UI, can be run via docker in another terminal:

```bash
$ docker run -d -e COLLECTOR_ZIPKIN_HTTP_PORT=9411 -p5775:5775/udp -p6831:6831/udp -p6832:6832/udp \
    -p5778:5778 -p16686:16686 -p14268:14268 -p9411:9411 jaegertracing/all-in-one:latest
```

Now when we run our program spans will be sent to the backend:

```bash
$ bundle exec ruby lesson01/exercise/hello.rb Bryan
```

### Annotate the Trace with Tags and Logs

Right now the trace we created is very basic. If we call our program with argument `Susan`
instead of `Bryan`, the resulting traces will be nearly identical. It would be nice if we could
capture the program arguments in the traces to distinguish them.

One naive way is to use the string `"Hello, Bryan!"` as the _operation name_ of the span, instead of `"say-hello"`.
However, such practice is highly discouraged in distributed tracing, because the operation name is meant to
represent a _class of spans_, rather than a unique instance. For example, in Jaeger UI you can select the
operation name from a dropdown when searching for traces. It would be very bad user experience if we ran the
program to say hello to a 1000 people and the dropdown then contained 1000 entries. Another reason for choosing
more general operation names is to allow the tracing systems to do aggregations. For example, Jaeger tracer
has an option of emitting metrics for all the traffic going through the application. Having a unique
operation name for each span would make the metrics useless.

The recommended solution is to annotate spans with tags or logs. A _tag_ is a key-value pair that provides
certain metadata about the span. A _log_ is similar to a regular log statement, it contains
a timestamp and some data, but it is associated with span from which it was logged.

When should we use tags vs. logs?  The tags are meant to describe attributes of the span that apply
to the whole duration of the span. For example, if a span represents an HTTP request, then the URL of the
request should be recorded as a tag because it does not make sense to think of the URL as something
that's only relevant at different points in time on the span. On the other hand, if the server responded
with a redirect URL, logging it would make more sense since there is a clear timestamp associated with such
event. The OpenTracing Specification provides guidelines called [Semantic Conventions][semantic-conventions]
for recommended tags and log fields.

#### Using Tags

In the case of `hello Bryan`, the string "Bryan" is a good candidate for a span tag, since it applies
to the whole span and not to a particular moment in time. We can record it like this:

```ruby
def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello', tags: { hello_to: hello_to }) do |scope|
    hello_str = "Hello, #{hello_to}!"
    puts hello_str
  end
end
```

Alternatively you can set a tag via `scope.span`:

```ruby
def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello', tags: { hello_to: hello_to }) do |scope|
    scope.span.set_tag('hello_to', hello_to)
    hello_str = "Hello, #{hello_to}!"
    puts hello_str
  end
end
```

#### Using Logs

Our hello program is so simple that it's difficult to find a relevant example of a log, but let's try.
Right now we're formatting the `hello_str` and then printing it. Both of these operations take certain
time, so we can log their completion:

```ruby
hello_str = "Hello, #{hello_to}!"
scope.span.log_kv(event: hello_str)

puts hello_str
scope.span.log_kv(event: 'print line')
```

The log statements might look a bit strange if you have not previosuly worked with a structured logging API.
Rather than formatting a log message into a single string that is easy for humans to read, structured
logging APIs encourage you to separate bits and pieces of that message into key-value pairs that can be
automatically processed by log aggregation systems. The idea comes from the realization that today most
logs are processed by machines rather than humans. Just [google "structured-logging"][google-logging]
for many articles on this topic.

The OpenTracing API for Ruby exposes structured logging API method `log_kv` that takes a dictionary
of key-value pairs.

The OpenTracing Specification also recommends all log statements to contain an `event` field that
describes the overall event being logged, with other attributes of the event provided as additional fields.

If you run the program with these changes, then find the trace in the UI and expand its span (by clicking on it),
you will be able to see the tags and logs.

## Conclusion

The complete program can be found in the [solution](./solution) package. We created a classs and moved the `init_tracer`
helper method into a module so that we can user it in the other lessons.

Next lesson: [Context and Tracing Functions](../lesson02).

[semantic-conventions]: https://github.com/opentracing/specification/blob/master/semantic_conventions.md
[google-logging]: https://www.google.com/search?q=structured-logging
