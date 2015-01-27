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
require_relative 'model_mongoid/passback'

# lib/Utilsはmodel_mongoidの各ファイルより後ろでrequireする．
require_relative 'lib/Utils'
require_relative 'lib/TicketGeneration'
require_relative 'lib/CheckCompletion'

Mongoid.load!("mongoid.yml", :development)

LOGIN_PATH = "/log_in"
DELETE_FROM_HISTORY = [:_id,:worker,:blob,:task]
NULL_TIME = Time.new(1981,1,1,0,0,0)
END_STATE = ['complete','time_up','abort']

class KUSKAnnotator < Sinatra::Base
	register Helpers::Utils
	register Helpers::TicketGeneration
	register Helpers::CheckCompletion

	use Rack::MethodOverride
#	enable :sessions
#	set :session_secret, "My session secret"
	use Rack::Session::Cookie, :key=>'rack.session',:path=>'/',:secret=>'My session secret'
	
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
				
		set :checker_list, User.where(checker:true).map{|v| v.name}
		
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
		if @user then
			STDERR.puts 'in before do'
			@user = @user.name
			STDERR.puts @user
		end
		@meta_tags = {}
	end

	#login form
	get LOGIN_PATH do
		session.clear
		if @user
			redirect '/task'
		end 
		@title = "ログイン画面"
		@message = session[:message]
		@end_time = guess_end_time.strftime("%H:%M:%S")

		session[:message] = nil
		haml :"user/log_in"
	end

	#login action
	post '/session' do
		_user = User.authenticate(params[:email], params[:password])
		end_time = Time.strptime(params[:end], "%H:%M")
		end_date = Time.new
		session[:start] = Time.new
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
		mtask_id = "#{@user}::rest::#{blob}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end

		@meta_tags = generate_meta_tags_base
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
		#puts curr_time
		#puts session[:start]
		if curr_time - session[:start] > time2sec(settings.work_time) then
			session[:start] = NULL_TIME
			redirect '/rest', 303			
		end
		ticket = Ticket.select_ticket(@user, settings.minimum_micro_task_num, settings.ticket_sampling_strategy)
		unless ticket then
			# 一度，生成を試みる
			ticket = Ticket.select_ticket(@user, settings.minimum_micro_task_num, settings.ticket_sampling_strategy)
			unless ticket then
				redirect "/end/#{END_STATE[0]}", 303
			end
		end	
		session[:ticket] = ticket
		STDERR.puts "====================="
		STDERR.puts ticket._id
		redirect "/task/#{ticket['task']}/#{ticket['blob_id']}", 303
	end

	get '/task/:task/:blob_id' do |task,blob_id|
		@ticket = session[:ticket].as_json
		redirect '/task', 303 unless @ticket
		@ticket = @ticket.with_indifferent_access
		redirect '/task', 303 unless @ticket[:task] == task
		redirect '/task', 303 unless @ticket[:blob_id] == blob_id
		
		mtask_id = "#{@user}::#{task}::#{blob_id}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end
		
		
		@meta_tags = generate_meta_tags_base(@ticket)
		if task != @ticket[:task] or blob_id != @ticket[:blob_id]
			# URLとキャッシュが合わない⇢ブラウザの戻るボタン⇢待ち時間を減らす
			@meta_tags[:min_work_time] = "1"
		end
		
		if params.include?('checker') and am_i_checker? then
			STDERR.puts "===========CHECKER: #{params['checker']}"
			@meta_tags[:checker] = @user
			@meta_tags[:min_work_time] = 3
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
			when 'task4'
				@meta_tags[:blob_path] = File.dirname(@ticket['blob_path'])
				@meta_tags[:current_segment] = @ticket['blob_id'].split(':')[-1].to_i
				@local_blob_image_path = settings.image_blob_path
				@verbs = settings.synonyms[:verb]
				blob_id_common_part = @meta_tags[:blob_id].split(':')[0...-1].join(':')
				@past_labels = MicroTask.where(worker:@user,task:task,blob_id:/#{blob_id_common_part}:.+/).to_a.map{|v|[v['blob_id'].split(':')[-1].to_i,  v['label']]}
				@past_labels = Hash[*@past_labels.flatten]
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
		#STDERR.puts 'in post /annotation do'
		#STDERR.puts @user
		login_check
		curr_time = Time.new
		
		mtask = MicroTask.new(_id: params[:_id], worker: params[:worker], time_range: [parse_time(params[:start_time]),curr_time],min_work_time: params[:min_work_time],task: params[:task])
		mtask.blob_id = params[:blob_id] #if params.include?(:blob_id)

		
		# 既に登録済みのマイクロタスクかどうかの確認
		prev_task = MicroTask.duplicate?(params[:_id])
		if prev_task and !params.include?("checker") then
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
					if params[:annotation] == 'null' then
						array = []
					else
						array =  JSON.parse(params[:annotation]).uniq
					end
					#画像のサイズで正規化しておく．
					for i in 0...array.length do
						array[i] = array[i].with_indifferent_access
						array[i][:x] = array[i][:x].to_f / settings.image_width
						array[i][:width] = array[i][:width].to_f / settings.image_width
						array[i][:y] = array[i][:y].to_f / settings.image_height
						array[i][:height] = array[i][:height].to_f / settings.image_height
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
				#	STDERR.puts params
				label = params[:label]
				options = label.split('+')
				# STDERR.puts options.join(" ")
				label = options[0]
				case label
					when 'tools_not_in_list' then
						mtask[:label] = params[:other_tool]
						mtask[:note] = "description"
					when 'mixture' then
						mtask[:label] = 'mixture' 
					when 'option' then
						iter = options[1]
						label = options[2]
						key = "option_#{iter}"
						mtask[:label] = "#{label}::#{params[key]}"
						mtask[:note] = "option"
					else
						mtask[:label] = params[:label]
				end
			when 'task4' then
				mtask[:label] = params[:label]
			else
				STDERR.puts "ERROR: unknown task '#{params[:task]}' is posted."
		end
				
		if MicroTask.where(:_id=>mtask._id).count == 0 then
			unless mtask.save then
				raise 500, "mongodbへのmicrotaskの保存に失敗しました"
			end		
		end

		# 現在のマイクロタスクを終了したことを明示
		session[:current_task] = nil
		
		redirect '/task', 303 if task=='rest'

		# マイクロタスク終了の判定を行う
		ticket = search(Ticket,mtask[:task],mtask[:blob_id])
		unless ticket.annotator.include?(mtask['worker']) then
				ticket.annotator << mtask['worker']
		end
		
		
		if params.include?('checker') and am_i_checker? then
			# checkerによるannotation post
			# /check/:task からのpost→他のmtaskをpassback送りにして，今回の物だけ登録し，ticket=trueとする
			temp = search_micro_tasks(ticket)
			delete_mtasks = []
			for m in temp do
				delete_mtasks << m unless m._id==mtask._id
			end
			Passback.execute(ticket,delete_mtasks) unless delete_mtasks.empty?
			
			
			if ticket.checker == nil then
				ticket.checker = [params[:checker]]
				else
				ticket.checker << params[:checker]
			end
			STDERR.puts ticket
			
			ticket.completion = true
			
			unless ticket.save! then
				raise "failed to update ticket."
			end
			redirect "/check/#{task}"			

		else
			# 通常のannotation post
			mtasks = search_micro_tasks(ticket)
			min_mtask_num = settings.minimum_micro_task_num[task]
			if mtasks.size >= min_mtask_num then
					if check_completion(ticket,mtasks) then
						ticket.completion = true
					else
						Passback.execute(ticket,mtasks)
					end
			end
		end

		unless ticket.save! then
			raise "failed to update ticket."
		end
		
		
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
	
	# 終了かどうか一括でチェック
	get '/completion_check/:task' do |task|
		tickets = Ticket.where({:task=>task})
		min_mtask_num = settings.minimum_micro_task_num[task]
		ids = []
		for ticket in tickets do
		STDERR.puts "checking ticket: #{ticket._id}"
			mtasks = search(MicroTask,task,ticket.blob_id,:no_expectation)
			next if mtasks.empty?
			next if min_mtask_num > mtasks.size
			next if ticket.completion
			if mtasks.size >= min_mtask_num then
				if check_completion(ticket,mtasks) then
					ticket.completion = true
					unless ticket.save! then
						raise "failed to update ticket."
					end					
				else
					Passback.execute(ticket,mtasks)
					ids << ticket._id
				end
			end
			
			
		end
		return ids.join("\n")
	end
	
	# 一定人数以上のannotatorがいる場合にticketをresetする
	get '/reset_tickets/:task/:max_annotator' do |task,max_annotator|
		tickets = Ticket.where({:task=>task})
		max_annotator = max_annotator.to_i
		ids = []
		for ticket in tickets do
			next if ticket.annotator.size < max_annotator
			mtasks = search(MicroTask,task,ticket.blob_id,:no_expectation)
			annotators = mtasks.map{|v|v.worker}
			ticket.annotator = annotators
			raise "failed to save ticket" unless ticket.save! 
			ids << ticket._id
		end
		return ids.join("\n")
	end
	
	# debug用のパス
	get '/test' do
		ticket = Ticket.where(task:"task2")[0]
		mtasks = search_micro_tasks(ticket)
		check_completion(ticket,mtasks)
		ticket = Ticket.where(task:"task2")[0]
		return ticket['candidates'].flatten.join("\n")
	end
		
	# タグ付け結果確認用のパス
	get '/check/:task' do |task|
		login_check
		return 404 unless am_i_checker?
		
		ticket = Ticket.select_ticket(@user,settings.minimum_micro_task_num,settings.ticket_sampling_strategy,true,{task=>1.0})
		session[:ticket] = ticket
		return "No more tickets that shoud be checked" unless ticket
		STDERR.puts ticket
		redirect "/check/#{ticket.task}/#{ticket.blob_id}", 303
	end

	get '/check/:task/:blob_id' do |task,blob_id|		
		login_check
		return 404 unless am_i_checker?
		@ticket = session[:ticket]
		@title = "CHECK #{task} for #{blob_id}"
		#return target.ticket['_id']
		
		mtask_id = "#{@user}::#{task}::#{blob_id}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end
		
		blob_id = @ticket['blob_id']
		@meta_tags = generate_meta_tags(@ticket)

=begin
		if task != ticket[:task] or blob_id != ticket[:blob_id]
			# URLとキャッシュが合わない⇢ブラウザの戻るボタン⇢待ち時間を減らす
			meta_tags[:min_work_time] = "1"
		end
=end
#		@meta_tags['min_work_time'] = 0
		
		passbacks = Passback.where("ticket._id"=>@ticket['_id'])
		@micro_tasks = []
		for p in passbacks do
			@micro_tasks += p.micro_tasks
		end
		for mtask in MicroTask.where(task:task,blob_id:blob_id) do
			@micro_tasks << mtask
		end
		@task = task
		#return "#{micro_tasks.size} micro_tasks has been found."		

		case task
			when 'task2'
				redirect "/task/#{@ticket.task}/#{@ticket.blob_id}?checker=true",303
			when 'task4'
				@meta_tags[:blob_path] = File.dirname(@ticket['blob_path'])
				@meta_tags[:current_segment] = @ticket[:blob_id].split(':')[-1].to_i
				@local_blob_image_path = settings.image_blob_path
				@verbs = settings.synonyms[:verb]
				blob_id_common_part = @meta_tags[:blob_id].split(':')[0...-1].join(':')

				@fixed_labels = {}
				tickets = Ticket.where(task:task,blob_id:/#{blob_id_common_part}:.+/,completion:true)
				other_tasks = MicroTask.where(task:task,blob_id:/#{blob_id_common_part}:.+/)
				tickets.each{|t|
					STDERR.puts t.blob_id
					label = other_tasks.where(blob_id:t.blob_id)[0]['label']
					@fixed_labels[t['blob_id'].split(':')[-1].to_i] = label
				}
		end
		
		for key,val in @meta_tags do
			STDERR.puts "#{key}: #{val}"
		end



		haml :"check/#{task}"
	end
=begin
	#アノテーションのhelpへのリンク(未完成)
	get '/help/:task' do |task|
		@title = "#{task.upcase}のHelp"

		haml :"help/#{task}", :layout=>:layout_help
	end
=end
end
