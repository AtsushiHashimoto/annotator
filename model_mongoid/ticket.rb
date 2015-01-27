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

	def self.select_ticket(annotator, min_task_num, strategy='semi_random', for_check = false, task_priority={})
		task_priority = {'task4'=>0.95,'task3'=>0.4,'task2'=>0.05,'task1'=>1.0} if task_priority.empty?

		max_task_num = min_task_num.values.max
		# annotatorの人数12人以上だったらタグ付けしない
		query_or = []
		for i in 0...max_task_num do
			query_or << {:annotator.with_size=>i}
		end
		#		query_or = {"$or"=> query_or}
		
		#番号の若いレシピから順に選ぶ
		cands =  Array.new(3){|i| "2015YR%02d"%(i+1)}
		cands +=  Array.new(20){|i| "2014RC%02d"%(i+1)}
		#cands = ["2015YR","2014RC"].product(Array.new(20){|i| "%02d"%(i+1)}).map{|v|v.join}
		
		tickets = self.where(completion:false)
		
		for recipe_id in cands do
			for task,prob in task_priority do
				next if Random.rand > prob
				STDERR.puts "#{recipe_id}: #{task}"
				tickets = self.where(blob_id:/#{recipe_id}/, task:task,completion:false)
				task_num = min_task_num[task]
				if for_check then
					tickets = tickets.nor(query_or[0...task_num])
				else
					tickets = tickets.or(query_or[0...task_num]).not.any_in(:annotator=>[annotator])
				end

				if task=='task4' then
					sample = tickets.sort_by{|v|v.blob_id}[0]
				else
					case strategy
						when 'ordered' then
							sample = tickets.sort_by{|v|v.blob_id}[0]
						else # random, semi_random 
							sample = tickets.sample
					end
				end

				break if sample
			end
			return sample if sample
		end
		for task,prob in task_priority do
			tickets = self.where(task:task,completion:false)
			task_num = min_task_num[task]
			if for_check then
				sample = tickets.nor(query_or[0...task_num])
			else
				sample = tickets.or(query_or[0...task_num]).not.any_in(:annotator=>[annotator])
			end
			break if sample
		end
		
		return sample
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
