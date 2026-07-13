# HTML Render Worker

MobileCore keeps the rendering boundary split by artifact cost:

| Output | Default backend | Runtime requirement |
| --- | --- | --- |
| PNG | Android WebView / iOS WKWebView | Mobile app only |
| PDF | Android `PdfDocument` / iOS `WKWebView.createPDF` | Mobile app only; iOS 14+ for native PDF |
| MP4 | HyperFrames worker | Node.js 22+, Chromium and FFmpeg on Helper/host |
| PPTX | HTML-to-PPTX worker | Node.js 18+, Playwright Chromium and `pptxgenjs` |

The app-side contract is `mobilecode.html-render.v1`, implemented by
`HtmlRenderProvider`. `PlatformHtmlRenderProvider` calls the native channel for
PNG/PDF. `HyperFramesHtmlRenderProvider` calls `POST /v1/render/html`, then
downloads the worker's artifact URL and recomputes the SHA-256 before the file
enters MobileCore's artifact store.

## Start the worker

From a machine with Node.js 22+, FFmpeg and the HyperFrames CLI available:

```sh
python3 mobile_agent/tooling/mobilecode_hyperframes_worker.py \
  --host 0.0.0.0 \
  --port 8790 \
  --public-base-url http://HOST:8790
```

Set `MOBILECODE_HTML_WORKER_TOKEN` and pass the same bearer token to
`HyperFramesHtmlRenderProvider` before exposing the worker beyond loopback.
The worker accepts inline HTML, a source path below `--source-root`, or an
`http(s)` URL visible from the worker. It never accepts a shell command from the
phone.

For an Android emulator, a host-loopback worker is normally addressed through
`http://10.0.2.2:8790/v1/render/html`; a physical device needs a reachable
LAN/TLS endpoint or an approved relay. Alpine Linux is optional here: it can
host the CLI worker when Node.js, Chromium and FFmpeg are installed, but it is
not needed for local PNG/PDF and it does not solve model inference by itself.

HyperFrames is used as the external frame engine because its CLI renders HTML
compositions through headless Chrome and FFmpeg, while MobileCore remains the
mobile evidence/artifact owner. See the upstream [HyperFrames repository](https://github.com/heygen-com/hyperframes).

## PPTX export

Install the worker dependencies and browser once:

```sh
cd mobile_agent/tooling/html-pptx-worker
npm install
npx playwright install chromium
node mobilecode_html_to_pptx_worker.mjs --port 8792
```

If Playwright's bundled browser is not installed, pass a system Chrome path:
`--chrome-path "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.

The default PPTX mode is `visual`: each HTML slide is captured through the
same Chromium runtime and inserted as a full-slide image. This follows the
high-fidelity path used by [html-to-pptx](https://github.com/nlj626/html-to-pptx)
and keeps CSS, fonts, gradients and animation states intact. The request
already carries `pptxMode=editableText` for the future hybrid backend inspired
by [html2pptx](https://github.com/Nanford/html2pptx), but that mode currently
fails explicitly instead of pretending that every HTML element is editable.
