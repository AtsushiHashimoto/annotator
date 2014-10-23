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
		
		def login_check
			unless @user then
				redirect LOGIN_PATH, 303
			end			
		end
		
	
		def parse_time(timestamp_str)
			buf = /(\d{4}).(\d{2}).(\d{2})_(\d{2}).(\d{2}).(\d{2}).(\d+)/.match(timestamp_str)
			return nil if nil == buf[0]
			Time.utc($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,"#{$6}.#{$7}".to_r)
		end
		
		def time2sec(min_sec)
			buf = /(\d{0,2}):(\d{1,2}.*)/.match(min_sec)
			return 0 if nil == buf[0]
			(Time.utc(0,1,1,0,$1.to_i,$2.to_r) - Time.utc(0,1,1,0,0,0)).to_i
		end
		
		def select_task_or_nil(user)
			# 完全にrandom?
			# ボトムアップ?
			# 深さ優先?

			return 'test',now
			nil
		end

	end
end