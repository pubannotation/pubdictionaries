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

# The widget's state-reader contract changed in llm_meta_widget 0.8.0: each entry
# must be { description: "...", read: function }. A reader left on the old bare
# function form is not an error the page can see — the widget logs to the console
# and skips that key, so the value silently stops reaching the model and the
# assistant quietly gets worse at this page. This is the only deployment of that
# contract, so the check belongs here.
#
# Written generically on purpose: a seventh reader added later is covered without
# anyone remembering to extend this test.
RSpec.describe 'the page’s aiState readers' do
  # Brace-matched rather than regexed: the `options` reader nests a function, so
  # a lazy /\{(.*?)\}/ would stop at the wrong closing brace.
  def ai_state_body(source)
    # The ASSIGNMENT, not the first mention: the view talks about window.aiState
    # in comments above it, and anchoring on those lands in the ai-actions JSON
    # block instead — which parses happily and silently checks the wrong thing.
    match = source.match(/window\.aiState\s*=\s*\{/)
    raise 'no window.aiState assignment in the view' if match.nil?

    open_i = match.end(0) - 1
    depth  = 0
    i      = open_i
    while i < source.length
      depth += 1 if source[i] == '{'
      depth -= 1 if source[i] == '}'
      return source[(open_i + 1)...i] if depth.zero?

      i += 1
    end
    raise 'window.aiState is never closed'
  end

  # Top-level `key:` pairs, each with the raw text of its value.
  def entries(body)
    out   = {}
    depth = 0
    key   = nil
    from  = 0
    body.each_char.with_index do |ch, i|
      case ch
      when '{', '[' then depth += 1
      when '}', ']' then depth -= 1
      when ','
        if depth.zero? && key
          out[key] = body[from...i]
          key = nil
        end
      end
      next unless depth.zero? && ch == ':' && key.nil?

      name = body[0...i][/([A-Za-z_][A-Za-z0-9_]*)\s*\z/, 1]
      next if name.nil?

      key  = name
      from = i + 1
    end
    out[key] = body[from..] if key
    out
  end

  let(:source)  { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }
  let(:readers) { entries(ai_state_body(source)) }

  it 'declares the readers this page is expected to expose' do
    expect(readers.keys).to include('text', 'selected_dictionaries', 'available_dictionaries')
    expect(readers.size).to be >= 5
  end

  it 'gives every reader a non-empty description and a read function' do
    readers.each do |name, value|
      described = value[/description:\s*(["'])(.*?)\1/m, 2]
      expect(described).not_to be_nil,
                              "#{name} has no description — the model would see its value with no idea what it means"
      expect(described.to_s.strip).not_to be_empty, "#{name}'s description is blank"
      expect(value).to match(/read:\s*(function|[A-Za-z_])/),
                       "#{name} has no read function"
    end
  end

  it 'leaves no reader on the removed bare-function form' do
    readers.each do |name, value|
      expect(value.strip).to start_with('{'),
                             "#{name} is still a bare function; llm_meta_widget 0.8.0 skips it instead of calling it"
    end
  end
end

