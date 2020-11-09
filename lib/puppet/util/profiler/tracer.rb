class Puppet::Util::Profiler::Tracer
  def initialize(identifier)
  end

  def start(description, metric_id)
    $stderr.puts "start: #{description} #{metric_id}"
  end

  def finish(context, description, metric_id)
    $stderr.puts "finish: #{description} #{metric_id}"
  end

  def shutdown
    $stderr.puts "shutdown"
  end
end
