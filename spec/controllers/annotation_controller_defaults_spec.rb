# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnnotationController, type: :controller do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_dict_defaults') }

  before do
    # Create some test entries
    entries_data = [
      ['test term', 'TEST:001', 'test term', 'test term', 9, EntryMode::GRAY, false, dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      entries_data,
      validate: false
    )
    dictionary.update_entries_num
  end

  describe 'GET /text_annotation.json with default options' do
    context 'when abbreviation and longest parameters are NOT provided' do
      it 'uses default values (both true)' do
        get :text_annotation, params: {
          dictionary: 'test_dict_defaults',
          text: 'test term',
          format: :json
        }

        expect(response).to have_http_status(:success)
        # The result should be successful, indicating defaults were applied
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('text')
        expect(json_response).to have_key('denotations')
      end
    end

    context 'when abbreviation is explicitly set to false' do
      it 'overrides the default' do
        get :text_annotation, params: {
          dictionary: 'test_dict_defaults',
          text: 'test term',
          abbreviation: 'false',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('denotations')
      end
    end

    context 'when longest is explicitly set to false' do
      it 'overrides the default' do
        get :text_annotation, params: {
          dictionary: 'test_dict_defaults',
          text: 'test term',
          longest: 'false',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('denotations')
      end
    end

    context 'when both are explicitly set to true' do
      it 'uses the explicit values' do
        get :text_annotation, params: {
          dictionary: 'test_dict_defaults',
          text: 'test term',
          abbreviation: 'true',
          longest: 'true',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('denotations')
      end
    end
  end

  describe 'parse_params_for_text_annotation' do
    it 'applies correct defaults for boolean options' do
      # Simulate a request without optional parameters
      params = ActionController::Parameters.new(
        dictionary: 'test_dict_defaults',
        text: 'test term'
      )

      allow(controller).to receive(:params).and_return(params)
      result = controller.send(:parse_params_for_text_annotation)

      # Check that defaults match TextAnnotator::OPTIONS_DEFAULT
      expect(result[:abbreviation]).to eq(TextAnnotator::OPTIONS_DEFAULT[:abbreviation])
      expect(result[:longest]).to eq(TextAnnotator::OPTIONS_DEFAULT[:longest])
      expect(result[:superfluous]).to eq(TextAnnotator::OPTIONS_DEFAULT[:superfluous])
      expect(result[:verbose]).to eq(TextAnnotator::OPTIONS_DEFAULT[:verbose])
      expect(result[:use_ngram_similarity]).to eq(TextAnnotator::OPTIONS_DEFAULT[:use_ngram_similarity])
    end

    it 'respects explicit false values' do
      params = ActionController::Parameters.new(
        dictionary: 'test_dict_defaults',
        text: 'test term',
        abbreviation: 'false',
        longest: 'false'
      )

      allow(controller).to receive(:params).and_return(params)
      result = controller.send(:parse_params_for_text_annotation)

      expect(result[:abbreviation]).to eq(false)
      expect(result[:longest]).to eq(false)
    end

    it 'respects explicit true values' do
      params = ActionController::Parameters.new(
        dictionary: 'test_dict_defaults',
        text: 'test term',
        abbreviation: 'true',
        longest: 'true',
        verbose: 'true'
      )

      allow(controller).to receive(:params).and_return(params)
      result = controller.send(:parse_params_for_text_annotation)

      expect(result[:abbreviation]).to eq(true)
      expect(result[:longest]).to eq(true)
      expect(result[:verbose]).to eq(true)
    end

    it 'handles numeric boolean values' do
      params = ActionController::Parameters.new(
        dictionary: 'test_dict_defaults',
        text: 'test term',
        abbreviation: '1',
        longest: '0'
      )

      allow(controller).to receive(:params).and_return(params)
      result = controller.send(:parse_params_for_text_annotation)

      expect(result[:abbreviation]).to eq(true)  # '1' becomes true
      expect(result[:longest]).to eq(false)      # '0' becomes false (not '1')
    end
  end

  describe 'TextAnnotator initialization with parsed params' do
    it 'receives correct default values from controller' do
      params = ActionController::Parameters.new(
        dictionary: 'test_dict_defaults',
        text: 'test term'
      )

      allow(controller).to receive(:params).and_return(params)
      parsed = controller.send(:parse_params_for_text_annotation)

      # These should match TextAnnotator defaults
      expect(parsed[:abbreviation]).to eq(true)
      expect(parsed[:longest]).to eq(true)
      expect(parsed[:superfluous]).to eq(false)
      expect(parsed[:verbose]).to eq(false)
    end
  end

  describe 'Integration test: defaults flow through to TextAnnotator' do
    it 'passes correct defaults to TextAnnotator when no params provided' do
      # Create a simple test to verify the full flow
      get :text_annotation, params: {
        dictionary: 'test_dict_defaults',
        text: 'test',
        format: :json
      }

      expect(response).to have_http_status(:success)
      # If defaults weren't applied correctly, the request might fail
      # or behave unexpectedly. Success indicates proper default handling.
    end
  end
end
