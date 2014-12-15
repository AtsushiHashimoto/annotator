require 'mongoid'
#require 'mongoid-versioning'
require 'bcrypt'

class Passback
	include Mongoid::Document
	
	field :ticket, type: Hash
	field :micro_tasks, type: Array
	field :time, type: DateTime
		
	validates :ticket, presence: true
	validates :micro_tasks, presence: true
	validates :time, presence: true
	
	def self.execute(ticket,mtasks)
		task = ticket.task
		blob_id = ticket.blob_id
		# check
		for mtask in mtasks do
			raise "invalid argment" unless task == mtask.task
			raise "invalid argment" unless blob_id == mtask.blob_id
		end
		ticket_ = JSON.parse(ticket.to_json)
		mtasks_ = mtasks.map{|v| JSON.parse(v.to_json)}
		passback = self.new(ticket:ticket_,micro_tasks:mtasks_,time: Time.new)
		
		raise "failed to passback ticket '#{ticket._id}'" unless passback.save!
		for mtask in mtasks do
			MicroTask.delete(mtask._id)
		end
	end
end 