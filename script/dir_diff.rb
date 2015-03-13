#!/usr/bin/ruby
require 'rubygems'
require 'active_support'

ARG_NUM = 2

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__} dir1 dir2"
	exit 1
end

dir1 = ARGV[0]
dir2 = ARGV[1]
file_list1 = `cd #{dir1};find . -print | sort`.split("\n").map{|v|v.strip}
file_list2 = `cd #{dir2};find . -print | sort`.split("\n").map{|v|v.strip}

puts "only in #{dir1}"
(file_list1-file_list2).each{|file| puts file}
puts ""
puts "only in #{dir2}"
(file_list2-file_list1).each{|file| puts file}

exit 0