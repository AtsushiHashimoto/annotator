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
		settings.image_blob_globpath = "#{settings.image_blob_path}/#{settings.image_blob_globpath}"
		settings.recipe_blob_globpath = "#{settings.recipe_blob_path}/#{settings.recipe_blob_globpath}"
		session = Moped::Session.new([settings.mongodb])
		session.use "testdb"
		Mongoid::Threaded.sessions[:default] = session
		
		# task2のためにontologyを読み込む
		set :synonyms, load_synonyms
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
	post '/sign_up' do
		if params[:password] != params[:confirm_password]
			redirect "/sign_up"
		end

		user = User.new(email: params[:email], name: params[:name])
		user.encrypt_password(params[:password])
		if user.save!
			session[:start] = Time.new
			session[:user_id] = user._id
			end_time = guess_end_time
			end_date = Time.new
			session[:end] = Time.new(end_date.year,end_date.month,end_date.day,
														 end_time.hour,end_time.min,0)
			redirect "/task" #user dashboard page
		else
			redirect "/sign_up"
		end
	end

	#共通の処理
	before do			
		@user = User.where(_id: session[:user_id]).first
		@meta_tags = {}
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
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end

		@meta_tags = generate_meta_tags
		@meta_tags[:task] = 'rest'
		@meta_tags[:blob] = blob
		@meta_tags[:min_work_time] = time2sec(settings.rest_time).to_s
		@title = "休憩を取って下さい"
		haml :'contents/rest'
	end

	get '/end/:state' do |state|
		login_check
		raise 500, "不正な終了状況'#{state}'です．" unless END_STATE.include?(state)
		@title = "作業終了"
		@state = state
		haml :'contents/end'
	end

  # タスクの表示
	get '/task' do
		session[:ticket] = nil
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
		ticket = Ticket.select_ticket(@user.name)
		unless ticket then
			# 一度，生成を試みる
			ticket = Ticket.select_ticket(@user.name)
			unless ticket then
				redirect "/end/#{END_STATE[0]}", 303
			end
		end	
		session[:ticket] = ticket.as_json
		redirect "/task/#{ticket.task}/#{ticket.blob_id}", 303
	end

	get '/task/:task/:blob_id' do |task,blob_id|
		@ticket = session[:ticket]
		redirect '/task', 303 unless @ticket
		@ticket = @ticket.with_indifferent_access
		redirect '/task', 303 unless @ticket[:task] == task
		redirect '/task', 303 unless @ticket[:blob_id] == blob_id
		
		mtask_id = "#{@user.name}::#{task}::#{blob_id}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end
		
		
		@meta_tags = generate_meta_tags(@ticket)
		if task != @ticket[:task] or blob_id != @ticket[:blob_id]
			# URLとキャッシュが合わない⇢ブラウザの戻るボタン⇢待ち時間を減らす
			@meta_tags[:min_work_time] = "1"
		end

		case task
			when 'task1'
				@meta_tags[:image_width] = settings.image_width
				@meta_tags[:image_height] = settings.image_height
				@meta_tags[:diff_image] = generate_diff_image(@ticket[:after_image],@ticket[:before_image], @ticket[:blob_path]);
				@meta_tags[:mask_image] = generate_mask_image(@ticket[:blob_path])
			when 'task2'
				@synonyms = settings.synonyms
				@candidates = @ticket[:candidates].with_indifferent_access
				@meta_tags[:list_ingredient] = @synonyms[:ingredient].to_json
				@meta_tags[:list_utensil   ] = @synonyms[:utensil   ].to_json
				@meta_tags[:list_seasoning ] = @synonyms[:seasoning ].to_json
				@meta_tags[:overview] = @ticket[:blob_path] + "/" + settings.task2[:overview]
			when 'task3'
				@meta_tags[:image_width] = settings.image_width
				@meta_tags[:image_height] = settings.image_height
				@meta_tags[:candidates] = @ticket['candidates'].to_json
				@meta_tags[:box] = @ticket['box'].to_json
				@meta_tags[:mask_image] = generate_mask_image(@ticket[:blob_path])
		end
		
		@title = "#{task.upcase} for #{blob_id}"
		
		# 新しいタスクに対するhamlファイルをここに書く
		haml :"contents/#{task}"
	end



	get '/overwrite' do
		@title = "データ再登録の確認画面"
		@meta_tags[:min_work_time] = time2sec(settings.min_work_time[:overwrite]).to_s
		@new_inputs = session[:temp_inputs]
		haml :'contents/overwrite'
	end

	post '/annotation' do
		login_check
		curr_time = Time.new
		mtask = MicroTask.new(_id: params[:_id], worker: params[:worker], time_range: [parse_time(params[:start_time]),curr_time],min_work_time: params[:min_work_time],task: params[:task])
		mtask.blob_id = params[:blob_id] #if params.include?(:blob_id)
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
			when 'task1' then
				unless params[:annotation].empty? then
					# 空でなければtask1 の結果をパースして保存
					array =  JSON.parse(params[:annotation]).uniq
					#画像のサイズで正規化しておく．
					for i in 0...array.length do
						array[i] = array[i].with_indifferent_access
						array[i][:x] = array[i][:x].to_f / settings.image_width
						array[i][:width] = array[i][:width].to_f / settings.image_width
						array[i][:y] = array[i][:y].to_f / settings.image_height
						array[i][:height] = array[i][:height].to_f / settings.image_width
					end					
					mtask[:annotation] = array
				end
			when 'task2' then
				targets = [:ingredients,:utensils,:seasonings]
				for tar in targets do
					unless params.include?(tar.to_s) then
						raise 500, "空の入力欄(#{tar})があります"
					end
					mtask[tar] = params[tar].split(",")
				end
			when 'task3' then
				STDERR.puts params
				label = params[:label]
				case label
					when 'tools_not_in_list' then
						mtask[:label] = params[:other_tool]
					when 'mixture' then
						mtask[:label] = 'mixture' 
					else
						mtask[:label] = params[:label]
				end
			else
				STDERR.puts "ERROR: unknown task '#{params[:task]}' is posted."
		end
				
				
		unless mtask.save! then
			raise 500, "mongodbへのmicrotaskの保存に失敗しました"
		end		
		
		# 現在のマイクロタスクを終了したことを明示
		session[:current_task] = nil
		
		# Ticketの方に登録
		
		Ticket::add_annotator(mtask['worker'],mtask['task'],mtask['blob_id'])
		
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
	
	# dataへのアクセス
	get '/blob_images/*' do
		path = settings.image_blob_path + "/" +  params[:splat].join("/")
		send_file path	
	end
	
	get '/blob_recipes/*' do
		path = settings.recipe_blob_path + "/" +  params[:splat].join("/")
		send_file path	
	end
		
		
	#アノテーションのhelpへのリンク
	get '/help/:task' do |task|
		@title = "#{task.upcase}のHelp"

		haml :"help/#{task}", :layout=>:layout_help
	end
end
