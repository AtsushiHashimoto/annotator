require 'sinatra/extension'

module Helpers
	module Utils
		extend Sinatra::Extension
		
		def self.registered(app)
			app.helpers Utils
		end
	
		def now
			Time.new.strftime("%Y.%m.%d_%H.%M.%S.%L")
		end
		
		def guess_end_time
			total_work_time = time2sec(settings.standard_total_work_time)
			curr = Time.new + total_work_time
			min = 15 * (curr.min / 15).to_i
			Time.new(curr.year,curr.month,curr.day,curr.hour,min,0)
		end
		
		def login_check
			unless @user then
				redirect LOGIN_PATH, 303
			end			
		end
	
		def parse_time(timestamp_str)
			buf = /(\d{4}).(\d{2}).(\d{2})_(\d{2}).(\d{2}).(\d{2}).(\d+)/.match(timestamp_str)
			return nil unless buf
			Time.utc($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,"#{$6}.#{$7}".to_r)
		end
		
		def time2sec(time_str)
			buf = /(\d{0,2}):(\d{1,2}.*)/.match(time_str)
			return 0 if nil == buf[0]
			min = $1.to_i
			sec = $2.to_r
			hour = (min / 60).to_i
			min = min - 60 * hour
			#			STDERR.puts "#{hour}:#{min}:#{sec}"
			(Time.utc(0,1,1,hour,min,sec) - Time.utc(0,1,1,0,0,0)).to_i
		end

		def generate_meta_tags_base(ticket=nil)
			meta_tags = {}
			meta_tags[:_id] = session[:current_task][:id]
			meta_tags[:worker] = @user
			meta_tags[:start_time] = session[:current_task][:start_time];
			return meta_tags unless ticket
			meta_tags[:blob_id] = ticket[:blob_id]
			meta_tags[:min_work_time] = time2sec(settings.min_work_time[ticket[:task]]).to_s
			for key,val in ticket.as_json do
				# 既にあるハッシュ要素は上書きしない(_id)など
				next unless val
				next if val.respond_to?(:'empty?') and val.empty?
				next if meta_tags.include?(key.to_sym)
				meta_tags[key.to_sym] = val.to_s
			end
			meta_tags
		end
		
		def generate_meta_tags(ticket)
			meta_tags = generate_meta_tags_base(ticket)
				
			task = ticket['task']
			case task
				when 'task1'
				meta_tags[:image_width] = settings.image_width
				meta_tags[:image_height] = settings.image_height
				meta_tags[:diff_image] = generate_diff_image(ticket[:after_image],ticket[:before_image], ticket[:blob_path]);
				meta_tags[:mask_image] = generate_mask_image(ticket[:blob_path])
				when 'task2'
				synonyms = settings.synonyms
				candidates = ticket[:candidates].with_indifferent_access
				meta_tags[:list_ingredient] = synonyms[:ingredient].to_json
				meta_tags[:list_utensil   ] = synonyms[:utensil   ].to_json
				meta_tags[:list_seasoning ] = synonyms[:seasoning ].to_json
				meta_tags[:overview] = ticket[:blob_path] + "/" + settings.task2[:overview]
				when 'task3'
				meta_tags[:image_width] = settings.image_width
				meta_tags[:image_height] = settings.image_height
				meta_tags[:candidates] = ticket['candidates'].to_json
				meta_tags[:box] = ticket['box'].to_json
				meta_tags[:mask_image] = generate_mask_image(ticket[:blob_path])
			end
			meta_tags
		end
		
		
		def extract_recipe_id(str)
				md = str.match(settings.recipe_id_regex)
				return nil unless md
				md[1]
		end
		
		def get_blob_image_path(path)
				"/blob_images" + path
		end
		
		def get_prev_file(path)
				dir = File.dirname(path)
				basename = File.basename(path)
				common_dir = File.dirname(dir)
				camera_name = File.basename(dir)
				return common_dir + "/BG/" + camera_name + "/bg_" + basename
=begin
				extname = File.extname(path)
				dir = File.dirname(path)
				files = Dir.glob(dir+ "/*"+extname).sort
				index = files.index(path)
				return nil if 0 == index
				return files[index-1]
=end
		end
		
		def load_synonyms
			hash = Hash.new{|h,k| h[k] = []}
			File.open(settings.task2[:synonims]).each{|line|
					type, value, description = line.split("\t").map{|v|v.strip}
					type = type.split("-")[0]
					case type
						when '材料'
							type = :ingredient
						when '調味料'
							type = :seasoning
						when '調理器具'
							type = :utensil
						when '動作'
							hash[:verb] << [value,description]
							next
					end
					hash[type] << "#{description}"
			}
			hash
		end

		# task1の補助関数
		def generate_diff_image(_image1,_image2, orig_blob_path)
			image1 = settings.image_blob_path + _image1
			image2 = settings.image_blob_path + _image2
			dir = settings.image_blob_path + File.dirname(orig_blob_path).sub('extract','diff')
			`mkdir -p #{dir}`
			output_image1 = "#{dir}/#{File.basename(image1)}"
			unless File.exist?(output_image1) then
				output_image2 = "#{dir}/image2_#{File.basename(image1)}"
				`composite -compose difference #{image1} #{image2} #{output_image1}` 
				`composite -compose difference #{image2} #{image1} #{output_image2}` 
				`composite -compose add #{output_image1} #{output_image2} #{output_image1}`
				`convert #{output_image1} -colorspace Gray -modulate #{settings.task1[:modulation]} #{output_image1}`
				`rm #{output_image2}`
			end
			return output_image1.sub(settings.image_blob_path,"")
		end

		def generate_mask_image(blob_image)
			path = settings.image_blob_path + blob_image
			dir = File.dirname(path).sub('extract','mask')
			`mkdir -p #{dir}`
			output_image = "#{dir}/#{File.basename(path)}"
			unless File.exist?(output_image)
				`convert -type GrayScale -threshold 1 #{path} #{output_image}`
			end
			return output_image.sub(settings.image_blob_path,"")
		end

		###############################
		## MongoDB 操作関連
		###############################
		def search(collection_class,task,blob_id, expectation=:singleton)
			records = collection_class.where({:task=>task,:blob_id=>blob_id})
			if expectation==:singleton then
				raise "No record has been found." if records.empty?
				raise "Too many records are found." if records.size > 1
				return records[0]
			end
			
			raise "No record has been found." if records.empty? and expectation==:exist	
			return records
		end
		
		def search_micro_tasks(ticket)
			puts ticket.task
			puts ticket.blob_id
			return search(MicroTask, ticket.task, ticket.blob_id, :no_expectation)
		end
	end
end