#!/usr/bin/ruby
require 'rubygems'
require 'mongoid'
require 'yaml'
require 'csv'



THIS_DIR = File.dirname(__FILE__)
_DEBUG = true
_COMPLESS = true


ARG_NUM = 2

if ARGV.size < ARG_NUM then
  unless _DEBUG then
  	STDERR.puts "USAGE: ruby #{__FILE__} data_id output_file timestamp_dir"
  	exit 1
  end
  ARGV << '2014RC01_S020' if ARGV.size == 0
  ARGV << "#{THIS_DIR}/test.#{File.basename(__FILE__,'.rb')}.csv" if ARGV.size == 1
end
#ARGV << "#{THIS_DIR}/../blob_images/#{ARGV[0]}/" if ARGV.size == 2


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
#TimeStampDir = ARGV[2]
DataPath = "../blob_images/#{TargetData}"

class String
  def blob_id_parse
    # "2014RC01_S020:extract:cameraA:PUT:putobject_0003012_016::1"
    buf = self.split(':')
    hash = {}
    hash[:recipe] = buf[0]
    hash[:camera] = buf[2]
    buf = buf[1..-1]

    hash[:box_id] = buf[-1].to_i

    temp,frame,blob_id =buf[-3].split('_')
    hash[:frame] = frame.to_i
    hash[:blob_id] = blob_id.to_i
    hash
  end
end
cameras = []
labels = []
reg_query = Regexp.new(TargetData)


mtask3s = MicroTask.where(task:'task3',blob_id:reg_query)
mtask1s = MicroTask.where(task:'task1',blob_id:reg_query)

Ticket.where(task:'task3',completion:true,blob_id:reg_query).each{|t|
	sample_id = t.blob_id
	mtask = mtask3s.where(task:'task3',blob_id:t.blob_id)[0]
	unless mtask then
		STDERR.puts "WARNING: micro_task not found (#{t.blob_id})"
		next
  end
  hash = mtask['blob_id'].blob_id_parse
	hash[:label] = mtask['label']

  mtask1 = mtask1s.where(task:'task1',blob_id:t.blob_id.split('::')[0])[0]
  hash[:event] = mtask1['annotation'][hash[:box_id]]['type']
  labels << hash

  cameras << hash[:camera] unless cameras.include?(hash[:camera])
}

# timestampがなければサーバからダウンロードする
KuskDatasetServer = '133.3.251.221'
User = 'a_hasimoto'
def _ensure_timestampfile(dir,camera,data_id,dataset)
  `scp #{User}@#{KuskDatasetServer}:/WWW/data/#{dataset}/#{data_id}/FlyCapCamera/#{camera}_timestamp.csv #{dir}`
end
def ensure_timestampfile(file,camera,data_id)
  return if File.exist?(file)
  dir = File.dirname(file)
  _ensure_timestampfile(dir,camera,data_id,'2014RC')
  return if File.exist?(file)
  _ensure_timestampfile(dir,camera,data_id,'2014RC_low_quality')
end

# timestampを読み込む
def load_timestamp(file)
  buf = CSV.read(file)
  hash = {}
  for col in buf do
    hash[col[0].to_i] = col[2].strip
  end
  hash
end

timestamps = {}
cameras.sort.each { |camera|
  timestamp_file = "#{DataPath}/#{camera}_timestamp.csv"
  ensure_timestampfile(timestamp_file,camera,TargetData)
  timestamps[camera] = load_timestamp(timestamp_file)
}

labels.sort_by!{|v| v[:frame]}

fout = File.open(OutputFile,'w')
fout.puts "ID(cameraid_blobid_boxid), camera, event, timestamp, likelihood"

labels.each{|l|
  fields = []
  fields << "ID(#{l[:camera]}_#{l[:blob_id]}_#{l[:box_id]})"
  fields << l[:camera]
  fields << l[:event]
  fields << timestamps[l[:camera]][l[:frame]]
  fields << "#{l[:label]}:1.0"
  fout.puts fields.join(",")
}
fout.close
exit 0