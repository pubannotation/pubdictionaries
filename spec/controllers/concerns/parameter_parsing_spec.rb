# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ParameterParsing, type: :controller do
  controller(ApplicationController) do
    include ParameterParsing
  end

  describe '#to_boolean' do
    context 'with default parameter' do
      it 'returns default value when input is nil' do
        result = controller.send(:to_boolean, nil, default: true)
        expect(result).to eq(true)
      end

      it 'returns false as default when specified' do
        result = controller.send(:to_boolean, nil, default: false)
        expect(result).to eq(false)
      end

      it 'returns nil when no default is specified and input is nil' do
        result = controller.send(:to_boolean, nil)
        expect(result).to be_nil
      end
    end

    context 'with explicit values (override defaults)' do
      it 'returns true for "true" string regardless of default' do
        result = controller.send(:to_boolean, 'true', default: false)
        expect(result).to eq(true)
      end

      it 'returns false for "false" string regardless of default' do
        result = controller.send(:to_boolean, 'false', default: true)
        expect(result).to eq(false)
      end

      it 'returns true for "1" string' do
        result = controller.send(:to_boolean, '1', default: false)
        expect(result).to eq(true)
      end

      it 'returns false for "0" string' do
        result = controller.send(:to_boolean, '0', default: true)
        expect(result).to eq(false)
      end

      it 'returns false for any other string' do
        result = controller.send(:to_boolean, 'yes', default: true)
        expect(result).to eq(false)
      end
    end

    context 'backward compatibility' do
      it 'works without default parameter (original behavior)' do
        expect(controller.send(:to_boolean, 'true')).to eq(true)
        expect(controller.send(:to_boolean, 'false')).to eq(false)
        expect(controller.send(:to_boolean, '1')).to eq(true)
        expect(controller.send(:to_boolean, nil)).to be_nil
      end
    end
  end

  describe '#to_integer' do
    it 'converts string to integer' do
      result = controller.send(:to_integer, '42')
      expect(result).to eq(42)
    end

    it 'returns nil for blank value' do
      result = controller.send(:to_integer, nil)
      expect(result).to be_nil
    end

    it 'returns nil for invalid integer string' do
      result = controller.send(:to_integer, 'not a number')
      expect(result).to be_nil
    end
  end

  describe '#to_float' do
    it 'converts string to float' do
      result = controller.send(:to_float, '3.14')
      expect(result).to eq(3.14)
    end

    it 'returns nil for blank value' do
      result = controller.send(:to_float, nil)
      expect(result).to be_nil
    end

    it 'returns nil for invalid float string' do
      result = controller.send(:to_float, 'not a number')
      expect(result).to be_nil
    end
  end

  describe '#to_array' do
    it 'splits comma-separated string' do
      result = controller.send(:to_array, 'a,b,c')
      expect(result).to eq(['a', 'b', 'c'])
    end

    it 'splits pipe-separated string' do
      result = controller.send(:to_array, 'a|b|c')
      expect(result).to eq(['a', 'b', 'c'])
    end

    it 'splits newline-separated string' do
      result = controller.send(:to_array, "a\nb\nc")
      expect(result).to eq(['a', 'b', 'c'])
    end

    it 'trims whitespace' do
      result = controller.send(:to_array, ' a , b , c ')
      expect(result).to eq(['a', 'b', 'c'])
    end

    it 'returns empty array for nil' do
      result = controller.send(:to_array, nil)
      expect(result).to eq([])
    end
  end

  describe '#parse_dictionaries!' do
    it 'uses dictionaries parameter when present' do
      params = ActionController::Parameters.new(dictionaries: 'dict1,dict2')
      controller.send(:parse_dictionaries!, params)
      expect(params[:dictionaries]).to eq(['dict1', 'dict2'])
    end

    it 'falls back to dictionary parameter when dictionaries is absent' do
      params = ActionController::Parameters.new(dictionary: 'dict1,dict2')
      controller.send(:parse_dictionaries!, params)
      expect(params[:dictionaries]).to eq(['dict1', 'dict2'])
      expect(params[:dictionary]).to be_nil
    end

    it 'removes dictionary parameter after parsing' do
      params = ActionController::Parameters.new(dictionary: 'dict1')
      controller.send(:parse_dictionaries!, params)
      expect(params.has_key?(:dictionary)).to be false
    end
  end
end
