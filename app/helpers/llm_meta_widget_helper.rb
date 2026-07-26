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
    actions_schema_id:       "ai-actions",
    state_global:            "aiState",
    actions_global:          "aiActions",
    # Remote (MCP) tools live in a separate JSON block. Optional — if the
    # host doesn't render #remote-mcp-tools, the widget just skips the
    # round-trip loop and behaves like local-actions-only.
    remote_tools_schema_id:  "remote-mcp-tools",
    max_rounds:              10
  }.freeze

  def llm_meta_widget(base_url:, model:, **overrides)
    locals = DEFAULTS.merge(base_url: base_url, model: model, **overrides)
    render partial: "llm_meta_widget/chat_panel", locals: locals
  end
end
