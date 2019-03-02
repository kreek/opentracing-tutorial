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
      scope.span.set_tag('hello_to', hello_to)
      hello_str = "Hello, #{hello_to}!"
      scope.span.log_kv(event: hello_str)
      puts hello_str
      scope.span.log_kv(event: 'print line')
    end
  end
end

raise ArgumentError, 'Expecting one argument' unless ARGV.count == 1

HelloWorld.new.say_hello(ARGV[0])

sleep 2
