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
		#番号の若いレシピから順に選ぶ
		for i in 1..20 do
			recipe_id = "2014RC#{"%02d"%i}"
			
			if rand < 0.2 then
				sample = self.where(blob_id:/#{recipe_id}/, task: "task2", completion:false).not.any_in(:annotator=>[annotator]).sample
				return sample if sample
			end
			
			sample = self.where(blob_id:/#{recipe_id}/, completion:false).not.any_in(:annotator=>[annotator]).sample
			return sample if sample
		end
		return nil
#, :annotator=>{"$elemMatch"=>{"$regex"=>/#{annotator}/}}}).sample

	end

	# 指定されたアノテータをticketに追加
=begin
	def self.add_annotator(annotator, task, blob_id, max_task_num=1)
>>>>>>> 6e1cc1560994eb85d4c369af1c8a102c189fcdd3
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
=end
end 
