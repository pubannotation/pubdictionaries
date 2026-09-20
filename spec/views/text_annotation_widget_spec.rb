# frozen_string_literal: true

require 'rails_helper'

# The chat widget runs in the visitor's browser and calls the llm_meta hub
# directly, so its base URL has to differ per deployment: the dev site talks
# to the dev hub, production to the production hub. It was hardcoded to the
# dev hub, which would have sent production visitors' chat traffic to a
# development server.
RSpec.describe 'the embedded chat widget’s hub URL' do
  it 'is configured per environment, not hardcoded in the view' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read

    expect(source).to include('base_url: Rails.configuration.x.llm_hub_url')
    expect(source).not_to match(/llm_meta_widget\([^)]*base_url:\s*["']http/)
  end

  it 'has a value in this environment' do
    expect(Rails.configuration.x.llm_hub_url).to be_present
  end

  it 'can be set per deployment via LLM_HUB_URL' do
    %w[development production test].each do |env|
      source = Rails.root.join("config/environments/#{env}.rb").read
      expect(source).to match(/ENV(\.fetch\(|\[)"LLM_HUB_URL"/),
                        "#{env}.rb should read LLM_HUB_URL"
    end
  end

  it 'points production at a different hub from development' do
    defaults = %w[development production].to_h do |env|
      source = Rails.root.join("config/environments/#{env}.rb").read
      [ env, source[/LLM_HUB_URL",\s*"([^"]+)"/, 1] ]
    end

    expect(defaults['production']).to be_present
    expect(defaults['production']).to start_with('https://')
    # The failure this guards: production serving a widget that posts
    # visitors' text to the development hub.
    expect(defaults['production']).not_to eq(defaults['development'])
  end

  # Setting LLM_HUB_URL empty switches the widget off without a code change.
  it 'renders no widget when the hub is unconfigured' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read

    expect(source).to match(/if Rails\.configuration\.x\.llm_hub_url\.present\?/)
  end
end
