# p4c-callback-pilot P4c Callback Pilot

- Run kind: `strategy_pilot_not_counted`
- Counts as experiment: `false`
- Task subset: `smoke-v2` (4 tasks)
- Strategies: react_single_agent, plan_execute_verify_single_agent, supervisor_handoff_multi_agent
- Results: 12 fake callback pilot rows, all `warning` and non-counted

## Evidence Boundary

pilot_not_counted: P4c generated deterministic fake callback traces and metrics only. No real model, provider API, mobile device, network, tool action, screenshot, or verifier execution was performed. These artifacts are validator-compatible pilot scaffolds, not benchmark results.

No strategy ranking or benchmark claim should be inferred from this pilot artifact.
