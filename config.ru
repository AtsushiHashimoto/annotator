require 'sinatra/base'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'app.rb'

class Application < Sinatra::Base
    use KUSKAnnotator

		set :MyCustomError, 10000

		set :port, 4569
		#set :raise_errors, false #development環境でエラー処理のテストをする．


		# エラー処理(config.ru内に書く必要がある)
		not_found do
			@message = "The requested file is not found."
			haml :error, :layout=>:layout_error
		end

		error do
			@message = env['sinatra.error'].name
			@message += "<br>" + env['sinatra.error'].message
			haml :error, :layout=>:layout_error			
		end


end

Application.run!
