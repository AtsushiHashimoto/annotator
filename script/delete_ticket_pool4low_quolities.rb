#!/usr/bin/ruby
require 'rubygems'
require 'mongoid'
require 'json'
require 'yaml'


THIS_DIR = File.dirname(__FILE__)

ARG_NUM = 0

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__}"
	exit 1
end

DISABLE_TARGET = File.open("#{THIS_DIR}/LowQualities.txt").read.strip.split("\n").map{|v|v.strip}


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
require "#{THIS_DIR}/../model_mongoid/ticket_pool.rb"

delete_target = []

TicketPool.where(task:'task4').each{|t|
  flag = true
  for dt_id in DISABLE_TARGET do
    next unless t.subtask =~ /.*#{dt_id}.*/
    #puts "#{t.subtask} matches to #{dt_id}"
    flag = false
    break
  end
  if flag then
    puts "keep #{t.subtask}"
    next # DISABLE_TARGETになければ，何もしないで次へ
  end

  puts "delete #{t.subtask}"
  t.delete
}

exit 0