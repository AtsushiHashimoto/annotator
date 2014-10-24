require 'mongoid'
require 'bcrypt'

class Ticket
	include Mongoid::Document

	# fields (presence: true)
	field :blob_id
	field :blob_path
	field :task
	field :completion, type: Boolean, default: false

	# fields (presence: true)
	field :recipe
	field :microtask_ids, type: Array


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

	def self.select_task
		self.where(completion:false).sample
	end

end 