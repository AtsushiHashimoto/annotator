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
require_relative 'lib/Utils'

Mongoid.load!("mongoid.yml", :development)

LOGIN_PATH = "/log_in"
DELETE_FROM_HISTORY = [:_id,:worker,:blob,:task]
NULL_TIME = Time.new(1981,1,1,0,0,0)

class KUSKAnnotator < Sinatra::Base
		register Helpers::Utils

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
			session[:message] = nil
			session[:start] = Time.new
			haml :"user/log_in"
		end
		#login action
		post '/session' do
			_user = User.authenticate(params[:email], params[:password])
			if _user
				session[:user_id] = _user._id
				redirect '/users'
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
		#user dashboard
		get '/users' do
			login_check
			mtask_id = "#{@user.name}::test::#{now}"
			if nil == session[:current_task] or mtask_id == session[:current_task][:id] then
				session[:current_task] = {:id=>mtask_id,:start_time=>now}
			end

			@title="ダッシュボード"
			#			STDERR.puts time2sec(settings.test[:min_work_time])
			@meta_tags << {:class=>:_id,:val=>session[:current_task][:id]}
			@meta_tags << {:class=>:worker, :val=>@user.name}
			@meta_tags << {:class=>:start_time, :val=>session[:current_task][:start_time]}
			@meta_tags << {:class=>:min_work_time, :val=>time2sec(settings.test[:min_work_time]).to_s}			
			@meta_tags << {:class=>:task,:val=>'test'}
			@meta_tags << {:class=>:blob,:val=>'testblob'}
			
			haml :"contents/dashboard"
		end

    get '/' do
			login_check
			redirect "/task",303
    end






    get '/task' do
			login_check
			
			# 次のタスクに行くか，終了するかの判定．
			go_on = Time.new - session[:start] < time2sec(settings.work_time)
			if go_on then
				task,blob = select_task_or_nil(@user)
			else
				task = "rest"
				blob = now
				session[:start] = NULL_TIME
			end

			if task == nil then
				@title = "作業は全て終了しました"
				return haml :'contents/end'
			end

			redirect "/task/#{task}/#{blob}",303
    end

		get '/task/:task/:blob' do |task,blob|
			
			login_check
			mtask_id = "#{@user.name}::#{task}::#{blob}"
			if nil == session[:current_task] or mtask_id == session[:current_task][:id] then
				session[:current_task] = {:id=>mtask_id,:start_time=>now}
			end
			
			
			min_work_time = settings.min_work_time[task]
			
			@meta_tags << {:class=>:_id,:val=>session[:current_task][:id]}
			@meta_tags << {:class=>:worker, :val=>@user.name}
			@meta_tags << {:class=>:start_time, :val=>session[:current_task][:start_time]};
			@meta_tags << {:class=>:min_work_time, :val=>time2sec(min_work_time).to_s}
			@meta_tags << {:class=>:task,:val=>task}
			@meta_tags << {:class=>:blob,:val=>blob}
			
			@title = "Task #{task}"
			
			# ユーザ名などの取得
			# 新しいタスクに対するhamlファイルをここに書く
			haml :"contents/task_#{task}"
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
				STDERR.puts temp
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

end