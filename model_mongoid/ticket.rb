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
	field :checker, type: Array


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

	def self.select_ticket(annotator, strategy='semi_random')
		# annotatorの人数4人以上だったらタグ付けしない
		query_or = []
		for i in 0...2 do
			query_or << {:annotator.with_size=>i}
		end
		query_or = {"$or"=> query_or}
		
		#番号の若いレシピから順に選ぶ
		cands =  Array.new(3){|i| "2015YR%02d"%(i+1)}
		cands +=  Array.new(20){|i| "2014RC%02d"%(i+1)}
		#cands = ["2015YR","2014RC"].product(Array.new(20){|i| "%02d"%(i+1)}).map{|v|v.join}
		for recipe_id in cands do
			case strategy
				when 'random' then
					sample = self.where(blob_id:/#{recipe_id}/).sample
				when 'ordered' then
					sample = self.where(blob_id:/#{recipe_id}/).sort_by{|v|
						STDERR.puts v.blob_id
						v.blob_id
					}[0]
				else
				# semi_random 
=begin
					if rand < 0.2 then
						sample = self.where(blob_id:/#{recipe_id}/, task: "task2", completion:false).not.any_in(:annotator=>[annotator]).sample
						return sample if sample
					end
=end
					if rand < 0.3 then
						sample = self.where(blob_id:/#{recipe_id}/, task: "task3", completion:false).not.any_in(:annotator=>[annotator]).where(query_or).sample
						return sample if sample
						
					end
					sample = self.where(blob_id:/#{recipe_id}/, completion:false).where(query_or).not.any_in(:annotator=>[annotator]).sample
			end
			
			return sample if sample
		end
		return nil
#, :annotator=>{"$elemMatch"=>{"$regex"=>/#{annotator}/}}}).sample

	end

	# 指定されたアノテータをticketに追加
=begin
	def self.add_annotator(annotator, task, blob_id, max_task_num=1)
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
