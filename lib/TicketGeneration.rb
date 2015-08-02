require 'kconv'
require 'sinatra/extension'

module Helpers
	module TicketGeneration
		extend Sinatra::Extension
		
		def self.registered(app)
			app.helpers TicketGeneration
		end

		def generate_task3
			# task3の生成
			task = 'task3'

			# 設定ファイルで明示しているdependencyを一応チェック． 
			task_dependency = settings.task_dependency[task]
			return 0 unless task_dependency.include?('task1') 
			return 0 unless task_dependency.include?('task2')
			return 0 unless task_dependency.size == 2
			
			existing_tickets = Ticket.where(task: task)
			
			seed_task1 = Ticket::where(task:'task1',completion:true)
			
			STDERR.puts seed_task1.size
		
			
			#recipes = MicroTask::where(task:'task2')
			count = 0
			count_no_annotation = 0
			for seed in seed_task1 do
				# validate
				# 本当は複数ユーザからの入力に対して正しい答えを判定したい!!
				# 別関数で統合を促す．(←答えの一致はチェック済み→どれを選んでも一緒)
				mtask = MicroTask::where(task:'task1',blob_id:seed.blob_id)[0]
				raise "no mtask of blob_id: #{seed.blob_id} has been found." unless mtask
				
				unless mtask['annotation'] then
					count_no_annotation = count_no_annotation+1
					next
				end
				

				# recipeを取得
				_id = task + "_" + mtask['blob_id']
				blob_id = mtask['blob_id']
				blob_path = seed['blob_path']

				# blob_id: 2014RC01_S008:extract:cameraA:PUT:putobject_0003941_061
				buf = blob_id.split(":")
				event = buf[-2]
				obj_id = [buf[0],buf[2],buf[-1].split("_")[-1]].join(":")
				
				recipe_id = buf[0].split("_")[0]
			
				# 本当は複数ユーザからの入力に対して正しい答えを判定したい!!
				# 別関数で統合を促す．
				recipe_info = MicroTask::where(task:'task2',blob_id:recipe_id).sample
				
				next unless recipe_info
				
				is_single_object = (mtask['annotation'].size==1)
				
				annotation_count = 0
				
				# before imageなどの登録
				regex = '(.*\/)extract\/(.+\/).+\/\w+_(\d{7})_\d{3}(.png)'
				md = blob_path.match(regex)
			
				
				for annotation in mtask['annotation'] do
						next if annotation['width']<=0
						next if annotation['height']<=0
						ticket = Ticket.new(_id: _id + "_#{annotation_count}", blob_id: blob_id + "::#{annotation_count}", task: task, blob_path: blob_path, annotator:[])
						ticket['event'] = event
						ticket['obj_id'] = obj_id
						ticket['candidates'] = recipe_info['ingredients'] + recipe_info['seasonings'] + recipe_info['utensils']
						ticket['box'] = annotation



						type = annotation['type']
						
						raw_image =  md[1..-1].join()
						if type == 'put' then
							# do nothing
						elsif type == 'taken' then
							raw_image = get_prev_file(settings.image_blob_path + raw_image)
							raw_image = raw_image.sub(settings.image_blob_path, '')
						else
							raise "Unknown annotation type '#{type}' for micro task _id: #{mtask['_id']}."
						end
						
						ticket['raw_image'] = raw_image

						next unless Ticket::where(_id: ticket._id).empty?
						
						ticket.save!
						count = count + 1
						annotation_count = annotation_count + 1
				end
				
			end			
			STDERR.puts "no annotation tickets: #{count_no_annotation}"  
			count
		end



		

		

	end
end
