# frozen_string_literal: true

require 'rails_helper'

# The MCP text_annotation tool annotates in-process with
# `TextAnnotator.new(dictionaries, {})`, relying on the annotator to fill every
# option from OPTIONS_DEFAULT itself (its `has_key?` checks in #initialize).
# That is only equivalent to what this page computes for a request carrying
# nothing but text and dictionaries for as long as that defaulting holds.
#
# The MCP specs cannot catch a divergence here: they stub TextAnnotator, so they
# assert that `{}` is passed, never that `{}` is *right*. Change OPTIONS_DEFAULT
# or stop defaulting in #initialize and they would all still pass while the tool
# silently annotated with different settings than the page.
#
# Options come from the real parser rather than a copy of its defaults, so this
# tracks the page instead of restating it. The whole permitted hash is handed
# over unsliced -- #initialize reads only the keys it knows, so the extra ones
# (:text, :dictionaries, :no_text, :tags) cannot change the configuration, and
# not slicing here means the action's slice list is not duplicated.
RSpec.describe AnnotationController, type: :controller do
  describe 'annotator configuration parity with the MCP tool' do
    let(:user) { create(:user) }
    # entries_num 0 on purpose: #initialize then opens no Simstring DB, so this
    # needs neither Elasticsearch nor an on-disk index.
    let!(:dictionary) { create(:dictionary, user: user, name: 'parity_dict', public: true, entries_num: 0) }

    # Every option #initialize turns into matching behaviour, including the two
    # it derives (@soft_match from the threshold, @search_method from
    # superfluous) -- a divergence in those changes results without changing any
    # option this spec reads directly.
    config_ivars = %i[
      @tokens_len_min @tokens_len_max @use_ngram_similarity
      @threshold @semantic_threshold @abbreviation
      @longest @superfluous @verbose
      @soft_match @search_method
    ].freeze

    it 'configures the annotator identically whether the page parses the options or the tool leaves them empty' do
      controller.params = ActionController::Parameters.new(
        'text' => 'some biomedical text', 'dictionaries' => dictionary.name
      )
      page_options = controller.send(:parse_params_for_text_annotation).to_h.symbolize_keys

      # Sanity: the parser really did fill the booleans in, otherwise this
      # comparison would be {} against {} and pass for the wrong reason.
      expect(page_options).to include(:longest, :superfluous, :verbose, :abbreviation, :use_ngram_similarity)

      page = TextAnnotator.new([dictionary], page_options)
      tool = TextAnnotator.new([dictionary], {})
      begin
        config_ivars.each do |ivar|
          expect(tool.instance_variable_get(ivar)).to eq(page.instance_variable_get(ivar)),
            "#{ivar}: tool got #{tool.instance_variable_get(ivar).inspect}, " \
            "page got #{page.instance_variable_get(ivar).inspect} -- " \
            "TextAnnotator no longer defaults this, so the tool must pass it explicitly"
        end
      ensure
        page.dispose
        tool.dispose
      end
    end
  end
end
