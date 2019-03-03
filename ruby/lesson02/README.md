# Lesson 2 - Context and Tracing Functions

## Objectives

Learn how to:

* Trace individual functions
* Combine multiple spans into a single trace
* Propagate the in-process context

## Walkthrough

First, copy your work or the official solution from [Lesson 1](../lesson01) to `lesson02/exercise/hello.rb`,
and make it a module by creating the `__init__.py` file:

```
mkdir lesson02/exercise
cp lesson01/solution/*.rb lesson02/exercise/
```

### Tracing individual functions

In [Lesson 1](../lesson01) we wrote a program that creates a trace that consists of a single span.
That single span combined two operations performed by the program, formatting the output string
and printing it. Let's move those operations into standalone methods first:

```ruby
class HelloWorld
  include Tracing

  def initialize
    OpenTracing.global_tracer = init_tracer('hello-world')
  end

  def say_hello(hello_to)
    span = OpenTracing.start_span('say-hello')
    span.set_tag('funk', 'nuts')
    hello_str = format_string(span, hello_to)
    print_hello(span, hello_str)
    span.finish
  end
  
  def format_string(span, hello_to)
  	hello_str = "Hello, #{hello_to}!"
    span.log_kv(event: hello_str)
    hello_str
  end
  
  def print_hello(span, hello_str)
  	puts hello_str
    span.log_kv(event: 'print line')
  end
end
```

Of course, this does not change the outcome. What we really want is a span for each method.

```ruby
class HelloWorld
  include Tracing

  def initialize
    OpenTracing.global_tracer = init_tracer('hello-world')
  end

  def say_hello(hello_to)
    span = OpenTracing.start_span('say-hello')
    span.set_tag('funk', 'nuts')
    hello_str = format_string(span, hello_to)
    print_hello(span, hello_str)
    span.finish
  end
  
  def format_string(root_span, hello_to)
    span = OpenTracing.start_span('format')
  	hello_str = "Hello, #{hello_to}!"
    span.log_kv(event: hello_str)
    hello_str
  end
  
  def print_hello(root_span, hello_str)
    span = OpenTracing.start_span('format')
  	puts hello_str
    span.log_kv(event: 'print line')
  end
end
```

Let's run it again:

```bash
$ bundle exec ruby lesson02/exercise/hello.rb Bryan
```

We got three spans, but there is a problem here. The first hexadecimal segment of the output represents
Jaeger trace ID, yet they are all different. If we search for those IDs in the UI each one will represent
a standalone trace with a single span. That's not what we wanted!

What we really wanted was to establish causal relationship between the two new spans to the root
span started in `say_hello`. We can do that by passing an additional option to the `start_span`
function:

```ruby
class HelloWorld
  include Tracing

  def initialize
    OpenTracing.global_tracer = init_tracer('hello-world')
  end

  def say_hello(hello_to)
    span = OpenTracing.start_span('say-hello')
    span.set_tag('hello_to', hello_to)
    hello_str = format_string(span, hello_to)
    print_hello(span, hello_str)
    span.finish
  end

  def format_string(root_span, hello_to)
    span = OpenTracing.start_span('format', child_of: root_span)
    hello_str = "Hello, #{hello_to}!"
    span.log_kv(event: hello_str)
    hello_str
    span.finish
  end

  def print_hello(root_span, hello_str)
    span = OpenTracing.start_span('format', child_of: root_span)
    puts hello_str
    span.log_kv(event: 'print line')
    span.finish
  end
end
```

If we think of the trace as a directed acyclic graph where nodes are the spans and edges are
the causal relationships between them, then the `child_of` option is used to create one such
edge between `span` and `root_span`. In the API the edges are represented by `SpanReference` type
that consists of a `SpanContext` and a label. The `SpanContext` represents an immutable, thread-safe
portion of the span that can be used to establish references or to propagate it over the wire.
The label, or `ReferenceType`, describes the nature of the relationship. `ChildOf` relationship
means that the `root_span` has a logical dependency on the child `span` before `root_span` can
complete its operation. Another standard reference type in OpenTracing is `FollowsFrom`, which
means the `root_span` is the ancestor in the DAG, but it does not depend on the completion of the
child span, for example if the child represents a best-effort, fire-and-forget cache write.

### Propagate the in-process context

You may have noticed one unpleasant side effect of our recent changes - we had to pass the Span object
as the first argument to each function. Unlike Go, languages like Java, Python, and Ruby support thread-local
storage, which is convenient for storing such request-scoped data like the current span. 
The OpenTracing API for Ruby supports a standard mechanism for passing and accessing the current 
span using the concepts of Scope Manager and Scope, which are using either plain thread-local storage. 

Instead of calling `start_span` on the tracer, we can call `start_active_span` that invokes that mechanism 
and makes the span "active" and accessible via `tracer.active_span`. The return value of the `start_active_span` 
is a `Scope` object that needs to be closed in order to restore the previously active span on the stack.

```ruby
def say_hello(hello_to)
  OpenTracing.start_active_span('say-hello') do |scope|
	  scope.span.set_tag('hello-to', hello_to)
	  hello_str = format_string(hello_to)
	  print_hello(hello_str)
  end
end
```

Notice that we're no longer passing the span as argument to the functions, because they can now
retrieve the span with `OpenTracing.active_span` method. However, because creating a child span of a currently active span 
is such a common pattern, this now happens automatically, so that we do not need to pass the `child_of` reference to the parent span anymore:

```ruby
def format_string(hello_to)
  OpenTracing.start_active_span('format') do |scope|
    hello_str = "Hello, #{hello_to}!"
    scope.span.log_kv(event: hello_str)
    return hello_str
  end
end

def print_hello(hello_str)
  OpenTracing.start_active_span('print') do |scope|
    puts hello_str
    scope.span.log_kv(event: 'print line')
  end
end
```

As the `format_string` and `print_hello` methods are called from within the parent span they automatically become children of the parent span.
Although it's spread across three methods it's functionally equivalent to:

```ruby
OpenTracing.start_active_span('say-hello') do |scope|
  # parent logic...
  OpenTracing.start_active_span('format') do |scope|
    # child logic...
  end
  OpenTracing.start_active_span('print') do |scope|
    # child logic...
  end
end
```

Note that because `start_active_span` passes a `Scope` instead of a `Span` to its block, we use `scope.span` property to access the span when we want 
to annotate it with tags or logs. 

If we run this modified program, we will see that all three reported spans still have the same trace ID.

### What's the Big Deal?

The last change we made may not seem particularly useful. But imagine that your program is
much larger with many functions calling each other. By using the Scope Manager mechanism we can access
the current span from any place in the program without having to pass the span object as the argument to
all the function calls. This is especially useful if we are using instrumented RPC frameworks that perform
tracing functions automatically - they have a stable way of finding the current span.

## Conclusion

The complete program can be found in the [solution](./solution) package.

Next lesson: [Tracing RPC Requests](../lesson03).
