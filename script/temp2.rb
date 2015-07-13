#!/usr/bin/ruby
require 'rubygems'
require 'sinatra'
require "sinatra/reloader"
require 'active_support'
require 'mongoid'


# checker

Mongoid.load!('./mongoid.yml')
require './../model_mongoid/microtask.rb'
require './../model_mongoid/ticket.rb'

Width = 416.0
Height = 310.4

configure do
	register Sinatra::Reloader
end

get '/' do
	tickets = Ticket.where(task:'task1').excludes(checker:nil)
	
	# check before execution
	tickets.each{|t|
		mtasks = MicroTask.where(task:t.task,blob_id:t.blob_id)
		if mtasks.size != 1 then
			return "ERROR: #{ticket.blob_id} has #{mtasks.size} mtasks."
		end
	}	

	tickets.each{|t|
		mtask = MicroTask.where(task:t.task,blob_id:t.blob_id)[0]
		a = mtask['annotation']
		next if !a or a.empty?
		new_annotations = []
		STDERR.puts mtask.blob_id
		STDERR.puts "==before=="
		STDERR.puts a
		flag = true
		for box in a do
			box['x'] *= Width
			box['width'] *= Width
			box['y'] *= Height	
			box['height'] *= Height
			# checkerの手作業を除く
			if box['y'] + box['height'] <= 1 and box['x']+box['width'] <= 1 then
				new_annotations << box
			else
				flag = false
				break
			end
		end
		next unless flag
		STDERR.puts "==after=="
		STDERR.puts new_annotations		
		MicroTask.where(blob_id:t.blob_id).update(annotation:new_annotations)
	}
	return 'Hello world from temp2.rb!'
end

