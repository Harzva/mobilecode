# MobileCode CLI Hub

MobileCode CLI Hub is the versioned catalog format for installing and probing
approved command line capabilities inside the MobileCode Linux Sandbox.

The catalog is intentionally declarative:

- Every CLI has an id, command name, official source URL, install strategy,
  required package/profile dependencies, probe task, auth boundary, and safety
  notes.
- App clients must not execute arbitrary install commands from the catalog.
  They map entries to built-in `package_install` profiles or audited typed
  tasks.
- Optional `tasks` entries expose only app-owned typed tasks, such as login
  start, auth status, or read-only probes; they are not shell snippets.
- Credentials, cookies, tokens, `.env` values, and local user paths must never
  be committed to this catalog or emitted in evidence.

Current MobileCode support levels:

- `supported`: App has a typed install/profile route and a probe task.
- `preview`: App can show/install prerequisites, but the real CLI command is
  not yet fully wired.
- `planned`: Catalog entry is documented for later implementation.

This directory can be split into a standalone repository later. The app-facing
contract should remain `catalog/mobilecode-cli-hub.manifest.json`.
