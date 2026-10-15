# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# The page card is located by its MEDIA TYPE, not by an id: that is the locator
# SEP-0000 defines, because an id the page chooses cannot be found by a client
# that was not told it. Defined once — five copies of this regex drifted apart
# the moment the locator changed.
PAGE_CARD_RE = %r{<script type="application/mcp-static-primitives\+json"[^>]*>(.*?)</script>}m

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
    declared = JSON.parse(source[PAGE_CARD_RE, 1])
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
    JSON.parse(source[PAGE_CARD_RE, 1])
        .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')
  end

  # Keys of a handler map, read as source: `"page:x": fn` or `name: fn`.
  # The page implements its primitives under the namespace its card declares, so
  # these maps are `window.mcp.tools` and friends rather than three separate
  # globals.
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

    expect(uris).to include('page:text',
                            'page:selected_dictionaries',
                            'page:available_dictionaries')
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
  # Transitional, and load-bearing while it lasts. A widget older than 0.10.0
  # finds the card by this id alone; dropping it made every tool, prompt and
  # resource on this page invisible to a visitor whose deployment still served
  # 0.9.x, with nothing failing anywhere. Delete this example, and the id, once
  # no deployment serves a widget older than 0.10.0.
  it 'keeps the legacy id on the card for older widgets' do
    expect(source).to include('type="application/mcp-static-primitives+json" id="ai-page"')
  end

  # The card declares where the handlers live, which is the only way a consumer
  # other than llm_meta_widget can find them. Without it the page is only half
  # discoverable: its primitives are declared, but nothing says what to call.
  it 'declares the page-global transport its handlers use' do
    remote = JSON.parse(source[PAGE_CARD_RE, 1]).fetch('remotes').first

    expect(remote['type']).to eq('page-global')
    expect(remote['global']).to eq('mcp')
    expect(source).to include('window.mcp = {')
  end

  # No aliases for the legacy globals, deliberately — asserted so that nobody
  # adds them back as a kindness.
  #
  # An alias would let a stale deployment keep working: a checkout that pulled
  # this view without running `bundle install` serves an older widget, finds the
  # legacy names, and behaves correctly, so nobody notices the deployment is
  # stale. Both failures this page has had were that shape. This page is the
  # reference implementation; it should fail loudly instead.
  #
  # The widget itself still reads the legacy names when a card declares no
  # transport, so other adopters keep working.
  it 'keeps no fallback to the legacy globals' do
    # The ASSIGNMENT, not the mention: the comment above the namespace names
    # these three on purpose, so that someone searching for them finds the
    # reason they are absent.
    expect(source).not_to match(/window\.aiActions\s*=/)
    expect(source).not_to match(/window\.aiPrompts\s*=/)
    expect(source).not_to match(/window\.aiResources\s*=/)
  end

  it 'addresses page resources with the page scheme' do
    expect(card.fetch('resources').map { _1['uri'] }).to all(start_with('page:'))
  end

  it 'has a reader for every declared resource, and declares every reader' do
    expect(handler_keys('mcp.resources').sort).to eq(card.fetch('resources').map { _1['uri'] }.sort)
  end

  # Declared implies implemented, but NOT the reverse: submit_annotation is
  # implemented for the page's own use and deliberately withheld from the
  # assistant (see the spec above). Equality in both directions would read as
  # tidier and would quietly forbid that.
  it 'has an action for every declared tool' do
    expect(handler_keys('mcp.tools')).to include(*card.fetch('tools').map { _1['name'] })
  end

  # submit_annotation is implemented but not declared, so the assistant cannot
  # call it and it needs no guard. The guards that were added for the declared
  # version went with it; see the comment on the handler for why.
  it 'keeps submit_annotation implemented but undeclared' do
    expect(handler_keys('mcp.tools')).to include('submit_annotation')
    expect(card.fetch('tools').map { _1['name'] }).not_to include('submit_annotation')
  end

  # The catalog is the one resource that does not change between turns; the rest
  # are form fields the visitor edits, and a copy read at boot would be stale by
  # the time anyone sends a message.
  it 'marks the form fields volatile and the catalog stable' do
    by_uri = card.fetch('resources').to_h { [ _1['uri'], _1['volatility'] ] }

    expect(by_uri['page:text']).to eq('volatile')
    expect(by_uri['page:available_dictionaries']).to eq('stable')
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

# The `annotate` prompt moved out of this app's MCP server and into the page's
# own card on 2026-10-14 (llm_meta_widget 0.9.0). Every step it describes is a
# call against THIS page, and a handler living in the page can read the live
# form rather than work from arguments a caller remembered to pass.
#
# These examples ran against the Ruby implementation until the move. They are
# kept because each one records a decision that cost something to learn, not
# because the text is pretty — so they run the page's real handler under node
# rather than matching strings in the source, which would pass on a handler
# that never composes those strings together.
RSpec.describe 'the page’s annotate prompt' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  # Everything from the first constant to the close of window.mcp.prompts.
  def handler_js
    lines = source.lines
    first = lines.index { |l| l.include?('var SELECT_DICTIONARIES = [') }
    raise 'the page declares no SELECT_DICTIONARIES' if first.nil?

    open_i = lines.index { |l| l.include?('window.mcp.prompts = {') }
    raise 'the page assigns no window.mcp.prompts' if open_i.nil?

    close = (open_i...lines.length).find { |i| lines[i].strip == '};' }
    raise 'window.mcp.prompts is never closed' if close.nil?

    lines[first..close].join
  end

  def prompt_text(arguments)
    raise 'node is required to run the page’s prompt handler' if `which node`.strip.empty?

    Dir.mktmpdir do |dir|
      script = File.join(dir, 'run.js')
      File.write(script, "var window = {};\n#{handler_js}\n" \
                         "process.stdout.write(JSON.stringify(" \
                         "window.mcp.prompts.annotate(#{arguments.to_json})));")
      out = `node #{script} 2>&1`
      raise "the page’s prompt handler failed: #{out}" unless $?.success?

      JSON.parse(out)
    end
  end

  it 'annotates directly when the page already has text and a selection' do
    text = prompt_text('text' => 'I have a stomach ache.', 'dictionaries' => 'UBERON-AE')

    expect(text).to include('UBERON-AE')
    expect(text).to include('I have a stomach ache.')
    expect(text).not_to include('find_ids')
  end

  # The case the first implementation refused to handle: text but no
  # dictionaries. Choosing them is the assistive act, not a precondition.
  it 'tells the assistant to choose and apply dictionaries when none are selected' do
    text = prompt_text('text' => 'I have a stomach ache.')

    # Catalog-first: choosing dictionaries for a passage is a topical judgement
    # that names and descriptions answer. find_ids is the tie-breaker, not the
    # method.
    expect(text).to include('list_dictionaries')
    expect(text).to include('set_dictionaries')
    expect(text).to match(/do not look terms up/i)
    expect(text).to include('I have a stomach ache.')
  end

  # Choosing dictionaries is not the job; annotating is. Left to "then annotate
  # it", the model announced its picks and stopped — and the page's text field
  # stayed empty, so the visitor could not even re-run it by hand.
  it 'spells out filling the form and running the annotation' do
    text = prompt_text('text' => 'I have a stomach ache.')

    expect(text).to include('set_text')
    expect(text).to include('text_annotation')
    expect(text.index('set_text')).to be < text.index('text_annotation')
  end

  # The assistant runs the annotation itself in step 2, so submitting the form
  # repeats work the visitor can trigger whenever they want the page's own view.
  # Asserting the reason, not the old scare wording about losing the
  # conversation, so a stale claim cannot be held in place by this spec.
  it 'tells the assistant not to submit the form as well' do
    text = prompt_text('text' => 'I have a stomach ache.')

    expect(text).to match(/do not submit/i)
    expect(text).to match(/already run the annotation/i)
  end

  it 'no longer claims submitting would discard the conversation' do
    text = prompt_text('text' => 'I have a stomach ache.')

    expect(text).not_to match(/reloads the page/i)
    expect(text).not_to match(/discards (our|the) conversation/i)
  end

  it 'asks for the text when the page has none' do
    text = prompt_text({})

    expect(text).to match(/ask me for the text/i)
    expect(text).to include('list_dictionaries')
  end

  it 'names an existing selection instead of choosing again' do
    text = prompt_text('dictionaries' => 'UBERON-AE')

    expect(text).to include('UBERON-AE')
    expect(text).not_to include('list_dictionaries')
  end

  # The button must work from an empty page; that is its whole point.
  it 'is usable with no arguments at all' do
    expect { prompt_text({}) }.not_to raise_error
  end

  it 'declares the prompt it implements, with both arguments optional' do
    card = JSON.parse(source[PAGE_CARD_RE, 1])
               .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')
    prompt = card.fetch('prompts').first

    expect(prompt['name']).to eq('annotate')
    expect(prompt['arguments'].map { _1['name'] }).to eq([ 'text', 'dictionaries' ])
    # Required arguments sourced from page state would make the template usable
    # only by someone who already knows the UI — which is who does not need it.
    expect(prompt['arguments'].map { _1['required'] }).to eq([ false, false ])
  end

  it 'has a handler for every declared prompt' do
    card = JSON.parse(source[PAGE_CARD_RE, 1])
               .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')

    card.fetch('prompts').each do |p|
      expect(handler_js).to include("#{p['name']}: function")
    end
  end
end

# The widget fills a prompt's declared arguments from the page's resources,
# matching the argument NAME against the name inside the resource URI. That
# coupling is invisible in both files: rename `page:text` and the annotate
# button quietly stops knowing what is in the textarea, with nothing failing.
#
# The alias is the widget's, not ours (llm_meta_widget's PROMPT_ARG_ALIASES).
# It is restated here because this page depends on it; if the widget drops it,
# this spec is where that shows up.
RSpec.describe 'the page’s prompt arguments and its resources' do
  WIDGET_ARG_ALIASES = { 'dictionaries' => 'selected_dictionaries' }.freeze

  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  def card
    JSON.parse(source[PAGE_CARD_RE, 1])
        .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')
  end

  it 'can fill every declared prompt argument from a declared resource' do
    names = card.fetch('resources').map { _1['uri'].delete_prefix('page:') }

    card.fetch('prompts').each do |prompt|
      prompt.fetch('arguments').each do |arg|
        wanted = WIDGET_ARG_ALIASES.fetch(arg['name'], arg['name'])
        expect(names).to include(wanted),
                         "prompt argument #{arg['name']} looks for resource page:#{wanted}, " \
                         "which this page does not declare — the widget would leave it empty"
      end
    end
  end
end

# A syntax error anywhere in this page's inline JavaScript takes down every
# handler on it at once: window.aiActions, aiPrompts and aiResources are all
# assigned in the same blocks, so one stray brace leaves the card declaring
# tools, prompts and resources that nothing implements. The visitor sees
# "the page declares prompt ... but no handler answers to that name", and
# nothing in Ruby notices, because ERB stays valid.
#
# That happened on 2026-10-15 while adding the submit_annotation guard.
RSpec.describe 'the page’s inline JavaScript' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  it 'parses, every block of it' do
    skip 'node is not available' if `which node`.strip.empty?

    blocks = source.scan(%r{<script type="text/javascript">\s*(.*?)\s*</script>}m).flatten
    expect(blocks.size).to be >= 3, 'expected the page to still carry its inline scripts'

    Dir.mktmpdir do |dir|
      blocks.each_with_index do |block, i|
        # ERB holes become a literal, so a template value cannot be mistaken
        # for a syntax error.
        file = File.join(dir, "block_#{i}.js")
        File.write(file, block.gsub(/<%=?-?.*?-?%>/m, '0'))
        out = `node --check #{file} 2>&1`
        expect($?.success?).to be(true), "block #{i} does not parse:\n#{out}"
      end
    end
  end
end

# Every other example here reads the view as text. That catches a renamed key or
# a missing declaration, but it cannot see what the browser sees: whether the
# script, once run, actually leaves the declared primitives on the declared
# global. Two failures this page has had were of that kind — a stray brace, and
# handlers assigned before their namespace existed — and both passed a text
# reading of the file.
#
# So this one runs the page's own script under node, with the page's helpers
# stubbed, and compares what exists with what the card promises.
RSpec.describe 'the page’s primitives, once the script has run' do
  let(:source) { Rails.root.join('app/views/annotation/text_annotation.html.erb').read }

  def card
    JSON.parse(source[PAGE_CARD_RE, 1])
        .fetch('_meta').fetch('io.modelcontextprotocol/static-primitives')
  end

  # The namespace is built by the last inline script. ERB holes become a literal
  # so a template value cannot look like a syntax error.
  def run_namespace
    skip 'node is not available' if `which node`.strip.empty?

    block = source.scan(%r{<script type="text/javascript">\s*(.*?)\s*</script>}m).flatten.last
                  .gsub(/<%=?-?.*?-?%>/m, '0')
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'namespace.js')
      File.write(file, <<~JS)
        var window = {},
            document = { getElementById: function () { return null },
                         querySelectorAll: function () { return [] } };
        function $() { return { val: function () { return "" }, length: 0,
                                submit: function () {}, each: function () {} } }
        $.each = function () {};
        var OPTION_ID_BY_NAME = {};
        function readSelectedDictionaries() { return [] }
        function readAvailableDictionaries() { return [] }
        function requireDictionaryExists() {}
        #{block}
        process.stdout.write(JSON.stringify({
          tools:     Object.keys((window.mcp || {}).tools     || {}),
          prompts:   Object.keys((window.mcp || {}).prompts   || {}),
          resources: Object.keys((window.mcp || {}).resources || {}),
          legacyDefined: [ window.aiActions, window.aiPrompts, window.aiResources ]
                           .some(function (v) { return v !== undefined })
        }));
      JS
      out = `node #{file} 2>&1`
      raise "the page's script did not run: #{out[0, 400]}" unless $?.success?

      JSON.parse(out)
    end
  end

  it 'leaves a handler on the namespace for every declared primitive' do
    got = run_namespace

    expect(got['tools']).to include(*card.fetch('tools').map { _1['name'] })
    expect(got['prompts']).to include(*card.fetch('prompts').map { _1['name'] })
    expect(got['resources']).to include(*card.fetch('resources').map { _1['uri'] })
  end

  it 'defines no legacy global, so a stale deployment fails loudly' do
    expect(run_namespace['legacyDefined']).to be(false)
  end
end
