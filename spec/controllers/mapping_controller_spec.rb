require 'spec_helper'

describe MappingController do

  describe "GET 'term_to_id'" do
    it "returns http success" do
      get 'term_to_id'
      response.should be_success
    end
  end

  describe "GET 'id_to_label'" do
    it "returns http success" do
      get 'id_to_label'
      response.should be_success
    end
  end

  describe "GET 'text_annotation'" do
    it "returns http success" do
      get 'text_annotation'
      response.should be_success
    end
  end

end
