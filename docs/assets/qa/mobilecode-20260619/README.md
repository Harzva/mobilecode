# MobileCode QA Share Assets - 2026-06-19

These screenshots are public-safe share assets curated from Android emulator QA.

Do not claim Chrome direct-tap support from this folder. The Chrome direct download tap is included as a limitation screenshot because Chrome opened the downloaded HTML in its own `content://` tab on the emulator. The Chrome share route remains an alternate path to present separately from direct-tap support.

## Product Flow Screenshots

- `01-app-home-deepseek-inbuilt.png` - MobileCode home with the built-in DeepSeek preset.
- `02-snake-generated-artifact-card.png` - generated artifact card for a phone-created HTML game.
- `03-snake-playable-webview.png` - playable snake game in MobileCode WebView preview.

## HTML Open-With Evidence

- `04-files-downloads-html-file.png` - Android Files / DocumentsUI showing the HTML file in Downloads.
- `05-android-open-with-mobilecode.png` - Android resolver offering MobileCode for the HTML file.
- `06-mobilecode-preview-from-files.png` - MobileCode rendering the HTML opened from Files.
- `07-chrome-direct-open-limitation.png` - Chrome direct download tap limitation; Chrome opened the file itself.
- `08-chrome-share-alternate.png` - Chrome share alternate path to MobileCode.
- `09-mobilecode-preview-from-chrome-share.png` - MobileCode preview after the Chrome share alternate path.
- `10-extra-text-html-share-preview.png` - EXTRA_TEXT HTML share preview.
- `11-no-mime-html-intent-preview.png` - no-MIME `.html` intent preview.

## Provider And Local Model Screenshots

- `12-provider-auto-model-sheet.png` - model sheet showing Provider Auto options without bottom overflow.
- `13-provider-auto-deepseek-auto-state.png` - DeepSeek Auto selected state.
- `14-local-model-manifest-loaded.png` - App-loaded local model manifest with candidate entries.
- `15-local-model-manifest-buttons.png` - model page and manifest buttons for local model candidates.

## Source QA Folders

- `mobile_agent/qa-output/share-assets-20260619-mobilecode-html-open/`
- `mobile_agent/qa-output/html-open-real-app-20260619-204552/`
- `mobile_agent/qa-output/tierflow-deepseek-auto-20260619-201639/`
- `mobile_agent/qa-output/local-model-manifest-20260619-210757/`
