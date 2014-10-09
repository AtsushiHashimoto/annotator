require 'sinatra/base'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'app.rb'

class Application < Sinatra::Base
    use KUSKAnnotator
    
    # 404 Error!
    not_found do
        status 404
        haml :error404
    end
end

Application.run!