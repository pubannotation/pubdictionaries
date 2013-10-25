require 'test_helper'

class WebServicesControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get exact_string_match" do
    get :exact_string_match
    assert_response :success
  end

  test "should get approximate_string_match" do
    get :approximate_string_match
    assert_response :success
  end

end
