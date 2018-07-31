require "rails_helper"

RSpec.describe AssociationsController, :type => :routing do
  describe "routing" do

    it "routes to #index" do
      expect(:get => "/associations").to route_to("associations#index")
    end

    it "routes to #new" do
      expect(:get => "/associations/new").to route_to("associations#new")
    end

    it "routes to #show" do
      expect(:get => "/associations/1").to route_to("associations#show", :id => "1")
    end

    it "routes to #edit" do
      expect(:get => "/associations/1/edit").to route_to("associations#edit", :id => "1")
    end

    it "routes to #create" do
      expect(:post => "/associations").to route_to("associations#create")
    end

    it "routes to #update via PUT" do
      expect(:put => "/associations/1").to route_to("associations#update", :id => "1")
    end

    it "routes to #destroy" do
      expect(:delete => "/associations/1").to route_to("associations#destroy", :id => "1")
    end

  end
end
