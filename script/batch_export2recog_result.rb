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
  	STDERR.puts "USAGE: ruby #{__FILE__} src_dir tar_dir"
  	exit 1
  end
  ARGV << '../blob_images' if ARGV.size == 0
  ARGV << "../annotated_data" if ARGV.size == 1
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

SRC_DIR = ARGV[0]
TAR_DIR = ARGV[1]

data_ids = Dir.glob("#{SRC_DIR}/*").map{|v|File.basename(v)}.sort

def check_completion(task,data_id)
  tickets = Ticket.where(task:task,blob_id:/#{data_id}/)
  num_of_tickets = tickets.count
  if num_of_tickets == 0 then
    STDERR.puts "#{data_id}/#{task}: no tickets are hit."
  end
  return false if num_of_tickets == 0

  num_of_completion = tickets.where(completion:true).count

  if num_of_completion != num_of_tickets then
    STDERR.puts "#{data_id}/#{task}: completion = #{num_of_completion} / #{num_of_tickets}"
  end

  return (num_of_tickets == num_of_completion)
end

# export to recognition result for action
EXE_ACTION = "ruby #{THIS_DIR}/export2recog_result4action.rb"
data_ids.each{|data_id|
  next unless check_completion('task4',data_id)
  tar_dir = "#{TAR_DIR}/#{data_id}"
  `mkdir -p #{tar_dir}`
  tar_file = "#{tar_dir}/motion_tag.csv"
  `#{EXE_ACTION} #{data_id} #{tar_file}`
}

EXE_OBJ_ACCESS = "ruby #{THIS_DIR}/export2recog_result4object_access.rb"
data_ids.each{|data_id|
  next unless check_completion('task1',data_id)
  #next unless check_completion('task2',data_id)
  next unless check_completion('task3',data_id)
  tar_dir = "#{TAR_DIR}/#{data_id}"
  `mkdir -p #{tar_dir}`
  tar_file = "#{tar_dir}/motion_tag.csv"
  `#{EXE_OBJ_ACCESS} #{data_id} #{tar_file}`
}

exit 0