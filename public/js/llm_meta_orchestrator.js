// Browser client for the meta-server's client-orchestrated flow.
//
// One request = one LLM turn. Streams the reply chunks via callbacks; resolves
// with the final content + any tool_calls the LLM emitted (unexecuted). The
// dispatcher that turns tool_calls into local action invocations (or remote
// MCP round-trips) is layered on top; see runChatLoop below.
//
// SHIP TARGETS: the llm_meta_client engine's chat host, and pages that embed
// the widget directly (e.g. PubDictionaries' text_annotation view). Kept as a
// single self-contained ES module so the copy-vendored PubDictionaries build
// stays a one-file drop-in.

// ---------------------------------------------------------------------------
// singleLlmCall — one turn, streamed
// ---------------------------------------------------------------------------
//
// Contract:
//   const result = await singleLlmCall({
//     baseUrl: 'https://meta-server.example',
//     apiKeyUuid: 'ollama-local',            // or a real llm_api_key uuid
//     modelName: 'qwen3-6-35b-fast',
//     messages: [{role: 'user', content: 'hi'}],
//     toolIds:    [12, 34],                  // optional; MCP tools registered
//                                            // on the meta-server
//     localTools: [                          // optional; inline schemas the
//       { name: 'add_dictionaries',          // client declares for its own
//         description: '...',                // page-embedded actions (window.
//         inputSchema: {...JSON Schema...} } // aiActions) that it dispatches
//     ],                                     // itself after the LLM emits.
//     generationSettings: {temperature: 0.7},// optional
//     bearerToken: 'eyJhbGci...',            // optional; anonymous if omitted
//     onTextDelta:     (str)  => {},
//     onThinkingDelta: (str)  => {},
//     onToolCall:      (tc)   => {},         // { id, name, arguments }
//     onPhase:         (name) => {},         // 'thinking' | 'tool_execution' | ...
//     signal:          abortController.signal
//   })
//   // result: { content, finishReason, toolCalls }
//
// Rejects if the server emits an `error` SSE event, or on network / abort.
export async function singleLlmCall({
  baseUrl,
  apiKeyUuid,
  modelName,
  messages,
  toolIds = [],
  localTools = [],
  generationSettings = {},
  bearerToken,
  onTextDelta,
  onThinkingDelta,
  onToolCall,
  onPhase,
  signal,
}) {
  if (!baseUrl || !apiKeyUuid || !modelName) {
    throw new Error("singleLlmCall: baseUrl, apiKeyUuid, modelName are required")
  }
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new Error("singleLlmCall: messages must be a non-empty array")
  }

  const url = `${baseUrl.replace(/\/$/, "")}/api/llm_api_keys/${encodeURIComponent(
    apiKeyUuid
  )}/models/${encodeURIComponent(modelName)}/single_llm_calls`

  const headers = { "Content-Type": "application/json", Accept: "text/event-stream" }
  if (bearerToken) headers["Authorization"] = `Bearer ${bearerToken}`

  const body = JSON.stringify({
    messages,
    tool_ids: toolIds,
    // Convert camelCase → snake_case at the wire boundary; the server's
    // strong-params permits `input_schema:` and rejects `inputSchema:`.
    local_tools: (localTools || []).map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: t.input_schema || t.inputSchema,
    })),
    generation_settings: generationSettings,
  })

  const response = await fetch(url, { method: "POST", headers, body, signal })
  if (!response.ok) {
    // Rails may render an HTML error page for routing / auth failures before
    // the SSE stream ever starts. Surface the status so callers can distinguish
    // "endpoint not there" from "stream ran but errored mid-flight".
    const text = await response.text().catch(() => "")
    throw new Error(`singleLlmCall: HTTP ${response.status} ${response.statusText}${text ? " — " + text.slice(0, 200) : ""}`)
  }
  if (!response.body) {
    throw new Error("singleLlmCall: response has no body (streaming unsupported?)")
  }

  const toolCalls = []
  let content = ""
  let finishReason = null

  // The `done` frame carries the authoritative content string too, but we
  // still concatenate deltas because the callback consumer usually wants
  // realtime rendering. The final content-from-`done` wins in case the LLM's
  // final content differs from the streamed sum (which happens with some
  // providers that emit their final text after tool_calls).

  for await (const event of parseSseStream(response.body, signal)) {
    switch (event.name) {
      case "text_delta": {
        const delta = event.data?.delta
        if (typeof delta === "string" && delta.length > 0) {
          content += delta
          onTextDelta?.(delta)
        }
        break
      }
      case "thinking_delta": {
        const delta = event.data?.delta
        if (typeof delta === "string" && delta.length > 0) {
          onThinkingDelta?.(delta)
        }
        break
      }
      case "tool_call": {
        const tc = event.data?.tool_call
        if (tc && tc.name) {
          toolCalls.push(tc)
          onToolCall?.(tc)
        }
        break
      }
      case "phase": {
        const name = event.data?.name
        if (typeof name === "string") onPhase?.(name)
        break
      }
      case "done": {
        // Server-declared final content + finish_reason. Prefer these over
        // the delta-sum when they disagree (see comment above).
        if (typeof event.data?.content === "string") content = event.data.content
        if (event.data?.finish_reason != null) finishReason = event.data.finish_reason
        return { content, finishReason, toolCalls }
      }
      case "error": {
        const code = event.data?.code || "server_error"
        const message = event.data?.message || "meta-server emitted an error event"
        const err = new Error(`singleLlmCall: ${code}: ${message}`)
        err.code = code
        throw err
      }
      // Unknown event names are ignored on purpose — the server may add new
      // ones (e.g. a future `usage` frame) without breaking older clients.
    }
  }

  // Stream closed without a `done` frame. Treat as an error so the caller
  // doesn't silently accept a truncated response as success.
  throw new Error("singleLlmCall: stream closed without done event")
}

// ---------------------------------------------------------------------------
// parseSseStream — async iterator over parsed SSE events
// ---------------------------------------------------------------------------
//
// SSE framing (per whatwg / EventSource spec):
//   - Frames are separated by a blank line (`\n\n`, possibly `\r\n\r\n`).
//   - Within a frame, each line is `field: value` or `:comment` (ignored).
//   - `event:` sets the event name (default `message`).
//   - `data:` lines accumulate; multiple `data:` lines concatenate with `\n`.
//   - `id:` and `retry:` are ignored here (we're not using automatic reconnect).
//
// Emits: { name: string, data: object | null }
//   data is JSON.parse'd if it looks like an object/array; malformed JSON is
//   surfaced as { name: 'error', data: {code, message} } so callers can bail.
export async function* parseSseStream(readableStream, signal) {
  const reader = readableStream.getReader()
  const decoder = new TextDecoder("utf-8")
  let buffer = ""

  const onAbort = () => { try { reader.cancel() } catch { /* noop */ } }
  signal?.addEventListener("abort", onAbort)

  try {
    while (true) {
      const { value, done } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })

      // Split on frame boundary. Keep the trailing partial in `buffer`.
      let sepIdx
      // Accept CRLF or LF-only boundaries; the meta-server emits LF-only but
      // proxies (nginx, cloudflare) sometimes reformat.
      while (
        (sepIdx = indexOfEither(buffer, "\n\n", "\r\n\r\n")) !== -1
      ) {
        const rawFrame = buffer.slice(0, sepIdx)
        buffer = buffer.slice(
          sepIdx + (buffer.slice(sepIdx, sepIdx + 4) === "\r\n\r\n" ? 4 : 2)
        )
        const parsed = parseSseFrame(rawFrame)
        if (parsed) yield parsed
      }
    }
    // Flush any trailing frame that wasn't followed by a blank line.
    if (buffer.trim().length > 0) {
      const parsed = parseSseFrame(buffer)
      if (parsed) yield parsed
    }
  } finally {
    signal?.removeEventListener("abort", onAbort)
    try { reader.releaseLock() } catch { /* noop */ }
  }
}

function indexOfEither(str, a, b) {
  const ai = str.indexOf(a)
  const bi = str.indexOf(b)
  if (ai === -1) return bi
  if (bi === -1) return ai
  return Math.min(ai, bi)
}

// ---------------------------------------------------------------------------
// runTurn — one LLM turn + fire-and-forget local dispatch
// ---------------------------------------------------------------------------
//
// The Piece-B primitive: driven by `singleLlmCall`, then after `done` invokes
// any tool_calls that name an entry in `aiActions` (window.aiActions on the
// host page). Sequential invocation preserves the order the LLM emitted them
// in — avoids races on shared DOM state (e.g. two aiActions mutating the same
// selection list).
//
// Fire-and-forget = no result is fed back to the LLM. If a caller wants
// LLM-loop semantics (tool result → follow-up LLM turn), that's Piece D.
//
// Contract:
//   const result = await runTurn({
//     ...singleLlmCall opts,
//     aiActions: window.aiActions       // { name: (args) => any|Promise }
//   })
//   // result: { content, finishReason, toolCalls,
//   //           dispatched: [{ toolCall, value|error }],
//   //           skipped:    [ toolCall ] }
//
// `dispatched` covers everything invoked (whether it succeeded or threw);
// `skipped` covers tool_calls whose name isn't in aiActions — Piece D turns
// those into MCP proxy round-trips. Errors from aiActions are captured, NOT
// thrown, so one broken action doesn't stop the rest of the batch.
export async function runTurn(opts) {
  const { aiActions = {}, ...singleOpts } = opts
  const result = await singleLlmCall(singleOpts)
  const { dispatched, skipped } = await dispatchLocalToolCalls(result.toolCalls, aiActions)
  return { ...result, dispatched, skipped }
}

// Standalone dispatcher — exposed for tests, and for Piece D which wants to
// separate the local phase from its own remote-loop logic.
export async function dispatchLocalToolCalls(toolCalls, aiActions) {
  const dispatched = []
  const skipped = []
  for (const tc of toolCalls || []) {
    const handler = aiActions?.[tc.name]
    if (typeof handler !== "function") {
      skipped.push(tc)
      continue
    }
    const args = coerceArguments(tc.arguments)
    try {
      const value = await handler(args)
      dispatched.push({ toolCall: tc, value })
    } catch (error) {
      dispatched.push({ toolCall: tc, error })
    }
  }
  return { dispatched, skipped }
}

// ---------------------------------------------------------------------------
// runChatLoop — Piece D: client-orchestrated multi-turn loop
// ---------------------------------------------------------------------------
//
// Wraps `singleLlmCall` in an actual loop so the LLM can call remote MCP
// tools, see their results, and produce a synthesized final response.
//
// Per round:
//   1. call `singleLlmCall` with local_tools + tool_ids
//   2. split emitted tool_calls into local (in aiActions) / remote
//      (in remoteTools by name) / unknown
//   3. dispatch locals fire-and-forget (no result fed back)
//   4. dispatch remotes via POST /api/mcp_tools/:id/call → collect results
//   5. if any remote calls happened, append assistant-with-tool_calls turn
//      and one role:tool message per result; loop
//   6. terminate when there are no remote calls (locals never round-trip),
//      or on hitting maxRounds
//
// Contract:
//   const result = await runChatLoop({
//     ...singleLlmCall opts,
//     aiActions:    window.aiActions,
//     remoteTools:  [{id, name, description, input_schema}, ...],
//     maxRounds:    10,
//     onRoundStart: (idx) => {},           // optional
//     onTextDelta:  (delta, roundIdx) => {},  // per-turn (roundIdx added)
//   })
//   // result: {
//   //   content, finishReason,             // from the FINAL turn
//   //   rounds: [{ round, ...singleLlmCall result, localCalls, remoteCalls, unknownCalls }],
//   //   dispatched: [{ toolCall, value|error }],  // all rounds combined
//   //   skipped:    [ toolCall ]           // truly unknown names across all rounds
//   // }
//
// NOTE on tool-name mapping: remoteTools[].name must match the name the LLM
// sees, which is what the server declares to the provider. MCP tool names
// go through McpToolAdapter.sanitize_name server-side; for pilot we assume
// no sanitization was needed (tool names already in [a-zA-Z0-9_-]{1,64}).
// If future MCP tools have unusual characters and get sanitized, the widget
// would need the sanitized name in remoteTools[].name.
export async function runChatLoop(opts) {
  const {
    aiActions = {},
    remoteTools = [],
    maxRounds = 10,
    onRoundStart,
    onTextDelta,
    onThinkingDelta,
    onToolCall,
    onPhase,
    ...singleOpts
  } = opts

  const messages   = [ ...(singleOpts.messages || []) ]
  const remoteByName = Object.fromEntries((remoteTools || []).map((t) => [ t.name, t ]))
  const toolIds    = [ ...(singleOpts.toolIds || []), ...(remoteTools || []).map((t) => t.id) ]

  const rounds = []
  const allDispatched = []
  const allSkipped = []
  let lastResult = null

  for (let round = 0; round < maxRounds; round++) {
    onRoundStart?.(round)

    const turnResult = await singleLlmCall({
      ...singleOpts,
      messages,
      toolIds,
      onTextDelta:     onTextDelta     ? (d) => onTextDelta(d, round)     : undefined,
      onThinkingDelta: onThinkingDelta ? (d) => onThinkingDelta(d, round) : undefined,
      onToolCall:      onToolCall      ? (t) => onToolCall(t, round)      : undefined,
      onPhase:         onPhase         ? (n) => onPhase(n, round)         : undefined
    })
    lastResult = turnResult

    // Classify tool_calls
    const localCalls = []
    const remoteCalls = []
    const unknownCalls = []
    for (const tc of turnResult.toolCalls || []) {
      if (typeof aiActions[tc.name] === "function") localCalls.push(tc)
      else if (remoteByName[tc.name])                remoteCalls.push(tc)
      else                                            unknownCalls.push(tc)
    }

    // Locals: fire-and-forget
    const localOut = await dispatchLocalToolCalls(localCalls, aiActions)
    allDispatched.push(...localOut.dispatched)

    // Remotes: round-trip. Track results in the ORDER the LLM emitted them
    // so tool_call_id pairs line up with the assistant's tool_calls entries.
    const remoteResults = []
    for (const tc of remoteCalls) {
      const tool = remoteByName[tc.name]
      const args = coerceArguments(tc.arguments)
      try {
        const value = await dispatchRemoteToolCall({
          baseUrl:     singleOpts.baseUrl,
          bearerToken: singleOpts.bearerToken,
          toolId:      tool.id,
          args:        args
        })
        allDispatched.push({ toolCall: tc, value })
        remoteResults.push({ tc, result: value })
      } catch (error) {
        allDispatched.push({ toolCall: tc, error })
        // Feed the error text back to the LLM as the tool result — better
        // than dropping it (the LLM can react, apologize, retry differently).
        remoteResults.push({ tc, result: { error: String(error.message || error) } })
      }
    }

    allSkipped.push(...unknownCalls)
    rounds.push({
      round, content: turnResult.content, finishReason: turnResult.finishReason,
      localCalls, remoteCalls, unknownCalls,
      toolCalls: turnResult.toolCalls
    })

    // No remote calls → nothing to feed back → done. Locals were fire-and-
    // forget; unknowns are the caller's problem.
    if (remoteCalls.length === 0) {
      return {
        content: turnResult.content,
        finishReason: turnResult.finishReason,
        rounds, dispatched: allDispatched, skipped: allSkipped
      }
    }

    // Build follow-up: assistant-with-tool_calls + one tool-result per remote.
    // Server-side: LlmRbFacade#messages_to_llm_objects preserves the
    // assistant-with-tool_calls entry via LLM::Message.extra[:tool_calls],
    // and split_history_from_current_input bundles the trailing tool-results
    // as the input to the next session.chat call.
    messages.push({
      role: "assistant",
      content: turnResult.content || "",
      tool_calls: turnResult.toolCalls
    })
    for (const { tc, result } of remoteResults) {
      messages.push({
        role: "tool",
        tool_call_id: tc.id || "",
        name: tc.name,
        content: typeof result === "string" ? result : JSON.stringify(result)
      })
    }
  }

  // Hit the cap without terminating. Return what we have + a diagnostic flag
  // so the widget can render "stopped after N rounds" instead of hanging.
  return {
    content: lastResult?.content || "",
    finishReason: lastResult?.finishReason || null,
    rounds, dispatched: allDispatched, skipped: allSkipped,
    stopped_reason: `max_rounds (${maxRounds}) exceeded`
  }
}

// Standalone remote dispatcher — POSTs one tool_call to the meta-server's
// MCP proxy endpoint. Exposed for tests + reuse.
export async function dispatchRemoteToolCall({ baseUrl, bearerToken, toolId, args }) {
  if (!baseUrl || toolId == null) {
    throw new Error("dispatchRemoteToolCall: baseUrl and toolId are required")
  }
  const url = `${baseUrl.replace(/\/$/, "")}/api/mcp_tools/${encodeURIComponent(toolId)}/call`
  const headers = { "Content-Type": "application/json" }
  if (bearerToken) headers["Authorization"] = `Bearer ${bearerToken}`

  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ arguments: args || {} })
  })
  if (!response.ok) {
    const text = await response.text().catch(() => "")
    throw new Error(`dispatchRemoteToolCall: HTTP ${response.status} ${response.statusText}${text ? " — " + text.slice(0, 200) : ""}`)
  }
  const body = await response.json()
  return body.result
}

// llm.rb's Session#extract_tool_calls delivers `arguments` as a parsed object
// (the OpenAI/Anthropic/Gemini adapters all parse before we see them). But
// SOMETIMES a provider passes through a raw JSON string (Gemini streaming
// edge cases have done this in the past). Coerce defensively so aiActions
// always receive an object.
function coerceArguments(raw) {
  if (raw == null) return {}
  if (typeof raw === "object") return raw
  if (typeof raw === "string") {
    try { return JSON.parse(raw) } catch { return { _raw: raw } }
  }
  return { _raw: raw }
}

function parseSseFrame(raw) {
  let name = "message"
  const dataLines = []

  for (const line of raw.split("\n")) {
    if (line.length === 0 || line.startsWith(":")) continue
    const colon = line.indexOf(":")
    const field = colon === -1 ? line : line.slice(0, colon)
    // Per spec: single leading space after the colon is stripped.
    let value = colon === -1 ? "" : line.slice(colon + 1)
    if (value.startsWith(" ")) value = value.slice(1)

    if (field === "event") name = value
    else if (field === "data") dataLines.push(value)
    // id / retry ignored
  }

  if (dataLines.length === 0 && name === "message") return null

  const dataStr = dataLines.join("\n")
  let data = null
  if (dataStr.length > 0) {
    try {
      data = JSON.parse(dataStr)
    } catch (e) {
      // Emit the raw string — callers that care can inspect it.
      data = { _raw: dataStr, _parseError: e.message }
    }
  }
  return { name, data }
}
