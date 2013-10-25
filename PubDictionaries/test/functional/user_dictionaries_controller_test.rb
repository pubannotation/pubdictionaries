require 'test_helper'

class UserDictionariesControllerTest < ActionController::TestCase
  setup do
    @user_dictionary = user_dictionaries(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:user_dictionaries)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create user_dictionary" do
    assert_difference('UserDictionary.count') do
      post :create, user_dictionary: { dictionary_id: @user_dictionary.dictionary_id, user_id: @user_dictionary.user_id }
    end

    assert_redirected_to user_dictionary_path(assigns(:user_dictionary))
  end

  test "should show user_dictionary" do
    get :show, id: @user_dictionary
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @user_dictionary
    assert_response :success
  end

  test "should update user_dictionary" do
    put :update, id: @user_dictionary, user_dictionary: { dictionary_id: @user_dictionary.dictionary_id, user_id: @user_dictionary.user_id }
    assert_redirected_to user_dictionary_path(assigns(:user_dictionary))
  end

  test "should destroy user_dictionary" do
    assert_difference('UserDictionary.count', -1) do
      delete :destroy, id: @user_dictionary
    end

    assert_redirected_to user_dictionaries_path
  end
end
