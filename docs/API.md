# LahLah Voice local API (macOS)

Start and stop dictation, read the last transcript and send commands to LahLah Video from scripts, Claude or LahLah Video itself.

- **Local only:** HTTP on `127.0.0.1`, random port. Nothing on your network can reach it.
- **API key:** Settings › API shows it (Show, Copy, Regenerate). It is stored in your login Keychain as "LahLah Voice API key", never in a file. Send it as `Authorization: Bearer <key>` or `X-API-Key: <key>`.
- **On/off:** Settings › API › Allow API control. Off: every call gets `403`.
- **Port:** `~/Library/Application Support/NovaVoice/control.json` holds `port` and `baseUrl` (user-only permissions).

| Method and path | Body | Does |
|---|---|---|
| `GET /v1/health` | | Is the app up |
| `GET /v1/status` | | `{ app, version, phase: idle\|listening\|working, mode, lastTranscript, lahlahVideoAvailable }` |
| `POST /v1/dictation/start` | | Starts hands-free dictation into the app in front |
| `POST /v1/dictation/stop` | | Stops; the text is inserted (or sent, in LahLah Video mode) |
| `GET /v1/transcripts/last` | | The last dictation: `{ raw, final, appName, date, … }` |
| `PUT /v1/mode` | `{"mode":"normal"}` or `{"mode":"lahlah-video-command"}` | In `lahlah-video-command` mode every utterance goes to LahLah Video as an edit |
| `POST /v1/lahlah-video/send` | `{"text":"split here"}` | Forwards a command to LahLah Video: through its API (key from its `control.json`) when it runs, else the `lahlahvideo://command` link. Answers `{ ok, via: "api"\|"deep-link", message }` |

```bash
PORT=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Library/Application Support/NovaVoice/control.json')))['port'])")
KEY="llvo_…"   # Settings › API › Copy
curl -s -H "Authorization: Bearer $KEY" -X PUT http://127.0.0.1:$PORT/v1/mode -d '{"mode":"lahlah-video-command"}'
curl -s -H "Authorization: Bearer $KEY" -X POST http://127.0.0.1:$PORT/v1/lahlah-video/send -d '{"text":"add crossfade"}'
```
