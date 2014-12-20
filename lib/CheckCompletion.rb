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
				return check_completion_task3(ticket,mtasks)
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
			return 0 if a['width']==0 or a['height']==0
			return 0 if b['width']==0 or b['height']==0
			area_a = a['width'] * a['height']
			area_b = b['width'] * b['height']
			c = common_area(a,b)
			return 0 if c['width'] <= 0
			return 0 if c['height'] <= 0
			area_c = c['width'] * c['height']
			
			return 2*area_c/(area_a+area_b)
		end

		def check_completion_task1(ticket,mtasks)
			annotations = mtasks.map{|v|v['annotation']}
			# check the number of boxes.
			flag = true
			results = annotations.combination(2){|a,b|
				# 他で結果が出ていれば後は計算省略
				next if flag == false

				# 両方アノテーションなしならOK
				next if !a and !b
				
				# 一方だけアノテーションがあるならNG
				if !(a and b) then
					flag = false
					next
				end

				# サイズが違うならNG
				if a.size != b.size then
					flag = false
					next
				end
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
				
				# 矩形の重なり(similarity)の最小値がしきい値以下ならNG
				flag = false if min_sim < settings.task1['min_similarity']
			}
			return flag
		end			

		def check_completion_task2(ticket,mtasks)
			# check the number of boxes.
			flag = true
			ingredients = mtasks.map{|v| v['ingredients']}.flatten.uniq.sort
			utensils = mtasks.map{|v| v['utensils']}.flatten.uniq.sort
			seasonings = mtasks.map{|v| v['seasonings']}.flatten.uniq.sort
			for mtask in mtasks do
				flag = false unless mtask['ingredients'].sort == ingredients
				flag = false unless mtask['utensils'].sort == utensils
				flag = false unless mtask['seasonings'].sort == seasonings
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
			
			
		def check_completion_task3(ticket,mtasks)
			labels = mtasks.map{|v| v['label']}.uniq
			return true if labels.size == 1
		end
	end
end