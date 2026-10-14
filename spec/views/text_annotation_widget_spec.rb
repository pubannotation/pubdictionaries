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

    # Two settings now, one per job: who answers the chat, and whose
    # registered MCP tools to offer. The hub does both here.
    expect(source).to match(/hub = Rails\.configuration\.x\.llm_hub_url/)
    expect(source).to match(/llm_url:\s*hub/)
    expect(source).to match(/tool_hub_url:\s*hub/)
    expect(source).not_to match(/llm_meta_widget\([^)]*llm_url:\s*["']http/)
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
  #
  # The hazard it guarded against is gone: llm_meta_widget 0.6.0 persists the
  # transcript across navigation. Re-declaring the action is therefore a live
  # option, but it is a change of its own — it wants a test that submits for
  # real and checks the conversation comes back, including when the submit
  # lands on an error page, which renders no widget to restore into. Until
  # then this spec keeps the current, deliberate state honest.
  it 'does not offer the assistant an action that navigates away' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read
    declared = JSON.parse(source[%r{<script type="application/json" id="ai-page">(.*?)</script>}m, 1])
                 .dig('_meta', 'io.modelcontextprotocol/static-primitives', 'tools')

    expect(declared.map { _1['name'] }).not_to include('submit_annotation')
    expect(declared.map { _1['name'] }).to include('set_text', 'set_dictionaries')
  end

  # Setting LLM_HUB_URL empty switches the widget off without a code change.
  it 'renders no widget when the hub is unconfigured' do
    source = Rails.root.join('app/views/annotation/text_annotation.html.erb').read

    expect(source).to match(/if Rails\.configuration\.x\.llm_hub_url\.present\?/)
  end
end

# The page declares its primitives in a static-primitives card and implements
# them in handler maps beside it — tools by name, resources by URI, each keyed
# by what its own protocol operation takes.
#
# The card and the maps are edited separately, so the failure this guards is a
# pair that drifts: a resource declared with no reader is silently absent from
# every turn, and a reader with no declaration is never read at all. Neither is
# an error the page can see — the widget warns to the console and carries on.
RSpec.describe 'the page card and its handlers' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  def card
    JSON.parse(source[%r{<script type="application/json" id="ai-page">(.*?)</script>}m, 1])
        .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')
  end

  # Keys of a handler map, read as source: `"page:/x": fn` or `name: fn`.
  def handler_keys(global)
    opening = source[/window\.#{global}\s*=\s*\{/]
    raise "no window.#{global} assignment in the view" if opening.nil?

    from  = source.index(opening) + opening.length - 1
    depth = 0
    source[from..].each_char.with_index do |ch, i|
      depth += 1 if ch == '{'
      depth -= 1 if ch == '}'
      if depth.zero?
        body = source[(from + 1)...(from + i)]
        return body.scan(/^\s*"?([A-Za-z_][\w:\/.-]*)"?\s*:/).flatten
      end
    end
    raise "window.#{global} is never closed"
  end

  it 'declares the resources this page is expected to expose' do
    uris = card.fetch('resources').map { _1['uri'] }

    expect(uris).to include('page:/annotation/text',
                            'page:/annotation/selected_dictionaries',
                            'page:/annotation/available_dictionaries')
    expect(uris.size).to be >= 5
  end

  it 'gives every resource a uri, a name and a non-empty description' do
    card.fetch('resources').each do |r|
      expect(r['uri'].to_s).not_to be_empty
      expect(r['name'].to_s).not_to be_empty, "#{r['uri']} has no name"
      expect(r['description'].to_s.strip).not_to be_empty,
                                                 "#{r['uri']} has no description — the model would see a value with no idea what it means"
    end
  end

  # `page:` is experimental and unregistered, and the README says so. An https:
  # uri here would claim to be fetchable, which it is not.
  it 'addresses page resources with the page scheme' do
    expect(card.fetch('resources').map { _1['uri'] }).to all(start_with('page:/'))
  end

  it 'has a reader for every declared resource, and declares every reader' do
    expect(handler_keys('aiResources').sort).to eq(card.fetch('resources').map { _1['uri'] }.sort)
  end

  # Declared implies implemented, but NOT the reverse: submit_annotation is
  # implemented for the page's own use and deliberately withheld from the
  # assistant (see the spec above). Equality in both directions would read as
  # tidier and would quietly forbid that.
  it 'has an action for every declared tool' do
    expect(handler_keys('aiActions')).to include(*card.fetch('tools').map { _1['name'] })
  end

  it 'keeps submit_annotation implemented but undeclared' do
    expect(handler_keys('aiActions')).to include('submit_annotation')
    expect(card.fetch('tools').map { _1['name'] }).not_to include('submit_annotation')
  end

  # The catalog is the one resource that does not change between turns; the rest
  # are form fields the visitor edits, and a copy read at boot would be stale by
  # the time anyone sends a message.
  it 'marks the form fields volatile and the catalog stable' do
    by_uri = card.fetch('resources').to_h { [ _1['uri'], _1['volatility'] ] }

    expect(by_uri['page:/annotation/text']).to eq('volatile')
    expect(by_uri['page:/annotation/available_dictionaries']).to eq('stable')
  end
end


# The widget names its model explicitly, so the hub's own system-wide default
# never reaches this page. Two constraints on whatever is named here: the hub
# must serve it free to a keyless caller (these visitors have no API key), and
# it must support tool calling, since the page is driven by MCP tools and
# window.aiActions over several rounds.
RSpec.describe 'the embedded chat widget’s model' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  it 'is named explicitly rather than left to the hub default' do
    expect(source).to match(/model:\s*["'][^"']+["']/)
  end

  # Changed from the local qwen on 2026-10-10: that model serves one request
  # at a time, so a demo audience queued behind each other.
  it 'is the hosted gpt-oss, not a local single-slot model' do
    expect(source[/model:\s*["']([^"']+)["']/, 1]).to eq('gpt-oss-120b')
  end
end

# The key the widget invokes through has to be able to serve the model it
# names. The widget's default, "ollama-local", resolves local models only:
# the hub looks a meta_id up within that key's family, so pointing `model:`
# at a hosted model while the key stayed "ollama-local" produced a turn that
# failed inside the stream — HTTP 200, an error event, no answer.
RSpec.describe 'the embedded chat widget’s api key' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  it 'invokes through the free-models key, which serves hosted models too' do
    expect(source[/api_key_uuid:\s*["']([^"']+)["']/, 1]).to eq('free-models')
  end
end
