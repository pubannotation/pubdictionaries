class WelcomeController < ApplicationController

  def index
  	# Get five most recent showable dictioanries.
    @latest_dics = Dictionary.get_latest_dictionaries(7) 
  end

end
