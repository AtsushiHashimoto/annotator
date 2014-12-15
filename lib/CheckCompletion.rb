require 'sinatra/extension'
require 'munkres'

module Helpers
	module CheckCompletion
		extend Sinatra::Extension
		
		def self.registered(app)
			app.helpers CheckCompletion
		end
	
		def check_completion(ticket,mtasks)
			task = ticket.task
			blob_id = ticket.blob_id
			# check
			for mtask in mtasks do
				raise "invalid argment" unless task == mtask.task
				raise "invalid argment" unless blob_id == mtask.blob_id
			end
			
			min_mtask_num = settings.minimum_micro_task_num[task]
			return false if mtasks.size < min_mtask_num
			
			case task
				when 'task1' then
				return check_completion_task1(ticket,mtasks)
				when 'task2' then
				return check_completion_task2(ticket,mtasks)
				when 'task3' then
				return check_completion_task2(ticket,mtasks)
				else
				#未実装
				raise "Unknown task"
			end			
		end
			
			
		def common_area(a,b)
			x = [a['x'],b['x']].max
			y = [a['y'],b['y']].max
			x2 = [a['x']+a['width'],b['x']+b['width']].min
			y2 = [a['y']+a['height'],b['y']+b['height']].min
			return {'x'=>x, 'y'=>y, 'width'=>(x2-x), 'height'=>(y2-y)}
		end
		def similarity_of_box(a,b)
			return 0 if a['type'] != b['type']
			area_a = a['width'] * a['height']
			area_b = b['width'] * b['height']
			c = common_area(a,b)
			area_c = c['width'] * c['height']
			return 2*area_c/(area_a+area_b)
		end

		def check_completion_task1(ticket,mtasks)
			annotations = mtasks.map{|v|v['annotation']}
			# check the number of boxes.
			flag = true
			results = annotations.combination(2){|a,b|
				return false unless a.size == b.size
				cost_matrix = []
				for box_a in a do
					col = []
					for box_b in b do
						col << 1- similarity_of_box(box_a,box_b)
					end
					cost_matrix << col
				end
				m = Munkres.new(cost_matrix)
				min_sim = 1.0
				for pair in m.find_pairings do
					sim = similarity_of_box(a[pair[0]],b[pair[1]])
					min_sim = [sim,min_sim].min
				end
				flag = false if min_sim < settings.task1['min_similarity']
			}
			return flag
		end			

		def check_completion_task2(ticket,mtasks)
			# check the number of boxes.
			flag = true
			ingredients = mtasks.map{|v| v['ingredients']}.flatten.uniq
			utensils = mtasks.map{|v| v['utensils']}.flatten.uniq
			seasonings = mtasks.map{|v| v['seasonings']}.flatten.uniq
			for mtask in mtasks do
				flag = false unless mtask['ingredients'] == ingredients
				flag = false unless mtask['utensils'] == utensils
				flag = false unless mtask['seasonings'] == seasonings
			end
			if false == flag then
				cand = ticket['candidates']
				cand['ingredient'] = ingredients
				cand['utensil'] = utensils
				cand['seasoning'] = seasonings
				ticket['candidates'] = cand
				unless ticket.upsert then
					raise 'failed to update attributes.'
				end
			end
			return flag
		end
	end
end