# Renders the client-orchestrated chat widget on the current page.
#
#   <%= llm_meta_widget(base_url: "https://llmbranch.dbcls.jp",
#                       model:    "qwen3-6-35b-fast") %>
#
# The host page must ALSO provide, on the same page:
#   - <script type="application/json" id="ai-actions">…</script>
#     JSON schema list of local action names + descriptions + input_schema.
#   - window.aiState  — reader functions, called per turn to build the
#                       system prompt with current page state.
#   - window.aiActions — action implementations invoked (fire-and-forget)
#                       when the LLM emits a matching tool_call.
#
# The default DOM ids / global names (ai-actions, aiState, aiActions) are
# overridable via keyword args for pages that already use those names.
module LlmMetaWidgetHelper
  DEFAULTS = {
    api_key_uuid:            "ollama-local",
    orchestrator_path:       "/js/llm_meta_orchestrator.js",
    # Class 3: page-embedded aiActions.
    actions_schema_id:       "ai-actions",
    state_global:            "aiState",
    actions_global:          "aiActions",
    # Class 1: hub-registered remote MCP tools. Optional — absent = skip.
    remote_tools_schema_id:  "remote-mcp-tools",
    # Class 2: host-wide well-known MCP tools. `nil` (default) → widget
    # auto-discovers same-origin `/.well-known/mcp.json` at boot.
    # Empty array → disable (no manifest fetch).
    # Explicit array of URLs → fetch those (multi-host).
    # See project_mcp_tool_classes memory for the three-class taxonomy.
    well_known_urls:         nil,
    # Client-side tool-loop cap. Kept LOW deliberately — weaker tool-use
    # models (Ollama qwen3, some Anthropic Haiku variants) can get stuck
    # re-invoking the same tool round after round instead of synthesizing
    # a final text answer. 3 is enough for "fetch → maybe fetch again →
    # synthesize" patterns and caps the runaway blast radius.
    max_rounds:              3
  }.freeze

  def llm_meta_widget(base_url:, model:, **overrides)
    locals = DEFAULTS.merge(base_url: base_url, model: model, **overrides)
    render partial: "llm_meta_widget/chat_panel", locals: locals
  end
end
