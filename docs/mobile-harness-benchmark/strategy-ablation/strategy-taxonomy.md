# Mobile Harness Strategy Taxonomy

This taxonomy defines the R1 strategy choices for MobileHarnessBench. It is
designed for scaffold and dry-run comparison first; it is not a claim that any
strategy is currently better.

## Strategy Families

| Family | Purpose | MobileCode fit | Primary risk |
| --- | --- | --- | --- |
| `single_agent_reasoning` | One agent owns planning, action, and reporting. | Lowest overhead for short mobile tasks. | Weak separation between action and verification. |
| `single_agent_with_verifier` | One actor plus an explicit final verifier. | Good bridge from current `AgentLoopController` to PEV. | Verifier can be too late if earlier steps drift. |
| `multi_agent_handoff` | Supervisor routes work to specialized roles. | Matches mobile-specific roles: code, runtime, preview, GitHub, memory. | Handoff context can leak noise or lose key constraints. |
| `multi_agent_swarm` | Router or hierarchy distributes tasks across worker pools. | Useful for larger future task batches and long workflows. | More overhead, more traces, harder mobile evidence accounting. |

## R1 Strategies

### `react_single_agent`

One agent alternates compact thought, one action, and one observation. It maps
well to current tool-loop behavior and is the lowest-friction control strategy.

- Loop: `think -> act -> observe`.
- Memory: reads one compact `HarnessMemoryPacket`.
- Verification: final task status only.
- Best for: short file-intake and code-edit tasks.

### `plan_execute_verify_single_agent`

One agent creates a small plan, executes one step at a time, and verifies each
step before continuing. This is the default bridge to MobileCode v1.

- Loop: `plan -> execute step -> verify -> retry or continue`.
- Memory: reads one compact packet and appends strategy trace events.
- Verification: `StepVerification` per step.
- Best for: tasks where preview/runtime evidence matters.

### `react_with_final_verifier`

One ReAct actor completes the task, then a separate verifier role checks the
final artifact and trace. It is a small step toward role separation without full
handoff orchestration.

- Loop: `react actor -> final verifier -> report`.
- Memory: actor receives goal packet; verifier receives trace summary only.
- Verification: final verifier contract.
- Best for: fast experiments that need a second-pass guard.

### `supervisor_handoff_multi_agent`

A Supervisor owns the plan and creates `HandoffPacket` work orders for
specialists. Each specialist returns compact evidence and blockers.

- Loop: `supervisor plan -> handoff -> specialist ReAct -> verify -> report`.
- Memory: role-specific filtering; no raw transcript handoff by default.
- Verification: per-step plus final report.
- Best for: mobile runtime fallback, preview QA, GitHub delivery, and memory
  updates.

### `swarm_router_multi_agent`

A router selects between specialist swarms based on task characteristics, device
profile, and load. R1 only defines this as a future comparison strategy.

- Loop: `router -> selected swarm -> judge -> report`.
- Memory: task packet plus swarm-local trace.
- Verification: judge/verifier role.
- Best for: large task queues after the benchmark runner matures.

### `hierarchical_swarm_multi_agent`

A manager decomposes a task and delegates to worker agents in a hierarchy. It is
the heaviest R1 strategy and should be kept out of early counted pilots.

- Loop: `manager plan -> worker tasks -> judge -> manager report`.
- Memory: manager packet; workers receive filtered subtasks.
- Verification: judge plus manager reconciliation.
- Best for: long future workflows with multiple independent artifacts.

## Mobile-Specific Dimensions

Every strategy comparison must lock or record:

- Device tier: emulator, real Android phone, iOS simulator, or iOS device.
- Runtime backend: WebView, MobileCode Helper, external Termux bridge, cloud, or
  local model runtime.
- File intake mode: app-owned file, content URI, share intent, downloaded HTML,
  or generated artifact.
- Preview mode: WebView, browser, screenshot capture, DOM probe, or no preview.
- Evidence mode: action evidence only, strategy trace, screenshots, verifier
  output, and run summary.

## Promotion Rule

R1 strategies can move from scaffold to counted results only when the run has a
locked model, locked task subset, locked device/runtime tier, real trace
artifacts, verifier output, and evidence that can be independently inspected.
