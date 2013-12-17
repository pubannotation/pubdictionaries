class UserDictionariesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!
 
end
