require 'rails_helper'

RSpec.describe "Associations", :type => :request do
  describe "GET /associations" do
    it "works! (now write some real specs)" do
      get associations_path
      expect(response).to have_http_status(200)
    end
  end
end
