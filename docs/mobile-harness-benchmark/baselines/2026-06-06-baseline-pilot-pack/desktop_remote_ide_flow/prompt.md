# Baseline Pilot Prompt: desktop_remote_ide_flow

Status: `pilot_ready_no_results`
Counts as baseline result: `false`

## Baseline

- Name: Desktop remote IDE flow
- Unit under test: A conventional desktop or remote IDE workflow used from outside the phone.
- Expected limit: Strong execution access, but not a phone-native control-plane baseline.

## Task

- Task id: `MH-CE-209`
- Category: `code_edit`
- Title: Edit HTML artifact prompt workspace_import happy_path ios_simulator_document
- Fixture: `fixtures/code-edit/html-prompt.txt`

## User Goal

Complete a code-edit workflow on HTML artifact prompt from a MobileCode workspace import and export verifier evidence. The success path must complete without manual recovery. Target mobile profile: ios_simulator_document via iOS document picker on ios_simulator.

## Allowed Tools

- desktop IDE or remote editor
- terminal or CI logs
- repository commit tools

## Expected Artifacts

- index.html
- preview_route

## Verifiers

- artifact_exists_verifier
- html_preview_verifier

## Evidence To Capture

- diff or commit record
- test or preview output
- run logs
- human intervention count
- exact model/provider lock
- full prompt transcript
- artifact paths or explicit blocked output
- verifier outputs or reason verifier could not run
- human intervention rows using `human-intervention-sheet.csv`

## Blocked Conditions

- workspace unavailable
- missing model/provider lock
- missing transcript
- missing artifact or blocked-output explanation
- missing human-intervention annotation

## Counting Rule

Do not set `counts_as_baseline_result=true` until this prompt is executed with a filled model lock, transcript, artifacts or blocked-output evidence, verifier outputs, and human-intervention annotations.
