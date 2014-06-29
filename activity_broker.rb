require_relative 'lib/activity_broker'
require 'optparse'

config = {
  event_source_port: 9090,
  subscriber_port: 9099
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby activity_broker.rb [options]"

  opts.on('--event_source_port NNNN',
          'port used for accepting connections from event source (default: 9090)') do |v|
    config[:event_source_port] = v.to_i
  end

  opts.on('--subscriber_port NNNN',
          'port used for accepting connections from clients (default: 9099)') do |v|
    config[:subscriber_port] = v.to_i
  end

  opts.on_tail('-h, --help') do
    puts config
    exit
  end
end.parse!(ARGV)

runner = ActivityBroker::ApplicationRunner.new(config)

trap(:INT) do
  runner.stop
  exit
end

runner.start
