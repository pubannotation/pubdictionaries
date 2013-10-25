require 'test_helper'

class RemovedEntriesControllerTest < ActionController::TestCase
  setup do
    @removed_entry = removed_entries(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:removed_entries)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create removed_entry" do
    assert_difference('RemovedEntry.count') do
      post :create, removed_entry: { entry_id: @removed_entry.entry_id, user_dictionary_id: @removed_entry.user_dictionary_id }
    end

    assert_redirected_to removed_entry_path(assigns(:removed_entry))
  end

  test "should show removed_entry" do
    get :show, id: @removed_entry
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @removed_entry
    assert_response :success
  end

  test "should update removed_entry" do
    put :update, id: @removed_entry, removed_entry: { entry_id: @removed_entry.entry_id, user_dictionary_id: @removed_entry.user_dictionary_id }
    assert_redirected_to removed_entry_path(assigns(:removed_entry))
  end

  test "should destroy removed_entry" do
    assert_difference('RemovedEntry.count', -1) do
      delete :destroy, id: @removed_entry
    end

    assert_redirected_to removed_entries_path
  end
end
