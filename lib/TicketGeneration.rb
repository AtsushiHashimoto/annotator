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
					return generate_task1(settings.image_blob_globpath,settings.image_blob_id_regex,settings.recipe_blob_globpath,settings.recipe_blob_id_regex)
				when 'task2'
					return generate_task2
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
			0
		end
		def generate_task2
			0
		end
		
		def generate_task1(image_blob_globpath, image_blob_id_regex,
			recipe_blob_globpath, recipe_blob_id_regex)
			all_blobs = Dir.glob(image_blob_globpath)
			# task1の生成
			task = 'task1'
			count = 0
			for blob_path in all_blobs do
				md = blob_path.match(image_blob_id_regex)
				next unless md
				blob_id = md[1]
				
				# 既に登録があれば再生成や上書きはしない
				_id = "#{task}_#{blob_id}"
				next if duplicate?(_id)
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