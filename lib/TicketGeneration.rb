require 'kconv'
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
				return generate_task4(settings.image_blob_path,settings.task4['video_dir'])

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
		def generate_task4(image_blob_path, video_dir)
			# task4の生成
			task = 'task4'
			
			extension = '.webm'
			# videosディレクトリがあるデータをチェック
			count = 0
			blob_image_dirs = Dir.glob(image_blob_path + "/*")
			STDERR.puts image_blob_path
			for dir in blob_image_dirs do
				STDERR.puts dir
				next unless dir =~ /#{image_blob_path}\/(.+)/
				data_id = $1
				dir = "#{dir}/#{video_dir}"
				STDERR.puts dir
				next unless File.exist?(dir)
				video_list = `find #{dir} | grep #{extension}`.split("\n").map{|v|
					File.basename(v.strip,extension)
				}.sort
				
				# segmentの情報を読み込む
				segment_file = dir + '/' + settings.task4['segment_file']
				segments = []
				File.open(segment_file,'r').each{|line|
					frame,time = line.split(',').map{|v|v.strip}
					segments << {:frame=>frame.to_i, :time=>time.to_f}
				}
				
				for i_str in video_list[0...-1] do
					i = i_str.to_i
					
					blob_id = "#{data_id}:video:#{i_str}"
					t_id = task + ':' + blob_id
				
					next unless Ticket::where(_id:t_id).empty?
					
					blob_path = "#{data_id}/#{video_dir}/#{i_str}#{extension}"
					
					ticket = Ticket.new(_id: t_id, blob_id: blob_id, task: task, blob_path: blob_path, annotator:[])
					
					ticket['start_frame'] = segments[i][:frame]
					ticket['start_time'] = segments[i][:time]
          next if i+1 == segment.size
          ticket['end_frame'] = segments[i+1][:frame]
					ticket['end_time'] = segments[i+1][:time]
					ticket['segment_num'] = segments.size-1
					
=begin
					STDERR.puts ""
					for key,val in ticket.as_json do
						STDERR.puts "#{key}: #{val}"
					end
=end
					unless ticket.save! then
						raise MyCustomError, "新規チケットの発行に失敗しました"
					end
					count = count + 1

				end
			end
			
			
			count
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
				raise "no mtask has been found." unless mtask
				
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

		def load_nlp_result_csv(dir)
			files = Dir.glob("#{dir}/*.csv")
			candidates = Hash.new{|h,k| h[k] = []}
			for file in files do
				buf = File.open(file,'r').read.toutf8
				words = buf.split("\n").map{|v|v.split(",")}.delete_if{|v|v.size < 4}
				words.map!{|v|v[3].strip}
				for key,array in settings.synonyms do						
					for word in words do
						next unless array.include?(word)
						candidates[key] << word
					end
					candidates[key].uniq!
				end
			end
			candidates
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
					blob_full_path = blob_path.clone
					blob_path.sub!(settings.recipe_blob_path,'')
					
					next unless check_recipe_files(blob_full_path)
					
					# 既に登録があれば再生成や上書きはしない
					_id = "#{task}_#{recipe_id}"
					next if Ticket.duplicate?(_id)
					
					count = count + 1
					ticket = Ticket.new(_id: _id, blob_id: recipe_id, task: task, blob_path: blob_path, annotator:[])
					
					# 食材，調理器具，調味料の候補を入れる．
					ticket[:candidates] = load_nlp_result_csv(blob_full_path)
					
					unless ticket.save! then
						raise MyCustomError, "新規チケットの発行に失敗しました"
					end					
			end
			count
		end
			
		def check_recipe_files(path)
			flag = true;
			# レシピディレクトリの中に必要なファイルが揃っているかを確認する
			if Dir.glob("#{path}/overview.*").empty? then
				flag = false
				STDERR.puts "overview.jpgがありません"
			end
			if Dir.glob("#{path}/*.csv").empty? then
				flag = false
				STDERR.puts "形態素解析結果がありません"	
			end
			flag
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
				blob_path.sub!(settings.image_blob_path, '')
				

				# before imageなどの登録
				regex = '(.*\/)extract\/(.+\/).+\/\w+_(\d{7})_\d{3}(.png)'
				md = blob_path.match(regex);
				unless md then
					STDERR.puts "Error: failed to parse blob_path into original image path"
					STDERR.puts "blob_path: '#{blob_path}'"
					STDERR.puts "regex: '#{regex}'"
					next
				end
				
				# 既に登録があれば再生成や上書きはしない
				_id = "#{task}_#{blob_id}"
				next if Ticket.duplicate?(_id)
				ticket = Ticket.new(_id: _id, blob_id: blob_id, task: task, blob_path: blob_path, annotator: [])
				
				
				after_image = md[1..-1].join()
				ticket[:after_image] = after_image
				before_image_path = get_prev_file(settings.image_blob_path + after_image)
				next if before_image_path == nil
				# 本当はここでnilなら背景画像を返すようにする
				ticket[:before_image] = before_image_path.sub(settings.image_blob_path, '')
				
				count = count + 1
				
				unless ticket.save! then
					raise MyCustomError, "新規チケットの発行に失敗しました"
				end
			end
			return count
		end
		
		

	end
end