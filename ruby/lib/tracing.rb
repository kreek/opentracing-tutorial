require 'jaeger/client'

module Tracing
  def init_tracer(service)
    Jaeger::Client.build(
      host: 'localhost',
      service_name: service,
      flush_interval: 1
    )
  end
end
