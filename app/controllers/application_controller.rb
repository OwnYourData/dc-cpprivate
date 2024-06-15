class ApplicationController < ActionController::Base
    protect_from_forgery with: :null_session
    
    def version
        render json: {"service": "signature service", "version": SIGNING_VERSION.to_s, "semcon": VERSION.to_s, "oydid-gem": Gem.loaded_specs["oydid"].version.to_s}.to_json,
               status: 200
    end

    def missing
        render json: {"error": "invalid path"},
               status: 404
    end	
end