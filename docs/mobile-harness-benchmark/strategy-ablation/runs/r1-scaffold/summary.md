# r1-scaffold Strategy Scaffold

- Run kind: `strategy_scaffold_not_run`
- Counts as experiment: `false`
- Task subset: `smoke-v2` (60 tasks)
- Strategies: react_single_agent, plan_execute_verify_single_agent, supervisor_handoff_multi_agent, swarm_router_multi_agent
- Results: 240 placeholders, all `not_run`

## Evidence Boundary

scaffold_not_run: R1 generated only a task-strategy scaffold. It did not run a model, phone, emulator, verifier, network call, or tool action.

No performance comparison should be inferred from this scaffold.
