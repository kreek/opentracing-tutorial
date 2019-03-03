require 'opentracing'
require 'jaeger/client'
require 'time'
require_relative '../../../ruby/lib/tracing'

class HelloWorld
  include Tracing

  def initialize
    OpenTracing.global_tracer = init_tracer('hello-world')
  end

  def say_hello(hello_to)
    OpenTracing.start_active_span('say-hello') do |scope|
      scope.span.set_tag('hello-to', hello_to)
      hello_str = format_string(hello_to)
      print_hello(hello_str)
    end
  end

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
end

raise ArgumentError, 'Expecting one argument' unless ARGV.count == 1

HelloWorld.new.say_hello(ARGV[0])

sleep 2
