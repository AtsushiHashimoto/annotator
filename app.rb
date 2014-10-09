require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'active_support/all'
require 'haml'

$LOAD_PATH.push(File.dirname(__FILE__))


class KUSKAnnotator < Sinatra::Base
    configure do
        #set hyper parameters
        set :MyConffile, "config.yml"
        
        #Load configure file
        register Sinatra::ConfigFile
        config_file "#{settings.root}/#{settings.MyConffile}"

    end

    configure :development do
        register Sinatra::Reloader
    end

		get '/scss/:basename' do |basename|
			scss :"scss/#{basename}"
		end

    get '/' do
			  # Sinatraでのログインの方法を再度調べる(basic認証で十分)
				is_logged_in = true
        
        if is_logged_in then
            redirect "/login",303
        else
						redirect "/goon",303
				end        
    end

    get '/login' do
				@title = "ログイン画面"
        haml :'contents/login'
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
				task,blob_id = select_task(user,settings.progress_csvfile)
#        blob_id = "2014RC03_S002_T001"
        # redirect to /task/:task/:blob
				if task == nil then
					@title = "作業は全て終了しました"
					@comment = "○○さん，お疲れさまでした．可能な全てのデータへのタグ付けが終わりました"
					haml :'contents/end'
				end
        redirect "/task/#{task}/#{blob_id}",303
    end

    get '/goon' do
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