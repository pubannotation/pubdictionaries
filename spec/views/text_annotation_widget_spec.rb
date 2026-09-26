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

  # A visitor who does not know this page is the one the assistant is for, so
  # the panel must not open empty, and the flow must not need more tool rounds
  # than the widget allows. Both are passed from this view; losing either is
  # silent — the widget simply falls back to a generic line and 3 rounds.
  it 'gives the widget a greeting written for this page' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read
    greeting = source[/greeting:\s*(.+?)\)\s*%>/m, 1].to_s

    expect(greeting).to be_present
    expect(greeting).to match(/annotate/i)
  end

  it 'allows enough tool rounds to choose dictionaries and then annotate' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read
    rounds = source[/max_rounds:\s*(\d+)/, 1]

    # look up, select, annotate, answer — the default of 3 ran out mid-flow.
    expect(rounds.to_i).to be >= 5
  end

  # Submitting navigates, which destroys the conversation, the record of what
  # ran and the scroll position. Asking the assistant not to call it was not
  # enough — the model did it anyway — so it is not declared at all. The
  # implementation stays for the page's own use.
  it 'does not offer the assistant an action that navigates away' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read
    declared = JSON.parse(source[%r{<script type="application/json" id="ai-actions">(.*?)</script>}m, 1])

    expect(declared.map { _1['name'] }).not_to include('submit_annotation')
    expect(declared.map { _1['name'] }).to include('set_text', 'set_dictionaries')
  end

  # Setting LLM_HUB_URL empty switches the widget off without a code change.
  it 'renders no widget when the hub is unconfigured' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read

    expect(source).to match(/if Rails\.configuration\.x\.llm_hub_url\.present\?/)
  end
end
