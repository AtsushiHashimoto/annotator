require 'mongoid'
require 'bcrypt'

class Ticket
	include Mongoid::Document
	include Mongoid::Timestamps

	# fields (presence: true)
	field :blob_id
	field :blob_path
	field :task
	field :completion, type: Boolean, default: false

	# fields (presence: true)
	field :recipe
	field :annotator, type: Array


	validates :blob_id, presence: true
	validates :blob_path, presence: true
	validates :task, presence: true
	# validates :microtask_ids, presence: false # まだ誰もやっていない⇢空
	validates :completion, presence: true
	
	def self.duplicate?(ticket_id)
		self.where(_id: ticket_id).first
	end

	def self.check(ticket_id, microtask_id)
		ticket = self.where(ticket_id).first
		return nil unless ticket
		ticket.microtask_ids << microtask_id
		ticket.save
	end

	def self.select_ticket(annotator)
		STDERR.puts annotator
		self.where(completion:false).not.any_in(:annotator=>[annotator]).sample
#, :annotator=>{"$elemMatch"=>{"$regex"=>/#{annotator}/}}}).sample

	end

	# 指定されたアノテータをticketに追加
	def self.add_annotator(annotator, task, blob_id, max_task_num=2)
		return if task == 'rest'
		ticket = self.where({:task=>task,:blob_id=>blob_id})
		raise "ticket not found." if ticket.empty?
		ticket = ticket[0]
#		STDERR.puts annotator
#		STDERR.puts task
#		STDERR.puts blob_id

		return if ticket.annotator.include?(annotator)

		ticket.annotator << annotator
		if ticket.annotator.size >= max_task_num then
			ticket.completion = true
		end

		unless ticket.save! then
				raise "failed to update ticket."
		end
	end
end 
