require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'active_support/all'
require 'base64' # for task_pedes_count

# templates

require 'sass'
require 'haml'
$LOAD_PATH.push('/Users/ahashimoto/.rbenv/versions/2.1.2/lib/ruby/gems/2.1.0/gems/coffee-script-2.4.1/lib/')
require 'coffee-script'

$LOAD_PATH.push(File.dirname(__FILE__))
require_relative 'model_mongoid/user'
require_relative 'model_mongoid/microtask'
require_relative 'model_mongoid/ticket'
require_relative 'model_mongoid/passback'
require_relative 'model_mongoid/ticket_pool'

# lib/Utilsはmodel_mongoidの各ファイルより後ろでrequireする．
require_relative 'lib/Utils'
require_relative 'lib/TicketGeneration'
require_relative 'lib/CheckCompletion'

Mongoid.load!("mongoid.yml", :development)



class KUSKAnnotator < Sinatra::Base
  configure do
    #Load configure file
    register Sinatra::ConfigFile
    DELETE_FROM_HISTORY = [:_id,:worker,:blob,:task]
    NULL_TIME = Time.new(1981,1,1,0,0,0)
    END_STATE = ['complete','time_up','abort']
  end
	register Helpers::Utils
	register Helpers::TicketGeneration
	register Helpers::CheckCompletion

	use Rack::MethodOverride
#	enable :sessions
#	set :session_secret, "My session secret"
  use Rack::Session::Cookie, :key=>'rack.session',:path=>'/',:secret=>'My session secret'
	# configureは宣言順に実行される．

	configure :development do
		register Sinatra::Reloader
		config_file "#{settings.root}/config_dev.yml"
	end
	configure :production do
		config_file "#{settings.root}/config.yml"
  end

  set :tasks,{}
	configure do
    # settings.tasksに各タスクを処理するクラス(singletonが望ましい)のインスタンスを登録する
    require_relative("my_tasks/MyTask.rb")
    MyTask::set_default_config(settings.my_tasks[:default])
    MyTask::set_util_funcs({time2sec:method(:time2sec),parse_time:method(:parse_time)})
    for key,val in settings.my_tasks do
      next unless key=~/\A(task.+)\Z/
      require_relative("my_tasks/#{$1.camelize}.rb")
      settings.tasks[$1] = $1.classify.constantize.new(val)
    end
    settings.my_tasks.with_indifferent_access

    # mongodへの接続
		session = Moped::Session.new([settings.mongodb])
		session.use "testdb"
		Mongoid::Threaded.sessions[:default] = session

    # TimeZoneの設定
    Time.zone = settings.timezone

    # task2のためにontologyを読み込む
		#set :synonyms, load_synonyms
	end

  # スタイルシートのscssによる生成
	get '/scss/:basename' do |basename|
		scss :"scss/#{basename}"
  end

  # java scriptのcoffee scriptからの生成
  get '/coffee/:java_file' do |java_file|
    coffee :"coffee/#{java_file}"
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

  # ユーティリティURLs
  # 進行状況の表示
  get '/progress' do
    login_check
    @title = "作業進行状況"
    @ticket_counts = {}
    data_list = Dir.glob("#{settings.image_blob_path}/20*").map{|v|File.basename(v)}.sort
    @tasks = [['task1','cameraA'],['task1','cameraB'],['task1','cameraC'],'task3','task4']
#    @tasks = ['task1','task2','task4']
    for id in data_list do
      @ticket_counts[id] = {}
      for task in @tasks do
        counts = {tickets:{}, completed:{}, incomplete:{}, passbacks:{}}
        if task.is_a?(Array) then
          query = {task:task[0],blob_id:/#{id}.*#{task[1]}/}
        else
          query = {task:task,blob_id:/#{id}/}
        end
        tickets = Ticket::where(query)
        counts[:tickets] = tickets.count
        counts[:completed] = tickets.where(completion:true).count
        counts[:passbacks] = Passback::where('ticket.task'=>task,'ticket.blob_id'=>/#{id}/).count
        @ticket_counts[id][task] = counts
      end
    end

    haml :'progress'
  end

  # チケットプールの更新
  get '/refresh_ticket_pool/:task' do |task|
    TicketPool.where({task:task}).each{|tp| tp.destroy}
    settings.tasks[task].refresh_ticket_pool
    #pools = refresh_ticket_pool(task,settings)
    return "refreshed!"
  end


  get '/rest' do
		login_check

		blob = now
		mtask_id = "#{@user}::rest::#{blob}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end

		@meta_tags = MyTask::generate_meta_tags_base(nil,nil,session[:current_task],@user)
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

    # タスクの割り振り

    # checkかtaskか
    ticket = nil
    chain_duration_sec = time2sec(settings.chain_duration)
    if session.has_key?(:chain_task) and session[:chain_task] then
      tp = TicketPool.where(_id:session[:chain_task])
      if tp.count == 1 then
        tp = tp[0]
        if tp.is_active?(@user,chain_duration_sec) then
          ticket_id = tp.next_task(@user)
          ticket = Ticket.find(ticket_id) if ticket_id
        else
          tp.users.delete(@user)
          tp.save!
        end
      else
        # ticketがないので，次のunless ticketに入る
        # puts "#{__FILE__} at line #{__LINE__}."
      end
    end

    unless ticket then
      session[:chain_task] = nil
      tp, ticket_id = TicketPool.select(@user,chain_duration_sec)
      unless tp then
        redirect "/end/#{END_STATE[0]}", 303
      end
      session[:chain_task] = tp._id
      ticket = Ticket.find(ticket_id)
    end

    STDERR.puts "ERROR: failed to save tpool" unless tp.save!
    STDERR.puts "ERRORRRRRRRRRRRR!!!!!!!!!!!!!\n\n\n\n" if ticket == nil
		session[:ticket] = ticket['_id']
    puts "#{__FILE__}: #{__LINE__}"
    puts ticket
    if tp.pool_type == :check then
      redirect "/check/#{ticket.task}/#{ticket.blob_id}", 303
    end
		redirect "/task/#{ticket.task}/#{ticket.blob_id}", 303
	end

	get '/task/:task/*' do |task,blob_id|
		@ticket = Ticket.where(_id:session[:ticket])[0].as_json
		redirect '/task', 303 unless @ticket
		@ticket = @ticket.with_indifferent_access
		redirect '/task', 303 unless @ticket[:task] == task
		redirect '/task', 303 unless @ticket[:blob_id] == blob_id

		mtask_id = "#{@user}::#{task}::#{blob_id}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
		end

    @task = settings.tasks[task]
    @meta_tags = @task.generate_meta_tags(@ticket,session[:current_task],@user)

		if params.include?('checker') then
			#STDERR.puts "===========CHECKER: #{params['checker']}"
			@meta_tags[:checker] = @user
			@meta_tags[:min_work_time] = settings.checker_work_time
    end


		@title = "#{task.camelize} for #{blob_id}"
		
		# 新しいタスクに対するhamlファイルをここに書く
		#haml :"contents/#{task}"
    haml @task.view_path_task.to_sym

  end



	get '/overwrite' do
		@title = "データ再登録の確認画面"
		@meta_tags[:min_work_time] = time2sec(settings.min_overwrite_time).to_s


		@new_inputs = session[:temp_inputs]
		haml :'contents/overwrite'
	end

	post '/annotation' do
		#STDERR.puts 'in post /annotation do'
		#STDERR.puts @user
		login_check
    puts Time.zone
		curr_time = Time.now.localtime

		
		mtask = MicroTask.new(_id: params[:_id], worker: params[:worker], time_range: [parse_time(params[:start_time]),curr_time],min_work_time: params[:min_work_time],task: params[:task])
		mtask.blob_id = params[:blob_id] #if params.include?(:blob_id)

    task_name = params[:task]

    # 既に登録済みのマイクロタスクかどうかの確認
		prev_task = MicroTask.duplicate?(params[:_id])

    puts "#{__LINE__}: #{params.keys}"
    if prev_task and !(params.include?("checker")) then
			if nil == params[:overwrite] then
        # COOKIEに入りきらないデータがある場合のための処理
        # よく考えたらparamsをqueryとして送ってしまえばCOOKIEに置く必要はない
        # 今後，改修することがあれば．
        task = settings.tasks[task_name]
        hash = task.overwrite_hook(params.deep_dup,@user) if task.respond_to?(:overwrite_hook)


        session[:temp_inputs] = {}
				for key,val in hash do
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


    if task_name == 'rest' then
      # 現在のマイクロタスクを終了したことを明示
      session[:start] = Time.new
      session[:current_task] = nil
      redirect '/task', 303 if task_name=='rest'
    end


    task = settings.tasks[task_name]
    puts "#{__LINE__}: #{params.keys}"

    annotation = task.parse_annotation(params)
    raise 500, "タグが不正である可能性があります．" if annotation==nil
    raise 500, "#{task_name}実装上のエラー: アノテーション記録用Hashのキーにシステムの予約語が使われています" unless annotation.keys & mtask.fields.keys
    for key,val in annotation do
      mtask[key] = val
    end


		case task_name
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
			else
				#STDERR.puts "ERROR: unknown task '#{params[:task]}' is posted."
		end
				
		if MicroTask.where(:_id=>mtask._id).count == 0 then
			unless mtask.save then
				raise 500, "mongodbへのmicrotaskの保存に失敗しました"
			end		
		end

		# 現在のマイクロタスクを終了したことを明示
		session[:current_task] = nil
		
		redirect '/task', 303 if task_name=='rest'

		# マイクロタスク終了の判定を行う
		ticket = search(Ticket,mtask[:task],mtask[:blob_id])
		unless ticket.annotator.include?(mtask['worker']) then
				ticket.annotator << mtask['worker']
		end
		
		
		if params.include?('checker') then
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

      # checkが終わればticket_poolから削除
      tp = TicketPool.where(_id:session["chain_task"])

      # tp.countが0の場合は，他の人がそのTicketPoolを終わらせたレアケースとなるはず．
      if tp.count == 1 then
        tp = tp[0]
        res = tp.delete_ticket(ticket._id)
        session["chain_task"] = nil if res == :get_empty
      end

			#redirect "/check/#{task}"

		else
			# 通常のannotation post
			mtasks = search_micro_tasks(ticket)
			min_mtask_num = task.config[:minimum_micro_task_num]
			if mtasks.size >= min_mtask_num then
        # completion = trueならticket_poolから削除
        tp = TicketPool.where(_id:session["chain_task"])

        if check_completion(ticket,mtasks) then
				  ticket.completion = true

          # tp.countが0の場合は，他の人がそのTicketPoolを終わらせたレアケースとなるはず．
          if tp.count == 1 then
            tp = tp[0]
            res = tp.delete_ticket(ticket._id)
            session[:chain_task] = nil if res == :get_empty
          end

        else
				  Passback.execute(ticket,mtasks)
          if tp.count == 1 then
            tp = tp[0]
            res = tp.task2check(ticket._id)
            session[:chain_task] = nil if res == :get_empty
          end
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
			num = settings.tasks[task].generate_tickets
			return "#{task}: #{num} ticket(s) are newly generated."
	end
	
	# dataへのアクセス
  get '/data_path/:task/*' do |task,file_path|
    path = settings.tasks[task].config[:data_path] + "/" +  file_path
    send_file path
  end

  get '/view/:task/*' do |task,blob_id|
    @title = "View #{task} for #{blob_id}"
    tickets = Ticket.where(task:task, blob_id:blob_id)
    pass if tickets.size < 1
    raise 500 if tickets.size > 1
    @ticket = tickets[0]
    @mtasks = MicroTask.where(task:task,blob_id:blob_id)
    dummy_current_task = {:id=>"dummy_user::#{blob_id}",:start_time=>now}
    @task = settings.tasks[task]
    @meta_tags = @task.generate_meta_tags(@ticket,dummy_current_task,'dummy_user')

    haml "#{task}/view".to_sym
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

		ticket = Ticket.select_ticket(@user,settings.minimum_micro_task_num,settings.ticket_sampling_strategy,true,{task=>1.0})
		session[:ticket] = ticket['_id']
		return "No more tickets that shoud be checked" unless ticket
		redirect "/check/#{ticket.task}/#{ticket.blob_id}", 303
	end

	get '/check/:task/*' do |task,blob_id|
		login_check
		@ticket = Ticket.where(_id:session[:ticket])[0]
		@title = "CHECK #{task} for #{blob_id}"
		#return target.ticket['_id']
		
		mtask_id = "#{@user}::#{task}::#{blob_id}"
		if !session[:current_task] or mtask_id != session[:current_task][:id] then
			session[:current_task] = {:id=>mtask_id,:start_time=>now}
    end

    STDERR.puts "ERROR: invalid blob_id: #{blob_id} != #{@ticket['blob_id']}.\n\n\n\n" unless blob_id == @ticket['blob_id']
		
		blob_id = @ticket['blob_id']
    @task = settings.tasks[task]
		@meta_tags = @task.generate_meta_tags(@ticket,session[:current_task],@user)
    @meta_tags[:checker] = @user

#		@meta_tags['min_work_time'] = 0
		puts "in /check/#{task}/#{blob_id}: ticket = #{@ticket}"
    puts "#{@ticket['_id']}"

    passbacks = Passback.where("ticket._id"=>@ticket['_id'])
		@micro_tasks = []
		for p in passbacks do
			@micro_tasks += p.micro_tasks
    end
    count = MicroTask.where(task:task).count
		for mtask in MicroTask.where(task:task,blob_id:blob_id) do
			@micro_tasks << mtask
		end
		#return "#{micro_tasks.size} micro_tasks has been found."

    # taskとcheckの違いは@micro_tasksの有無
    haml @task.view_path_check.to_sym
	end
=begin
	#アノテーションのhelpへのリンク(未完成)
	get '/help/:task' do |task|
		@title = "#{task.upcase}のHelp"

		haml :"help/#{task}", :layout=>:layout_help
	end
=end

  # MyTaskクラスの独自関数を呼び出すパス
  get '/call/:task/:func' do |task,func|
    path = send(settings.tasks[task].send(func.to_sym,params))
    @params[:task_name] = task
    @params = params.with_indifferent_access
    @params[:task] = settings.tasks[task]
    haml path.to_sym
  end
end
