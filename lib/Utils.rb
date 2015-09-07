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
			Time.new($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,"#{$6}.#{$7}".to_r)
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
		
		def generate_meta_tags(ticket)
			meta_tags = generate_meta_tags_base(ticket)
				
			task = ticket['task']
			case task
				when 'task3'
				meta_tags[:image_width] = settings.image_width
				meta_tags[:image_height] = settings.image_height
				meta_tags[:candidates] = ticket['candidates'].to_json
				meta_tags[:box] = ticket['box'].to_json
				meta_tags[:mask_image] = generate_mask_image(ticket[:blob_path])
			end
			meta_tags
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
