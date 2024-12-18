require 'test_helper'

class Api::V1::EntriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    user = users(:one)
    user.create_access_token!
    @access_token = user.access_token.token

    @dictionary = dictionaries(:one)
    @entry = entries(:one)

    @empty_dictionary = dictionaries(:empty_dictionary)
    @file = fixture_file_upload('sample_tsv_entries.tsv', 'text/tab-separated-values')

    @other_users_dictionary = dictionaries(:two)
  end

  # Test #create
  test 'should create entry' do
    assert_difference('Entry.count', 1) do
      post '/api/v1/entries', params: { dictionary_id: @dictionary.name, label: 'abc', identifier: '123' },
                              headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                              as: :json
    end

    assert_response :created
    assert_equal 'abc', Entry.last.label
    assert_equal '123', Entry.last.identifier
  end

  test 'should return error when label is blank' do
    post '/api/v1/entries', params: { dictionary_id: @dictionary.name, identifier: '123' },
                            headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                            as: :json

    assert_response :bad_request
    assert_includes @response.body, "A label should be supplied."
  end

  test 'should return error when identifier is blank' do
    post '/api/v1/entries', params: { dictionary_id: @dictionary.name, label: 'abc' },
                            headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                            as: :json

    assert_response :bad_request
    assert_includes @response.body, "An identifier should be supplied."
  end

  test "should return error when entry already exists" do
    post '/api/v1/entries', params: { dictionary_id: @dictionary.name, label: @entry.label, identifier: @entry.identifier },
                            headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                            as: :json

    assert_response :conflict
    assert_includes @response.body, "The entry ('#{@entry.label}', '#{@entry.identifier}') already exists in the dictionary."
  end

  # Test #destroy_entries
  test 'should delete entry' do
    assert_difference('Entry.count', -1) do
      delete '/api/v1/entries', params: { dictionary_id: @dictionary.name, entry_id: 1 },
                                headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                                as: :json
    end

    assert_response :ok
  end

  test 'should return error when no entry_id is present' do
    delete '/api/v1/entries', params: { dictionary_id: @dictionary.name },
                              headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                              as: :json

    assert_response :bad_request
    assert_includes @response.body, "No entry to be deleted is selected"
  end

  test 'should return error when entry_id does not exist' do
    delete '/api/v1/entries', params: { dictionary_id: @dictionary.name, entry_id: 9999 },
                              headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                              as: :json

    assert_response :not_found
    assert_includes @response.body, "Could not find the entries, 9999"
  end

  # Test #undo
  test 'should undo entry' do
    assert_equal EntryMode::WHITE, @entry.mode

    assert_difference('Entry.count', -1) do
      put "/api/v1/entries/#{@entry.id}/undo", params: { dictionary_id: @dictionary.name },
                                               headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                                               as: :json
    end

    assert_response :ok
  end

  test 'should return error when entry does not exist' do
    put "/api/v1/entries/9999/undo", params: { dictionary_id: @dictionary.name },
                                     headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                                     as: :json

    assert_response :bad_request
    assert_includes @response.body, "Cannot find the entry."
  end

  # Test #upload_tsv
  test 'should create bulk upload job' do
    post '/api/v1/entries/tsv', params: { dictionary_id: @empty_dictionary.name, file: @file },
                                headers: { 'Content-Type' => 'multipart/form-data', 'Authorization' => "Bearer #{@access_token}" }

    assert_response :accepted
  end

  test 'should create bulk upload job with force option' do
    @empty_dictionary.jobs.create!(name: 'test-job', begun_at: Time.now - 2, ended_at: Time.now - 1)

    post '/api/v1/entries/tsv?force=true', params: { dictionary_id: @empty_dictionary.name, file: @file },
                                           headers: { 'Content-Type' => 'multipart/form-data', 'Authorization' => "Bearer #{@access_token}" }

    assert_response :accepted
  end

  test 'should return error when job exist' do
    @empty_dictionary.jobs.create!(name: 'test-job', begun_at: Time.now - 2, ended_at: Time.now - 1)

    post '/api/v1/entries/tsv', params: { dictionary_id: @empty_dictionary.name, file: @file },
                                headers: { 'Content-Type' => 'multipart/form-data', 'Authorization' => "Bearer #{@access_token}" }

    assert_response :conflict
    assert_includes @response.body, "The last task is not yet dismissed. Please dismiss it and try again."
  end

  test 'should return error when dictionary is not uploadable' do
    post '/api/v1/entries/tsv', params: { dictionary_id: @dictionary.name, file: @file },
                                headers: { 'Content-Type' => 'multipart/form-data', 'Authorization' => "Bearer #{@access_token}" }

    assert_response :bad_request
    assert_includes @response.body, "Uploading a dictionary is only possible if there are no dictionary entries."
  end

  # Test Authentication
  test 'should not be able to change resources without access token' do
    post "/api/v1/entries", params: { dictionary_id: @dictionary.name, label: 'abc', identifier: '123' },
                            headers: { 'Content-Type' => 'application/json' },
                            as: :json
    assert_response :unauthorized

    delete '/api/v1/entries', params: { dictionary_id: @dictionary.name, entry_id: 1 },
                              headers: { 'Content-Type' => 'application/json' },
                              as: :json
    assert_response :unauthorized

    put "/api/v1/entries/#{@entry.id}/undo", params: { dictionary_id: @dictionary.name },
                                             headers: { 'Content-Type' => 'application/json' },
                                             as: :json
    assert_response :unauthorized

    post '/api/v1/entries/tsv', params: { dictionary_id: @empty_dictionary.name, file: @file },
                                headers: { 'Content-Type' => 'multipart/form-data' }
    assert_response :unauthorized
  end

  test 'should not be able to change resources with invalid access token' do
    post "/api/v1/entries", params: { dictionary_id: @dictionary.name, label: 'abc', identifier: '123' },
                            headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer invalid-token" },
                            as: :json

    assert_response :unauthorized
  end

  test 'should not be able to change other users resources' do
    post "/api/v1/entries", params: { dictionary_id: @other_users_dictionary.name, label: 'abc', identifier: '123' },
                            headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@access_token}" },
                            as: :json

    assert_response :not_found
  end
end
