require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'active_support/all'
require 'sass'
require 'haml'


$LOAD_PATH.push(File.dirname(__FILE__))
require_relative 'lib/user'
require_relative 'lib/Utils'

Mongoid.load!("mongoid.yml", :development)

class KUSKAnnotator < Sinatra::Base
		register Helpers::Utils

		use Rack::MethodOverride
		enable :sessions
		set :session_secret, "My session secret"

		configure do
        #set hyper parameters
        set :MyConffile, "config.yml"
        
        #Load configure file
        register Sinatra::ConfigFile
        config_file "#{settings.root}/#{settings.MyConffile}"

				session = Moped::Session.new(["localhost:4568"])
				session.use "testdb"
				Mongoid::Threaded.sessions[:default] = session
    end

    configure :development do
        register Sinatra::Reloader
    end

		get '/scss/:basename' do |basename|
			scss :"scss/#{basename}"
		end


		# ユーザ管理

		# signup form
		get '/sign_up' do
			@title = "ユーザ登録"

			session[:user_id] ||= nil 
			if session[:user_id]
				redirect '/go_on' #logout form
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

		#login form
		get '/log_in' do
			@title = "ログイン画面"
			if session[:user_id]
				redirect '/go_on'
			end 
			
			haml :"user/log_in"
		end

		#login action
		post '/session' do
			if session[:user_id]
				redirect "/users"
			end
			
			user = User.authenticate(params[:email], params[:password])
			if user
				session[:user_id] = user._id
				redirect '/users'
			else
			redirect "/log_in"
			end
		end

		#logout action
		delete '/session' do
			session[:user_id] = nil
			redirect '/log_in'
		end

		#共通の処理
		before do
			@user = User.where(_id: session[:user_id]).first
			@meta_tags = []
		end

    # session内部のページ
		#user dashboard
		get '/users' do
			@title="ダッシュボード"
			@user = User.where(_id: session[:user_id]).first
						
      @meta_tags << {:class=>:min_time, :val=>settings.test[:min_time]}
			if @user
				haml :"contents/dashboard"
			else
			redirect '/log_in'
			end
		end

    get '/' do
        unless @user then
            redirect "/log_in",303
        else
						redirect "/go_on",303
				end        
    end



    get '/task/:task/:blob_id' do |task,blob_id|
			  @title = "Task #{task}"
        # ユーザ名などの取得
				haml :"contents/task_#{task}"
    end

		get '/report' do
			#作業レポートを作成する
			#(毎回，これを提出するようにして，作業をさぼってないことを確認させる．)
		end

		post '/annotation/:task/:blob_id' do |task,blob_id|
        # 次のタスクに行くか，終了するかの判定．
				go_on = false
				
        if go_on then
            redirect "/task",303
        else
						@title = "休憩を取ってください"
						@comment = "○○さん，お疲れさまでした．#{settings.work_term}分以上連続で作業されたので#{settings.rest_term}分休憩してください．"
            haml :'contents/end'
        end
    end

    get '/task' do
        task = "test"
        blob_id = "2014RC03_S002_P001"
				task,blob_id = select_task(@user,settings.progress_csvfile)
#        blob_id = "2014RC03_S002_T001"
        # redirect to /task/:task/:blob
				if task == nil then
					@title = "作業は全て終了しました"
					@comment = "○○さん，お疲れさまでした．可能な全てのデータへのタグ付けが終わりました"
					haml :'contents/end'
				end
        redirect "/task/#{task}/#{blob_id}",303
    end

    get '/go_on' do
				redirect "/users"
        # 前の休憩に入った時間から10分経ったかどうかをチェックしてログイン
        is_in_rest = false
        if is_in_rest then
						@title = "もう少し休憩してください"
						@comment = "お疲れさまです．残りの休憩時間は○○分○○秒です"
						haml :'contents/end'
        else
            redirect "/task",303
        end
    end


end