#!/usr/bin/ruby
require 'rubygems'
require 'mongoid'
require 'yaml'


THIS_DIR = File.dirname(__FILE__)
_DEBUG = true
_COMPLESS = true



ARG_NUM = 2

if ARGV.size < ARG_NUM then
  unless _DEBUG then
  	STDERR.puts "USAGE: ruby #{__FILE__} data_id output_file"
  	exit 1
  end
  ARGV << '2014RC01_S020' if ARGV.size == 0
  ARGV << "#{THIS_DIR}/test.#{File.basename(__FILE__,'.rb')}.csv" if ARGV.size == 1
end


environment = :development
if ARGV.size > ARG_NUM
	environment = ARGV[ARG_NUM]
end

Mongoid.load!('./mongoid.yml', environment)

if environment == :development then
	YML_FILE = "#{THIS_DIR}/../config_dev.yml"
else
	YML_FILE = "#{THIS_DIR}/../config.yml"
end

conf = YAML.load_file(YML_FILE)
require "#{THIS_DIR}/../model_mongoid/ticket.rb"
require "#{THIS_DIR}/../model_mongoid/microtask.rb"

TargetData = ARGV[0]
OutputFile = ARGV[1]


labels = []
reg_query = Regexp.new(TargetData)
Ticket.where(task:'task4',completion:true,blob_id:reg_query).each{|t|
	sample_id = t.blob_id
	mtask = MicroTask.where(task:'task4',blob_id:t.blob_id)[0]
	unless mtask then
		STDERR.puts "WARNING: micro_task not found (#{t.blob_id})"
		next
	end
	label = mtask['label']
	puts mtask.as_json
	puts t.as_json
	#data_id = t.blob_id.split(':')[0]
	#puts data_id

	start_time = t['start_time']
	start_frame = t['start_frame']
	end_time = t['end_time']
	end_frame = t['end_frame']
	labels << {
			label:label,
			start_time:start_time,start_frame:start_frame,
			end_time:end_time,end_frame:end_frame
	}
}

labels.sort_by!{|v| v[:start_frame]}

fout = File.open(OutputFile,'w')
labels.each{|l|
  l_s = l[:start_frame]
  l_e = l[:end_frame]
  label = l[:label]
  puts "#{l_s} to #{l_e}"
  if _COMPLESS then
    fout.puts "#{l_s}, #{label}/Ac:1.0"
  else
    for frame in l_s...l_e do
      fout.puts "#{frame}, #{label}/Ac:1.0"
    end
  end
}
fout.close
exit 0