require 'sinatra/extension'

module Helpers
	module Utils
		extend Sinatra::Extension
		
		def self.registered(app)
			app.helpers Utils
		end
	end
end