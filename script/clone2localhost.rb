#!/usr/bin/ruby
require 'rubygems'
require 'active_support'

ARG_NUM = 0

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__}"
	exit 1
end

RemoteHostIP = "10.236.170.115" # edit if server is moved.
MongoDBPort = "27017"
DB_NAME = "kusk_annotation"

LocalHostIP = `curl ifconfig.me`.strip

if LocalHostIP == RemoteHostIP then
  STDERR.puts "ERROR: this script cannot run on #{RemoteHostIP}, which is the main mongodb host server."
  exit 1
end

THIS_DIR = File.dirname(__FILE__)
DB_DIR = "#{THIS_DIR}/../db"

now = Time.now
suffix = now.strftime('%Y-%m-%d-%H:%M:%S')
TEMP_DIR = "#{DB_DIR}/temp_#{suffix}"
`mkdir -p #{TEMP_DIR}`

command = "mongodump --host #{RemoteHostIP} --port #{MongoDBPort} --out #{TEMP_DIR}/mongodump"
#puts command
puts `#{command}`

command = "mongorestore -d #{DB_NAME} --drop #{TEMP_DIR}/mongodump/#{DB_NAME}"
puts command
puts `#{command}`

`rm -rf #{TEMP_DIR}`

exit 0