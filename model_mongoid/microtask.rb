require 'mongoid'
require 'bcrypt'

class MicroTask
	include Mongoid::Document
	
	field :worker
	field :time_range, type: Array
	field :min_work_time, type: Integer
	field :task
	field :blob
	# annotation data are added as custom field.
	# e.g.
	# mtask = MicroTask.new(..省略..)
	# mtask[:rect] = [12,34]..[30,56] # <- (12,34)を始点，(30,56)を終点とする矩形領域
	
	validates :worker, presence: true
	validates :time_range, presence: true
	validates :min_work_time, presence: true
	validates :task, presence: true
	
	def self.duplicate?(mtask_id)
		self.where(_id: mtask_id).first
	end

	def self.delete(mtask_id)
		self.where(_id: mtask_id).delete
	end

end 