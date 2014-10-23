require 'sinatra/base'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'app.rb'

class Application < Sinatra::Base
    use KUSKAnnotator

		MyCustomError = 10000

		set :port, 4568
		#set :raise_errors, false #development環境でエラー処理のテストをする．


		# エラー処理(config.ru内に書く必要がある)
		not_found do
			@message = "The requested file is not found."
			haml :error, :layout=>:layout_error
		end

		error do
			@message = env['sinatra.error'].name
			haml :error, :layout=>:layout_error			
		end

		error MyCustomError do
			@message = env['sinatra.error'].message
			haml :error, :layout=>:layout_error
		end

end

Application.run!