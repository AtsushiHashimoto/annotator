#!/usr/bin/ruby
require 'rubygems'
require 'active_support'

ARG_NUM = 0

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__}"
	exit 1
end


THIS_DIR = File.dirname(__FILE__)
DB_DIR = "#{THIS_DIR}/../db"

`mkdir -p #{DB_DIR}/backup`

now = Time.now

suffix = now.strftime('%Y-%m-%d-%H:%M:%S')

command = "mongodump --out #{DB_DIR}/backup/mongodump.#{suffix}"
#puts command
`#{command}`


# How to Restore => http://gihyo.jp/dev/serial/01/mongodb/0011?page=2
exit 0