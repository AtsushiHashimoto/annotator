#!/usr/bin/ruby
require 'rubygems'
require 'mongoid'
require 'yaml'


THIS_DIR = File.dirname(__FILE__)

ARG_NUM = 1

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__} output_dir"
	exit 1
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

OutputDir = ARGV[0]

`mkdir -p #{OutputDir}`

labels = Hash.new(){|h,k|h[k]=[]}

Ticket.where(task:'task4',completion:true).each{|t|
	sample_id = t.blob_id
	mtask = MicroTask.where(task:'task4',blob_id:t.blob_id)[0]
	unless mtask then
		STDERR.puts "WARNING: micro_task not found (#{t.blob_id})"
		next
	end
	label = mtask['label']
	puts mtask.as_json
	puts t.as_json
	data_id = t.blob_id.split(':')[0]
	#puts data_id

	start_time = t['start_time']
	start_frame = t['start_frame']
	end_time = t['end_time']
	end_frame = t['end_frame']
	labels[data_id] << {
			label:label,
			start_time:start_time,start_frame:start_frame,
			end_time:end_time,end_frame:end_frame
	}
}

def min_sec(sec)
	return sec.to_i/60, ((sec - sec.to_i) + sec.to_i % 60).round(3)
end

labels.each{|data_id,tags|
	fout = File.open("#{OutputDir}/#{data_id}.csv",'w')
	tags.sort_by{|v|v[:start_time]}.each{|tag|
		next if 'その他'==tag[:label]
		fout.puts "#{min_sec(tag[:start_time]).join(",")}, #{min_sec(tag[:end_time]).join(",")}, #{tag[:label]}"
	}
	fout.close
}


exit 0