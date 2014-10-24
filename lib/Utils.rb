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
			STDERR.puts "#{hour}:#{min}:#{sec}"
			(Time.utc(0,1,1,hour,min,sec) - Time.utc(0,1,1,0,0,0)).to_i
		end
		
		def generate_meta_tags(ticket=nil)
			meta_tags = []
			meta_tags << {:class=>:_id,:val=>session[:current_task][:id]}
			meta_tags << {:class=>:worker, :val=>@user.name}
			meta_tags << {:class=>:start_time, :val=>session[:current_task][:start_time]};
			return meta_tags unless ticket
			meta_tags << {:class=>:min_work_time, :val=>time2sec(settings.min_work_time[ticket.task]).to_s}
			meta_tags << {:class=>:task,:val=>ticket.task}
			meta_tags << {:class=>:blob,:val=>ticket.blob_id}
			meta_tags << {:class=>:ticket,:val=>ticket._id}
		end
		
		
		def extract_recipe_id(str)
				md = str.match(settings.recipe_id_regex)
				return nil unless md
				md[1]
		end

	end
end