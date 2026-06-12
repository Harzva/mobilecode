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
