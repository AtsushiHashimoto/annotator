require 'sinatra/extension'

module Helpers
	module TicketGeneration
		extend Sinatra::Extension
		
		def self.registered(app)
			app.helpers TicketGeneration
		end
			
		def generate_tickets(task)
			case task
				when 'task1'
					return generate_task1(settings.image_blob_globpath,settings.image_blob_id_regex)
				when 'task2'
					return generate_task2(settings.recipe_blob_globpath,settings.recipe_blob_id_regex)
				when 'task3'
					return generate_task3
				when 'task4'
					return generate_task4
				when 'task5'
					return generate_task5
				when 'task6'
					return generate_task6
				else
					raise MyCustomError, "Unknown task '#{task}.'"
			end
		end

		def generate_task6
			0
		end
		def generate_task5
			0
		end
		def generate_task4
			0
		end
		def generate_task3
			# task3の生成
			task = 'task3'

			task_dependency = settings.task_dependency[task]
			return 0 unless task_dependency.include?('task1') 
			return 0 unless task_dependency.include?('task2')
			return 0 unless task_dependency.size == 2
			
			self_tickets = Ticket.where(task: task)
			ignore_ids = self_tickets.map{|ticket| ticket.blob_id}

			seeds = seed_tickets_image(ignore_ids,'task1')
			recipes = seed_tickets_recipe(ignore_ids, 'task2')
			
			count = 0
			for seed in seeds do
					md = seed.blob_id.match(settings.recipe_id_regex)
					next unless md
					recipe_id = md[1]
					STDERR.puts "#{recipe_id} X #{seed.blob_id}"
			end
			
			count
		end
			
		def seed_tickets_image(ignore_ids, parent_task)
			temp = Ticket.where({task: parent_task, completion: true})
			temp.delete_if{|ticket| ignore_ids.include?(ticket.blob_id)}
		end
		
		def seed_tickets_recipe(ignore_ids, parent_task='task2')
			Ticket.where({task: parent_task,completion: true})
		end
		
		def generate_task2(recipe_blob_globpath, recipe_blob_id_regex)
			all_blobs = Dir.glob(recipe_blob_globpath)
			# task2の生成
			task = 'task2'
			count = 0
			for blob_path in all_blobs do
					md = blob_path.match(recipe_blob_id_regex)
					next unless md
					recipe_id = md[1].gsub("/",":")
					
					next unless check_recipe_files(blob_path)
					
					# 既に登録があれば再生成や上書きはしない
					_id = "#{task}_#{recipe_id}"
					next if Ticket.duplicate?(_id)
					
					count = count + 1
					ticket = Ticket.new(_id: _id, blob_id: recipe_id, task: task, blob_path: blob_path)
					unless ticket.save! then
						raise MyCustomError, "新規チケットの発行に失敗しました"
					end					
			end
			count
		end
			
		def check_recipe_files(path)
			# レシピディレクトリの中に必要なファイルが揃っているかを確認する
			true
		end
		
		def generate_task1(image_blob_globpath, image_blob_id_regex)
			all_blobs = Dir.glob(image_blob_globpath)
			# task1の生成
			task = 'task1'
			count = 0
			for blob_path in all_blobs do
				md = blob_path.match(image_blob_id_regex)
				next unless md
				blob_id = md[1].gsub("/",":")
				
				# 既に登録があれば再生成や上書きはしない
				_id = "#{task}_#{blob_id}"
				next if Ticket.duplicate?(_id)
				count = count + 1
				ticket = Ticket.new(_id: _id, blob_id: blob_id, task: task, blob_path: blob_path)
				unless ticket.save! then
					raise MyCustomError, "新規チケットの発行に失敗しました"
				end
			end
			return count
		end
		
	end
end