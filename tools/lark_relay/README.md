# Lark Relay

This folder contains a minimal Lark relay skeleton for evidence work.
It provides an offline mock loop and a live `lark-cli event consume` bridge.

The mock loop:

1. accept or create a mock event
2. enqueue into an in-memory queue
3. run an agent stub
4. execute an IM dry-run send adapter
5. write structured evidence JSON

No real network calls or credentials are used.

## Mock quick start

```bash
python tools/lark_relay/mock_relay_runner.py \
  --message "你好，帮我回复一段测试内容" \
  --tool "lark.relay.mock"
```

The command prints the output path and dumps the evidence JSON file under:

`tools/lark_relay/evidence/<dry_run_id>.json`

## Useful options

- `--event-json '<json>'` to feed a mock event payload
- `--event-file path/to/event.json` to load payload from file
- `--simulate-failure none|agent_error|send_blocked`
- `--output path/to/evidence.json` to override output file path

## Live event bridge

The live bridge consumes Lark IM receive events with:

```bash
lark-cli event consume im.message.receive_v1 --as bot
```

Then it converts the event into the local relay shape, runs the same agent
adapter, and calls:

```bash
lark-cli im +messages-reply --as bot --message-id <om_xxx> --text <reply>
```

Agent mode switch (default mock):

```bash
python3 tools/lark_relay/live_event_relay.py \
  --max-events 1 \
  --send-mode dry-run \
  --agent-mode command \
  --agent-command "python3 tools/lark_relay/my_local_agent.py"
```

The command mode uses the normalized message text as stdin, and uses command
stdout as the relay reply.

OpenAI-compatible command agent adapter:

```bash
export MOBILECODE_AGENT_API_KEY=<your_api_key>
export MOBILECODE_AGENT_API_URL=https://api.deepseek.com/chat/completions
export MOBILECODE_AGENT_MODEL=deepseek-chat

python3 tools/lark_relay/live_event_relay.py \
  --max-events 1 \
  --send-mode dry-run \
  --agent-mode command \
  --agent-command "python3 tools/lark_relay/agent_command_openai_compatible.py"
```

Dry-run is the default send mode. Use live reply only intentionally:
`--send-mode live --allow-live`.

Default mode is safe dry-run reply:

```bash
python3 tools/lark_relay/live_event_relay.py \
  --max-events 1 \
  --timeout 2m \
  --send-mode dry-run \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix
```

For a real bot reply, use an explicit live confirmation:

```bash
python3 tools/lark_relay/live_event_relay.py \
  --max-events 1 \
  --timeout 2m \
  --send-mode live \
  --allow-live \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix
```

Minimal daemon mode restarts one `lark-cli event consume` cycle after each
timeout or processed batch, and keeps an ignored state file for `event_id`
de-duplication:

```bash
python3 tools/lark_relay/live_event_relay.py \
  --daemon \
  --max-events 1 \
  --timeout 2m \
  --send-mode dry-run \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix
```

Live daemon replies still require the explicit live guard:

```bash
python3 tools/lark_relay/live_event_relay.py \
  --daemon \
  --max-events 1 \
  --timeout 2m \
  --send-mode live \
  --allow-live \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix \
  --agent-mode command \
  --agent-command "python3 tools/lark_relay/agent_command_openai_compatible.py"
```

Daemon state defaults to
`tools/lark_relay/evidence/.relay-daemon-state.json`, which is ignored by Git.
It stores processed `event_id` values only; do not put tokens or raw auth logs in
the state file.

Recommended first test: send the bot a private message that starts with
`/mc `, for example `/mc 你好`.

Prerequisites:

- `lark-cli auth status` shows bot identity ready.
- The app has the `im.message.receive_v1` event enabled in the developer console.
- The app has receive-message scope such as `im:message.p2p_msg:readonly`.
- Reply/send scopes and bot chat membership are available when moving from
  dry-run to live send.

Live bridge evidence records the event, normalized relay event, consumer
stderr tail, reply command, reply result, failure kind, next action, and
dry-run/live mode.

Evidence JSON may contain chat IDs, message IDs, and sender open IDs. Keep
`tools/lark_relay/evidence/*.json` local unless it has been explicitly
sanitized for public sharing.

Public-safe samples live under `tools/lark_relay/samples/`. For example,
`samples/live_reply_success.sanitized.json` is the shape consumed by MobileCode
Lark API Lab to render an event -> reply -> evidence timeline without exposing
chat IDs, open IDs, message IDs, or private message content.

## Sanitized evidence feed

MobileCode Lark API Lab can now sync a sanitized relay evidence feed instead of
only rendering built-in samples. The feed reads ignored local relay evidence,
redacts chat IDs, open IDs, message IDs, tokens, and message content, then serves
only the public-safe projection:

```bash
python3 tools/lark_relay/evidence_feed_server.py --print-once
```

Run a local managed endpoint for the App:

```bash
python3 tools/lark_relay/evidence_feed_server.py \
  --host 127.0.0.1 \
  --port 8787
```

Use `http://127.0.0.1:8787` as the relay URL for iOS simulator or local desktop
testing. Android emulator usually reaches the Mac host with
`http://10.0.2.2:8787`.

For a managed relay, set an optional bearer token through the environment. Put
the same value in the App's relay token field; do not commit or print it:

```bash
export MOBILECODE_LARK_EVIDENCE_FEED_TOKEN=<relay_token>
python3 tools/lark_relay/evidence_feed_server.py --host 127.0.0.1 --port 8787
```

Endpoint contract:

- `GET /health` returns service readiness.
- `GET /lark/evidence?limit=20` returns `mobilecode.lark_relay.evidence_feed.v1`.
- If `MOBILECODE_LARK_EVIDENCE_FEED_TOKEN` is set, `/lark/evidence` requires
  `Authorization: Bearer <relay_token>`.
- The App may also paste/import the same sanitized JSON feed manually.
- Raw `tools/lark_relay/evidence/*.json` remains ignored and should not be
  committed.

## Dev-log Docx chain

The first end-to-end product chain is:

`/mc 写开发日志` -> relay event -> command agent -> Lark Docx create -> bot reply
with link -> sanitized evidence feed -> MobileCode Lark API Lab.

Dry-run the command agent without any Lark write:

```bash
printf '/mc 写开发日志\n' | \
  python3 tools/lark_relay/agent_command_dev_log_docx.py
```

Wire it into the live relay in dry-run reply mode:

```bash
python3 tools/lark_relay/live_event_relay.py \
  --daemon \
  --max-events 1 \
  --timeout 2m \
  --send-mode dry-run \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix \
  --agent-mode command \
  --agent-command "python3 tools/lark_relay/agent_command_dev_log_docx.py"
```

Live Docx creation is a real write. Confirm the target folder and scopes first,
then opt in explicitly:

```bash
export MOBILECODE_LARK_DEVLOG_MODE=live
export MOBILECODE_LARK_DEVLOG_ALLOW_LIVE=1
export MOBILECODE_LARK_DEVLOG_FOLDER_TOKEN=<target_folder_token>

python3 tools/lark_relay/live_event_relay.py \
  --daemon \
  --max-events 1 \
  --timeout 2m \
  --send-mode live \
  --allow-live \
  --trigger-prefix "/mc " \
  --strip-trigger-prefix \
  --agent-mode command \
  --agent-command "python3 tools/lark_relay/agent_command_dev_log_docx.py"
```

The sanitized sample `samples/dev_log_docx_chain.sanitized.json` mirrors this
chain for public UI testing without exposing a real document URL.

Command agents may emit structured evidence metadata on stderr with the prefix
`MOBILECODE_RELAY_META_JSON=`. The relay keeps stdout as the bot reply, removes
the marker from visible stderr, and copies supported metadata such as
`chain_stage` and `lark_docx` into the evidence file.

## Expected event payload example

```json
{
  "event_id": "evt-123",
  "request_id": "req-123",
  "chat_id": "chat-001",
  "sender_id": "user-001",
  "message_text": "私聊消息内容"
}
```

Alternative schema is also accepted:

```json
{
  "event_id": "evt-123",
  "request_id": "req-123",
  "message": {
    "text": "私聊消息内容"
  }
}
```

## Evidence fields

The produced JSON contains at least:

- `event_id`
- `tool`
- `request_id`
- `dry_run_id`
- `failure_kind`
- `next_action`
- `message_text`
- `reply_text`
- `agent`
- `timestamp`
