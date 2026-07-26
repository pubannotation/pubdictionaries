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
// Wraps `singleLlmCall` in an actual loop so the LLM can call tools, see
// their results, and produce a synthesized final response.
//
// Handles all three tool classes (see memory: project_mcp_tool_classes):
//   Class 1 — remoteTools[]:   hub-registered; POST via meta-server proxy
//   Class 2 — hostWideTools[]: well-known; POST directly to host's /mcp
//   Class 3 — aiActions:       page-embedded; invoke JS in-process
//
// Per round:
//   1. call `singleLlmCall` with merged local_tools (Class 2 + 3 schemas) +
//      tool_ids (Class 1 references)
//   2. classify emitted tool_calls by name (aiActions → hostWide → remote → unknown)
//   3. dispatch Class 3 fire-and-forget
//   4. dispatch Class 2 via direct MCP; Class 1 via meta-server proxy;
//      collect results in emission order
//   5. if any round-trip results, append assistant-with-tool_calls turn and
//      one role:tool message per result; loop
//   6. terminate when no round-trip results (Class 3 alone doesn't loop),
//      or on hitting maxRounds
//
// Contract:
//   const result = await runChatLoop({
//     ...singleLlmCall opts,
//     aiActions:     window.aiActions,
//     hostWideTools: [{ name, description, input_schema, endpoint }, ...],
//     remoteTools:   [{ id, name, description, input_schema }, ...],
//     maxRounds:     10,
//     onRoundStart:  (idx) => {},
//     onTextDelta:   (delta, roundIdx) => {}
//   })
//   // result: {
//   //   content, finishReason,
//   //   rounds: [{ round, ..., localCalls, hostWideCalls, remoteCalls, unknownCalls }],
//   //   dispatched: [{ toolCall, value|error }],
//   //   skipped:    [ toolCall ]
//   // }
//
// NOTE on tool-name mapping: Class 1 remoteTools[].name must match the name
// the LLM sees, which is what the server declares to the provider (may be
// sanitized by McpToolAdapter). Class 2 and Class 3 tool names go through
// unmodified — LLM sees them as declared in local_tools.
export async function runChatLoop(opts) {
  const {
    aiActions = {},
    remoteTools = [],
    hostWideTools = [],
    maxRounds = 10,
    signal,
    onRoundStart,
    onTextDelta,
    onThinkingDelta,
    onToolCall,
    onPhase,
    ...singleOpts
  } = opts

  const messages     = [ ...(singleOpts.messages || []) ]
  const remoteByName = Object.fromEntries((remoteTools || []).map((t) => [ t.name, t ]))
  // Class 2: host-wide MCP tools (well-known). Map name→{endpoint, ...} for
  // dispatch. If the same name appears in aiActions, Class 3 wins there
  // (checked first in the classifier below); if it also appears in remoteTools,
  // Class 2 wins over Class 1 (host-owned is more direct).
  const hostWideByName = Object.fromEntries((hostWideTools || []).map((t) => [ t.name, t ]))
  const toolIds      = [ ...(singleOpts.toolIds || []), ...(remoteTools || []).map((t) => t.id) ]

  // Class 2 schemas ride inline via local_tools (LLM sees them like Class 3).
  // De-dupe by name; Class 3 wins so we don't clobber an aiAction's schema.
  const inlineByName = {}
  for (const t of singleOpts.localTools || []) inlineByName[t.name] = t
  for (const t of hostWideTools || []) {
    if (!inlineByName[t.name]) inlineByName[t.name] = { name: t.name, description: t.description, input_schema: t.input_schema }
  }
  const mergedLocalTools = Object.values(inlineByName)

  const rounds = []
  const allDispatched = []
  const allSkipped = []
  let lastResult = null

  for (let round = 0; round < maxRounds; round++) {
    // Bail immediately on external abort — don't start a new LLM turn if
    // the user hit Clear / navigated away between rounds.
    if (signal?.aborted) throw new DOMException("aborted", "AbortError")
    onRoundStart?.(round)

    const turnResult = await singleLlmCall({
      ...singleOpts,
      messages,
      toolIds,
      localTools:      mergedLocalTools,
      signal,
      onTextDelta:     onTextDelta     ? (d) => onTextDelta(d, round)     : undefined,
      onThinkingDelta: onThinkingDelta ? (d) => onThinkingDelta(d, round) : undefined,
      onToolCall:      onToolCall      ? (t) => onToolCall(t, round)      : undefined,
      onPhase:         onPhase         ? (n) => onPhase(n, round)         : undefined
    })
    lastResult = turnResult

    // Classify tool_calls by class. Precedence: Class 3 (aiActions, no
    // network, same-page) → Class 2 (host-wide well-known, direct MCP) →
    // Class 1 (hub-registered, meta-server proxy) → unknown.
    const localCalls    = []  // Class 3
    const hostWideCalls = []  // Class 2
    const remoteCalls   = []  // Class 1
    const unknownCalls  = []
    for (const tc of turnResult.toolCalls || []) {
      if      (typeof aiActions[tc.name] === "function") localCalls.push(tc)
      else if (hostWideByName[tc.name])                  hostWideCalls.push(tc)
      else if (remoteByName[tc.name])                    remoteCalls.push(tc)
      else                                                unknownCalls.push(tc)
    }

    // Class 3: locals — fire-and-forget
    const localOut = await dispatchLocalToolCalls(localCalls, aiActions)
    allDispatched.push(...localOut.dispatched)

    // Class 2: host-wide — direct MCP JSON-RPC POST to the host's own endpoint
    const roundTripResults = []
    for (const tc of hostWideCalls) {
      const tool = hostWideByName[tc.name]
      const args = coerceArguments(tc.arguments)
      try {
        const value = await callMcpTool({ endpoint: tool.endpoint, name: tc.name, args, signal })
        allDispatched.push({ toolCall: tc, value })
        roundTripResults.push({ tc, result: value })
      } catch (error) {
        allDispatched.push({ toolCall: tc, error })
        roundTripResults.push({ tc, result: { error: String(error.message || error) } })
      }
    }

    // Class 1: remote — meta-server proxy round-trip. Order preserved.
    for (const tc of remoteCalls) {
      const tool = remoteByName[tc.name]
      const args = coerceArguments(tc.arguments)
      try {
        const value = await dispatchRemoteToolCall({
          baseUrl:     singleOpts.baseUrl,
          bearerToken: singleOpts.bearerToken,
          toolId:      tool.id,
          args:        args,
          signal
        })
        allDispatched.push({ toolCall: tc, value })
        roundTripResults.push({ tc, result: value })
      } catch (error) {
        allDispatched.push({ toolCall: tc, error })
        // Feed the error text back to the LLM as the tool result — better
        // than dropping it (the LLM can react, apologize, retry differently).
        roundTripResults.push({ tc, result: { error: String(error.message || error) } })
      }
    }

    allSkipped.push(...unknownCalls)
    rounds.push({
      round, content: turnResult.content, finishReason: turnResult.finishReason,
      localCalls, hostWideCalls, remoteCalls, unknownCalls,
      toolCalls: turnResult.toolCalls
    })

    // Terminate when there's nothing to feed back. Locals (Class 3) are
    // fire-and-forget; unknowns can't be handled; only Class 2 + Class 1
    // execution produces tool results the LLM should see.
    if (roundTripResults.length === 0) {
      return {
        content: turnResult.content,
        finishReason: turnResult.finishReason,
        rounds, dispatched: allDispatched, skipped: allSkipped
      }
    }

    // Build follow-up: assistant-with-tool_calls + one tool-result per
    // round-tripped call (both Class 2 and Class 1). Server-side:
    // LlmRbFacade#messages_to_llm_objects preserves the assistant-with-
    // tool_calls entry via LLM::Message.extra[:tool_calls], and
    // split_history_from_current_input bundles the trailing tool-results
    // as the input to the next session.chat call.
    messages.push({
      role: "assistant",
      content: turnResult.content || "",
      tool_calls: turnResult.toolCalls
    })
    for (const { tc, result } of roundTripResults) {
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

// ---------------------------------------------------------------------------
// Class 2: host-wide MCP tools (well-known + direct dispatch)
// ---------------------------------------------------------------------------
//
// See memory: project_mcp_tool_classes. Class 2 tools are declared by the
// HOST site at `${origin}/.well-known/mcp.json` and executed by the widget
// posting JSON-RPC 2.0 `tools/call` DIRECTLY to the host's own MCP endpoint
// — no meta-server proxy in the loop. This dissolves the "widget-to-meta-
// server auth" question for same-origin host-owned tools: browser session
// cookies flow through automatically.
//
// Manifest shape (widget accepts):
//   {
//     "servers": [
//       { "name": "pubdictionaries",
//         "url":  "/mcp",                      // relative or absolute
//         "tools": [
//           { "name": "text_annotation",
//             "description": "...",
//             "input_schema": {...} }
//         ] }
//     ]
//   }
//
// The `url` is resolved against the manifest URL's origin, so a same-origin
// host can just say `/mcp` and the widget fills in the rest.

// Fetch a well-known manifest and normalize it: absolute URLs, flat tool list
// with the owning server's endpoint attached to each entry for dispatch.
// Fails gracefully — returns [] on network / parse error so a missing or
// malformed manifest doesn't kill the widget's boot.
export async function fetchMcpManifest(manifestUrl) {
  let manifest
  try {
    const response = await fetch(manifestUrl)
    if (!response.ok) return []
    manifest = await response.json()
  } catch { return [] }

  const base = new URL(manifestUrl)
  const out = []
  for (const server of manifest?.servers || []) {
    let endpoint
    try { endpoint = new URL(server.url, base).toString() } catch { continue }
    for (const tool of server.tools || []) {
      if (!tool.name) continue
      out.push({
        name:         tool.name,
        description:  tool.description || "",
        input_schema: tool.input_schema || tool.inputSchema || { type: "object", properties: {} },
        endpoint,
        serverName:   server.name || null
      })
    }
  }
  return out
}

// JSON-RPC 2.0 `tools/call` POST to an MCP endpoint. Returns the parsed
// `result` value (or throws on JSON-RPC error / HTTP failure). Supports
// both JSON and SSE responses (MCP over HTTP allows either).
let _mcpReqId = 0
export async function callMcpTool({ endpoint, name, args, signal }) {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept":       "application/json, text/event-stream"
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id:      ++_mcpReqId,
      method:  "tools/call",
      params:  { name, arguments: args || {} }
    }),
    signal,
    // Send session cookies for same-origin MCP endpoints. Cross-origin CORS
    // with credentials requires the server to echo Access-Control-Allow-
    // Credentials: true — which most MCP servers won't. This is fine: for
    // cross-origin the widget doesn't send cookies; the server enforces
    // its own auth (API key in header, etc.) if it wants any.
    credentials: "same-origin"
  })
  if (!response.ok) {
    const text = await response.text().catch(() => "")
    throw new Error(`callMcpTool(${name}): HTTP ${response.status}${text ? " — " + text.slice(0, 200) : ""}`)
  }

  const contentType = response.headers.get("content-type") || ""

  if (contentType.includes("application/json")) {
    const body = await response.json()
    if (body?.error) {
      throw new Error(`callMcpTool(${name}): ${body.error.message || "JSON-RPC error"}`)
    }
    return body?.result
  }

  if (contentType.includes("text/event-stream")) {
    // MCP over SSE — each SSE `data:` frame is a JSON-RPC message.
    for await (const evt of parseSseStream(response.body, signal)) {
      const payload = evt.data
      if (!payload || typeof payload !== "object") continue
      if (payload.error) {
        throw new Error(`callMcpTool(${name}): ${payload.error.message || "JSON-RPC error"}`)
      }
      if ("result" in payload) return payload.result
    }
    throw new Error(`callMcpTool(${name}): SSE stream ended without result`)
  }

  throw new Error(`callMcpTool(${name}): unexpected content-type ${contentType}`)
}

// Standalone remote dispatcher — POSTs one tool_call to the meta-server's
// MCP proxy endpoint. Exposed for tests + reuse.
export async function dispatchRemoteToolCall({ baseUrl, bearerToken, toolId, args, signal }) {
  if (!baseUrl || toolId == null) {
    throw new Error("dispatchRemoteToolCall: baseUrl and toolId are required")
  }
  const url = `${baseUrl.replace(/\/$/, "")}/api/mcp_tools/${encodeURIComponent(toolId)}/call`
  const headers = { "Content-Type": "application/json" }
  if (bearerToken) headers["Authorization"] = `Bearer ${bearerToken}`

  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ arguments: args || {} }),
    signal
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
