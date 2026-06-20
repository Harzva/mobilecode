#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import re
import subprocess
from pathlib import Path


OWNER_REPO = os.environ.get("GITHUB_REPOSITORY", "Harzva/mobilecode")
REPO_URL = f"https://github.com/{OWNER_REPO}"
ZERO_SHA = "0" * 40

IMPORTANT_SUBJECT = re.compile(
    r"\b(add|auto|ci|deploy|evidence|feat|fix|manifest|model|pages|provider|qa|release|route|routing|smoke|workflow)\b",
    re.IGNORECASE,
)

IMPORTANT_PATH_PREFIXES = (
    ".github/workflows/",
    "app/src/",
    "docs/mobilecode-local-models.json",
    "docs/mobilecode-update.json",
    "mobile_agent/lib/",
    "mobile_agent/test/",
    "scripts/",
)


def run(command: list[str], *, cwd: Path, check: bool = True) -> str:
    try:
        return subprocess.check_output(
            command,
            cwd=cwd,
            stderr=subprocess.STDOUT,
            text=True,
        ).strip()
    except subprocess.CalledProcessError as exc:
        if check:
            raise SystemExit(exc.output.strip() or str(exc)) from exc
        return ""


def git(repo: Path, *args: str, check: bool = True) -> str:
    return run(["git", *args], cwd=repo, check=check)


def valid_commit(repo: Path, sha: str | None) -> bool:
    if not sha or sha == ZERO_SHA:
        return False
    return bool(git(repo, "cat-file", "-e", f"{sha}^{{commit}}", check=False) == "")


def collect_commits(repo: Path, base: str | None, head: str, since: str) -> list[dict[str, str]]:
    pretty = "%H%x1f%h%x1f%ad%x1f%an%x1f%s"
    args = ["log", f"--pretty=format:{pretty}", "--date=short"]
    if base:
        args.append(f"{base}..{head}")
    else:
        args.extend([head, f"--since={since}"])
    raw = git(repo, *args, check=False)
    if not raw and base:
        return []
    if not raw:
        raw = git(repo, f"--pretty=format:{pretty}", "--date=short", "-n", "1", head)
    commits = []
    for line in raw.splitlines():
        parts = line.split("\x1f")
        if len(parts) == 5:
            full, short, date, author, subject = parts
            commits.append(
                {
                    "full": full,
                    "short": short,
                    "date": date,
                    "author": author,
                    "subject": subject,
                }
            )
    return commits


def changed_files(repo: Path, base: str | None, head: str, commits: list[dict[str, str]]) -> list[str]:
    if base:
        raw = git(repo, "diff", "--name-only", f"{base}..{head}", check=False)
    else:
        files: set[str] = set()
        for commit in commits:
            raw_show = git(repo, "show", "--name-only", "--pretty=format:", commit["full"], check=False)
            files.update(line for line in raw_show.splitlines() if line.strip())
        return sorted(files)
    return sorted(line for line in raw.splitlines() if line.strip())


def classify(path: str) -> str:
    if path.startswith(".github/workflows/"):
        return "GitHub Actions"
    if path.startswith("mobile_agent/"):
        return "Mobile app"
    if path.startswith("app/"):
        return "Pages site"
    if path.startswith("docs/mobile-harness"):
        return "Mobile Harness"
    if path.startswith("docs/"):
        return "Docs"
    if path.startswith("scripts/"):
        return "Automation"
    if path.startswith("relay/"):
        return "Relay"
    return "Repository"


def summarize_areas(files: list[str]) -> dict[str, int]:
    areas: dict[str, int] = {}
    for path in files:
        area = classify(path)
        areas[area] = areas.get(area, 0) + 1
    return dict(sorted(areas.items(), key=lambda item: (-item[1], item[0])))


def has_important_changes(commits: list[dict[str, str]], files: list[str], force: bool) -> bool:
    if force:
        return True
    if any(IMPORTANT_SUBJECT.search(commit["subject"]) for commit in commits):
        return True
    return any(path.startswith(IMPORTANT_PATH_PREFIXES) for path in files)


def write_markdown(
    path: Path,
    *,
    log_type: str,
    title: str,
    date: str,
    generated_at: str,
    base: str | None,
    head: str,
    head_short: str,
    commits: list[dict[str, str]],
    files: list[str],
    areas: dict[str, int],
) -> None:
    commit_lines = "\n".join(
        f"- [`{commit['short']}`]({REPO_URL}/commit/{commit['full']}) {commit['subject']}"
        for commit in commits
    )
    area_lines = "\n".join(f"- {area}: {count} file(s)" for area, count in areas.items()) or "- No changed files detected."
    file_lines = "\n".join(f"- `{item}`" for item in files[:40]) or "- No changed files detected."
    if len(files) > 40:
        file_lines += f"\n- ... {len(files) - 40} more file(s)"
    compare = f"{base[:12]}..{head_short}" if base else f"last {len(commits)} commit(s)"
    compare_link = f"{REPO_URL}/compare/{base}...{head}" if base else f"{REPO_URL}/commit/{head}"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            [
                "---",
                f'title: "{title}"',
                f"type: {log_type}",
                f"date: {date}",
                f"generatedAt: {generated_at}",
                f"head: {head}",
                "---",
                "",
                f"# {title}",
                "",
                f"- Generated at: `{generated_at}`",
                f"- Head: [`{head_short}`]({REPO_URL}/commit/{head})",
                f"- Window: [{compare}]({compare_link})",
                f"- Commit count: {len(commits)}",
                f"- Changed files: {len(files)}",
                "",
                "## Changed Areas",
                "",
                area_lines,
                "",
                "## Commits",
                "",
                commit_lines or "- No commits detected.",
                "",
                "## Changed Files",
                "",
                file_lines,
                "",
            ]
        ),
        encoding="utf-8",
    )


def parse_frontmatter(path: Path, root: Path) -> dict[str, str] | None:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    data: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    data["path"] = path.relative_to(root).as_posix()
    return data


def screenshot_metadata(devlog_dir: Path) -> dict[str, str] | None:
    latest = devlog_dir / "screenshots" / "latest.png"
    if not latest.exists():
        return None
    preferred = os.environ.get("MOBILECODE_DEVLOG_CURRENT_SCREENSHOT")
    current = latest
    if preferred:
        candidate = Path(preferred)
        if not candidate.is_absolute():
            candidate = devlog_dir / candidate
        if candidate.exists():
            current = candidate
    else:
        screenshots = [
            path
            for path in (devlog_dir / "screenshots").glob("*.png")
            if path.name != "latest.png"
        ]
        if screenshots:
            current = max(screenshots, key=lambda path: (path.stat().st_mtime_ns, path.name))
    return {
        "latest": latest.relative_to(devlog_dir).as_posix(),
        "current": current.relative_to(devlog_dir).as_posix(),
        "currentName": current.name,
    }


def build_index(root: Path, devlog_dir: Path, generated_at: str) -> None:
    entries = []
    for path in sorted(devlog_dir.glob("*/*.md")):
        meta = parse_frontmatter(path, root)
        if meta:
            entries.append(meta)
    entries.sort(key=lambda item: (item.get("date", ""), item.get("generatedAt", "")), reverse=True)
    feed = {
        "schemaVersion": 1,
        "generatedAt": generated_at,
        "repository": OWNER_REPO,
        "entries": entries,
    }
    screenshot = screenshot_metadata(devlog_dir)
    if screenshot:
        feed["latestScreenshot"] = screenshot
    (devlog_dir / "index.json").write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    cards = []
    for entry in entries[:40]:
        rel = html.escape(entry["path"].replace("docs/devlog/", ""))
        title = html.escape(entry.get("title", rel))
        kind = html.escape(entry.get("type", "log"))
        date = html.escape(entry.get("date", ""))
        head = html.escape(entry.get("head", "")[:12])
        cards.append(
            f"""
      <a class="entry" href="./{rel}">
        <span>{kind}</span>
        <strong>{title}</strong>
        <small>{date} · {head}</small>
      </a>"""
        )
    cards_html = "\n".join(cards) or "<p>No developer logs yet.</p>"
    screenshot_html = ""
    if screenshot:
        latest_src = html.escape(screenshot["latest"])
        current_name = html.escape(screenshot["currentName"])
        screenshot_html = f"""
    <section class="screenshot">
      <div>
        <span>Latest screenshot</span>
        <strong>{current_name}</strong>
      </div>
      <a href="./{latest_src}">
        <img src="./{latest_src}" alt="Latest MobileCode developer log page screenshot">
      </a>
    </section>"""
    (devlog_dir / "index.html").write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MobileCode Developer Logs</title>
  <style>
    :root {{ color-scheme: dark; --bg: #05070c; --panel: #101827; --line: #263449; --text: #f8fafc; --muted: #9fb1c7; --mint: #73f3d0; --cyan: #27d7e6; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; min-height: 100vh; background: var(--bg); color: var(--text); font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    main {{ width: min(980px, calc(100% - 32px)); margin: 0 auto; padding: 48px 0; }}
    h1 {{ margin: 0; font-size: clamp(36px, 8vw, 72px); line-height: 0.95; letter-spacing: 0; }}
    p {{ color: var(--muted); line-height: 1.55; }}
    .top {{ display: grid; gap: 16px; margin-bottom: 28px; }}
    .meta {{ display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8px; }}
    .meta span, .entry span {{ border: 1px solid rgba(115, 243, 208, .38); color: var(--mint); border-radius: 8px; padding: 6px 9px; font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: .08em; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }}
    .entry {{ display: grid; gap: 12px; min-height: 160px; padding: 18px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); text-decoration: none; color: inherit; }}
    .entry:hover {{ border-color: var(--cyan); transform: translateY(-2px); transition: 160ms ease; }}
    .entry strong {{ font-size: 20px; line-height: 1.18; }}
    .entry small {{ color: var(--muted); }}
    .screenshot {{ margin: 30px 0; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); overflow: hidden; }}
    .screenshot div {{ display: flex; justify-content: space-between; gap: 12px; padding: 14px 16px; color: var(--muted); }}
    .screenshot span {{ color: var(--mint); font-weight: 900; text-transform: uppercase; letter-spacing: .08em; font-size: 12px; }}
    .screenshot img {{ display: block; width: 100%; height: auto; border-top: 1px solid var(--line); }}
    .links {{ display: flex; flex-wrap: wrap; gap: 12px; margin-top: 26px; }}
    .links a {{ color: var(--mint); font-weight: 800; }}
  </style>
</head>
<body>
  <main>
    <section class="top">
      <div class="meta"><span>MobileCode</span><span>Developer Logs</span></div>
      <h1>Daily and important engineering changes.</h1>
      <p>These logs are generated from Git history by the MobileCode repository hook, then published to GitHub Pages.</p>
      <p>Last generated: <code>{html.escape(generated_at)}</code></p>
    </section>
{screenshot_html}
    <section class="grid">
{cards_html}
    </section>
    <section class="links">
      <a href="./index.json">JSON feed</a>
      <a href="{html.escape(REPO_URL)}">GitHub repository</a>
      <a href="../">MobileCode Pages</a>
    </section>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate MobileCode developer logs from git history.")
    parser.add_argument("--mode", choices=["daily", "important", "both", "auto", "index"], default="auto")
    parser.add_argument("--base", default=os.environ.get("GITHUB_EVENT_BEFORE"))
    parser.add_argument("--head", default=os.environ.get("GITHUB_SHA", "HEAD"))
    parser.add_argument("--since", default="24 hours ago")
    parser.add_argument("--date", default=dt.datetime.now(dt.timezone.utc).date().isoformat())
    parser.add_argument("--force-important", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    devlog_dir = repo / "docs" / "devlog"
    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    head = git(repo, "rev-parse", args.head)
    head_short = git(repo, "rev-parse", "--short", head)
    base = args.base if valid_commit(repo, args.base) else None
    commits = collect_commits(repo, base, head, args.since)
    files = changed_files(repo, base, head, commits)
    areas = summarize_areas(files)
    wrote_log = False

    mode = args.mode
    if mode == "index":
        build_index(repo, devlog_dir, generated_at)
        print(f"Rebuilt developer log index in {devlog_dir.relative_to(repo)}")
        return 0
    if mode == "auto":
        mode = "daily" if os.environ.get("GITHUB_EVENT_NAME") == "schedule" else "important"

    if mode in {"daily", "both"}:
        write_markdown(
            devlog_dir / "daily" / f"{args.date}.md",
            log_type="daily",
            title=f"Daily Devlog - {args.date}",
            date=args.date,
            generated_at=generated_at,
            base=base,
            head=head,
            head_short=head_short,
            commits=commits,
            files=files,
            areas=areas,
        )
        wrote_log = True

    if mode in {"important", "both"} and has_important_changes(commits, files, args.force_important):
        write_markdown(
            devlog_dir / "important" / f"{args.date}-{head_short}.md",
            log_type="important",
            title=f"Important Changes - {args.date} - {head_short}",
            date=args.date,
            generated_at=generated_at,
            base=base,
            head=head,
            head_short=head_short,
            commits=commits,
            files=files,
            areas=areas,
        )
        wrote_log = True

    if wrote_log:
        build_index(repo, devlog_dir, generated_at)
        print(f"Generated developer logs in {devlog_dir.relative_to(repo)}")
    else:
        print("No developer log changes matched the selected mode.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
