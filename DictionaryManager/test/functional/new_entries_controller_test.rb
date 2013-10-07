require 'test_helper'

class NewEntriesControllerTest < ActionController::TestCase
  setup do
    @new_entry = new_entries(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:new_entries)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create new_entry" do
    assert_difference('NewEntry.count') do
      post :create, new_entry: { label: @new_entry.label, title: @new_entry.title, uri: @new_entry.uri, user_dictionary_id: @new_entry.user_dictionary_id }
    end

    assert_redirected_to new_entry_path(assigns(:new_entry))
  end

  test "should show new_entry" do
    get :show, id: @new_entry
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @new_entry
    assert_response :success
  end

  test "should update new_entry" do
    put :update, id: @new_entry, new_entry: { label: @new_entry.label, title: @new_entry.title, uri: @new_entry.uri, user_dictionary_id: @new_entry.user_dictionary_id }
    assert_redirected_to new_entry_path(assigns(:new_entry))
  end

  test "should destroy new_entry" do
    assert_difference('NewEntry.count', -1) do
      delete :destroy, id: @new_entry
    end

    assert_redirected_to new_entries_path
  end
end
