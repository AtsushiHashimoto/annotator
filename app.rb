require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'active_support/all'
require 'sass'
require 'haml'


$LOAD_PATH.push(File.dirname(__FILE__))
require_relative 'model_mongoid/user'
require_relative 'model_mongoid/microtask'
require_relative 'model_mongoid/ticket'

# lib/Utilsはmodel_mongoidの各ファイルより後ろでrequireする．
require_relative 'lib/Utils'
require_relative 'lib/TicketGeneration'

Mongoid.load!("mongoid.yml", :development)

LOGIN_PATH = "/log_in"
DELETE_FROM_HISTORY = [:_id,:worker,:blob,:task]
NULL_TIME = Time.new(1981,1,1,0,0,0)
END_STATE = ['complete','time_up','abort']

class KUSKAnnotator < Sinatra::Base
	register Helpers::Utils
	register Helpers::TicketGeneration

	use Rack::MethodOverride
	enable :sessions
	set :session_secret, "My session secret"
	
	
	# configureは宣言順に実行される．
	configure do        
		#Load configure file
		register Sinatra::ConfigFile
	end
	configure :development do
		register Sinatra::Reloader
		config_file "#{settings.root}/config_dev.yml"
	end
	configure :production do
		config_file "#{settings.root}/config.yml"
	end

	configure do
		session = Moped::Session.new([settings.mongodb])
		session.use "testdb"
		Mongoid::Threaded.sessions[:default] = session
	end


	get '/scss/:basename' do |basename|
		scss :"scss/#{basename}"
	end

	# ユーザ管理
	# signup form
	get '/sign_up' do
		@title = "ユーザ登録"

		session[:user_id] ||= nil 
		STDERR.puts "sign_up: #{session[:user_id]}"
		if @user
			redirect '/task' #logout form
		end 
		
		haml :"user/sign_up"
	end 

	#signup action
	post '/users' do
		if params[:password] != params[:confirm_password]
			redirect "/sign_up"
		end
		
		user = User.new(email: params[:email], name: params[:name])
		user.encrypt_password(params[:password])
		if user.save!
			session[:user_id] = user._id
			redirect "/users" #user dashboard page
		else
			redirect "/sign_up"
		end
	end

	#共通の処理
	before do			
		@user = User.where(_id: session[:user_id]).first
		@meta_tags = []
	end

	#login form
	get LOGIN_PATH do
		if @user
			redirect '/task'
		end 
		@title = "ログイン画面"
		@message = session[:message]
		@end_time = guess_end_time.strftime("%H:%M:%S")

		session[:message] = nil
		session[:start] = Time.new
		haml :"user/log_in"
	end
	#login action
	post '/session' do
		_user = User.authenticate(params[:email], params[:password])
		end_time = Time.strptime(params[:end], "%H:%M")
		end_date = Time.new
		session[:end] = Time.new(end_date.year,end_date.month,end_date.day,
														 end_time.hour,end_time.min,0)
		STDERR.puts session[:end]
		if _user
			session[:user_id] = _user._id
			redirect '/task'
		else
			session[:message] = "log in failed."
			redirect LOGIN_PATH
		end
	end

	#logout action
	delete '/session' do
		session[:user_id] = nil
		redirect LOGIN_PATH
	end


	# session内部のページ
	get '/' do
		login_check
		redirect "/task",303
	end


	get '/rest' do
		login_check

		blob = now
		mtask_id = "#{@user.name}::rest::#{blob}"
		if !session[:current_task] or mtask_id == session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end

		@meta_tags = generate_meta_tags
		@meta_tags << {:class=>:task,:val=>'rest'}
		@meta_tags << {:class=>:blob,:val=>blob}
		@meta_tags << {:class=>:min_work_time, :val=>time2sec(settings.rest_time).to_s}
		@title = "休憩を取って下さい"
		haml :'contents/rest'
	end

	get '/end/:state' do |state|
		login_check
		raise MyCustomError, "不正な終了状況'#{state}'です．" unless END_STATE.include?(state)
		@title = "作業終了"
		@state = state
		haml :'contents/end'
	end

  # タスクの表示
	get '/task' do
		login_check
		
		curr_time = Time.new
		# 終了予定時間のチェック
		if session[:end] < curr_time then
			redirect "/end/#{END_STATE[1]}"
		end
		# 休憩の判定
		if curr_time - session[:start] > time2sec(settings.work_time) then
			session[:start] = NULL_TIME
			redirect '/rest', 303			
		end
		ticket = Ticket.select_task
		unless ticket then
			# 一度，生成を試みる

			ticket = Ticket.select_task
			unless ticket then
				redirect '/end/#{END_STATE[0]}', 303
			end
		end			
		
		mtask_id = "#{@user.name}::#{ticket.task}::#{ticket.blob_id}"
		if !session[:current_task] or mtask_id == session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end
		@meta_tags = generate_meta_tags(ticket)

		@title = "#{ticket.task.upcase} for #{ticket.blob_id}"
		
		# 新しいタスクに対するhamlファイルをここに書く
		haml :"contents/#{ticket.task}"
	end



	get '/overwrite' do
		@title = "データ再登録の確認画面"
		@meta_tags << {:class=>:min_work_time, :val=>time2sec(settings.min_work_time[:overwrite]).to_s}
		@new_inputs = session[:temp_inputs]
		haml :'contents/overwrite'
	end

	post '/annotation' do
		login_check
		curr_time = Time.new
		mtask = MicroTask.new(_id: params[:_id], worker: params[:worker], time_range: [parse_time(params[:start_time]),curr_time],min_work_time: params[:min_work_time],task: params[:task])
		mtask.blob = params[:blob] if params.include?(:blob)
		# 既に登録済みのマイクロタスクかどうかの確認
		prev_task = MicroTask.duplicate?(params[:_id])
		if prev_task then
			if nil == params[:overwrite] then
				session[:temp_inputs] = {}
				for key,val in params do
					session[:temp_inputs][key] = val
					STDERR.puts "#{key} : #{val}"
				end
				redirect '/overwrite', 303
			else
				# /overwriteからのpost
				if nil == prev_task[:history]
					mtask[:history] = []
				else
					mtask[:history] = prev_task[:history]
					prev_task.delete(:history)
			end
			temp = prev_task.as_json.delete_if{|key,val|
				DELETE_FROM_HISTORY.include?(key.to_sym)
			}
			mtask[:history] << temp
			MicroTask.delete(params[:_id])
			end
		end
			

		# 新しいタスクに対するannotation結果の保存処理をここに書く!
		task = params[:task]
		case task
			when 'rest' then
				session[:start] = Time.new
			when 'test' then
				mtask[:annotation] = params[:annotation]
			else
				STDERR.puts "ERROR: unknown task '#{params[:task]}' is posted."
		end		
		
		unless mtask.save! then
			raise MyCustomError, "mongodbへのmicrotaskの保存に失敗しました"
		end		
		
		# 現在のマイクロタスクを終了したことを明示
		session[:current_task] = nil
		
		
		
		
		redirect "/task", 303
	end
		
	# Ticket管理
	get '/ticket/generate' do
		results = []
		for task in settings.tasks do
			num = generate_tickets(task)
			results << "#{task}: #{num} ticket(s) are newly generated."
		end
		return results.join("</br>\n")
	end
	get '/ticket/generate/:task' do |task|
			num = generate_tickets(task)
			return "#{task}: #{num} ticket(s) are newly generated."
	end

end