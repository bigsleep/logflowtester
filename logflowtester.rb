require 'fluent/config'
require 'fluent/engine'
require 'fluent/env'
require 'fluent/plugin/bare_output'
require 'fluent/plugin/multi_output'
require 'fluent/plugin/out_copy'
require 'fluent/plugin/out_relabel'
require 'fluent/root_agent'
require 'fluent/system_config'
require 'fluent/test/log'
require 'json'

if ARGV.size != 2 then
    puts ARGV.inspect
    puts "usage: ruby $0 [CONFIG_FILE] [LOG_EVENTS_JSON]"
    exit
end

def format_error
    puts <<"EOS"
log events format error.
format: [{"tag":"aaa.bbb.ccc","source_index":0,"record":{"value":"a"}}]
EOS
    exit
end

path = ARGV[0]
config_fname = File.basename(path)
config_basedir = File.dirname(path)
use_v1_config = true

config_data = File.open(path, "r:utf-8:utf-8") {|f| f.read }

def format_result(output, tag, es)
    <<"EOS"
Result:
  - output: #{output.inspect}
  - tag: #{tag}
  - es: #{es.inspect}
EOS
end

def is_leaf(output)
    [Fluent::Plugin::RelabelOutput, Fluent::Plugin::CopyOutput, Fluent::Plugin::MultiOutput, Fluent::Plugin::BareOutput].each { |k|
        if output.is_a?(k) then
            return false
        end
    }
    true
end

orig_new_output = Fluent::Plugin.method(:new_output)
Fluent::Plugin.define_singleton_method(:new_output) {|type|
    output = orig_new_output.call(type)

    if is_leaf(output) then
        output.define_singleton_method(:emit_events) { |tag, es|
            puts format_result(output, tag, es)
        }

        output.define_singleton_method(:configure) {|conf|
            output
        }

        output.define_singleton_method(:start) {}
        output.define_singleton_method(:after_start) {}
    end

    output
}

conf = Fluent::Config.parse(config_data, config_fname, config_basedir, use_v1_config)
system_config = Fluent::SystemConfig.create(conf)

$log = Fluent::Test::TestLogger.new
engine = Fluent::Engine.init(system_config)
engine.run_configure(conf)

begin
    events = JSON.load(ARGV[1])
rescue JSON::ParserError => e
    puts "JSON parse error: #{e}"
    exit
end

if !events.instance_of?(Array) then
    format_error
end

events.each do |event|
    if !event.has_key?("tag") then
        format_error
    end

    if !event.has_key?("source_index") then
        format_error
    end

    if !event.has_key?("record") then
        format_error
    end

    if engine.root_agent.inputs.size <= event["source_index"] then
        puts "source index out of range"
        exit
    end
end

events.each do |event|
    time = Fluent::Engine.now
    source_index = event["source_index"]
    tag = event["tag"]
    record = event["record"]
    engine.root_agent.inputs[source_index].router.emit(tag, time, record)
end
