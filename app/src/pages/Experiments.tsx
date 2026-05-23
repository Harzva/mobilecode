import {
  ArrowRight,
  Braces,
  CheckCircle2,
  Eye,
  FileCode2,
  GitBranch,
  Hammer,
  RefreshCcw,
  ShieldCheck,
  TriangleAlert,
  Workflow,
} from 'lucide-react';

const implemented = [
  'v0.1.43-last restored the v0.1.39 product UI baseline and kept it as the recovery line.',
  'DeepSeek now has a provider-native tool-calling Agent Loop path; Mimo and unsupported providers keep Single-shot fallback.',
  'ActionRunner executes safe typed tools and ActionEvidence records action name, success, duration, artifact paths, URLs, logs, and recovery hints.',
  'Agent Loop can now inspect and modify a mobile workspace with find_files, grep_files, and bounded apply_patch.',
  'Sub-Agent Lite v2 introduces background read-only Explorer / Reviewer workers with cancellation, timeout, token budget, and a two-worker concurrency cap.',
  'The Virtual Command Layer now covers copy_file, mkdir, delete_file, save_snapshot, and virtual_diff without opening raw shell.',
  'Tools now exposes Activity / Logs, provider tool list, preset permissions, and Android/Linux/macOS command compatibility.',
  'The composer now separates Mode, Model, Task Dispatch, and Input so mobile users can see how a run will execute before sending.',
  'Task Dispatch Center now groups quick generation, Agent validation, repair/review, and command-map prompts without crowding the mobile composer.',
  'Blocked apply_patch observations now return a recovery contract so the model can read context, send a valid unified diff, or use complete write_file for small artifacts.',
];

const missing = [
  'The Agent Loop is still minimal and safety-bounded, not a full autonomous coding runtime.',
  'Rollback restore, project summary, package/build execution, and full visual verification are not implemented yet.',
  'Native bitmap preview screenshots and rich visual verification are not implemented yet.',
  'Sub-Agent Lite v2 is still read-only; background workers can inspect and review, but real writes must return to the main AgentLoop.',
  'A Termux or Helper execution lane is still a future typed task route, not a raw shell exposed to the model.',
];

const safeTools = [
  'list_files',
  'find_files',
  'grep_files',
  'agent_open',
  'agent_eval',
  'agent_close',
  'web_search',
  'fetch_url',
  'write_file',
  'read_file',
  'copy_file',
  'mkdir',
  'delete_file',
  'move_file',
  'save_snapshot',
  'virtual_diff',
  'apply_patch',
  'preview_html',
  'preview_snapshot',
  'report_result',
];
const blockedTools = ['shell', 'rm', 'sudo', 'git push', 'publish', 'remote logs', 'arbitrary command'];

const loop = [
  { title: 'Model intent', text: 'The model expresses what should happen, not a claim that it already happened.' },
  { title: 'Tool call', text: 'A provider-native tool call carries a structured name and arguments.' },
  { title: 'ActionRunner', text: 'MobileCode validates the request and performs only allowed local actions.' },
  { title: 'Evidence', text: 'The result becomes observable facts: paths, URLs, duration, logs, and failure kind.' },
  { title: 'Observation', text: 'The model can continue from the real tool result instead of guessing.' },
  { title: 'Next action', text: 'A loop can repair, preview, report, or stop with an honest final answer.' },
];

const dailyLogs = [
  {
    date: '2026-05-23',
    title: 'Sub-Agent Lite v2 and safer mobile commands',
    points: [
      'Sub-Agent Lite moved from one-run read-only sessions to background read-only workers with cancellation, timeout, token budget, and at most two concurrent lanes.',
      'Explorer and Reviewer workers can inspect, search, collect evidence, and return mailbox observations, but they still cannot write files or run shell.',
      'The main AgentLoop remains the only write lane: write_file, apply_patch, move_file, copy_file, mkdir, and delete_file still pass through ActionRunner, snapshots, evidence, and observation.',
      'MobileCode expanded the Virtual Command Layer with copy_file, mkdir, guarded delete_file, save_snapshot, and virtual_diff so common Unix intentions map to Android-safe typed actions.',
      'The product direction is not “turn Android into Linux.” It is a Mobile Unix Facade: familiar coding workflow for models, strict Android workspace safety underneath.',
      'A future Termux/Helper route can run typed long tasks with taskId, stdout/stderr, evidence, and observation, but it should stay separate from provider-native raw shell.',
      'Task Dispatch Center moved preset work into a product sheet: quick games, complex Agent validation, repair/review, and command-map explanations are now grouped by intent.',
      'When apply_patch is rejected, MobileCode gives the model a compact recovery contract: do not repeat the malformed patch, read the target, retry a valid unified diff, or use complete write_file for small HTML artifacts.',
      'The mobile lesson is that a good phone Agent needs fewer permanent buttons and clearer execution contracts, not just a larger tool list.',
    ],
  },
  {
    date: '2026-05-22',
    title: 'DeepSeek Agent Loop and Mobile Unix Facade',
    points: [
      'DeepSeek is the first provider-native Agent Loop validation line; unsupported providers do not pretend to be Agent Loop.',
      'MobileCode added a visible tool list and command compatibility map so users can see exactly which mobile-safe coding actions are supported.',
      'The Mobile Unix Facade now covers list_files, find_files, grep_files, move_file, and bounded apply_patch while staying inside the app workspace.',
      'Agent Loop uses a visible role flow: Planner inspects, Builder changes, Reviewer verifies, and Repair responds to failed evidence.',
      'Streaming tool-call arguments are shown as one updating progress item with character deltas; actual file writes still happen only after the complete structured tool call is validated.',
      'Invalid patch drafts are now treated as safe blocks rather than product-breaking run failures when an artifact has already been preserved.',
      'Blocked recovery hints now tell the model what failed and which safe next action to try, instead of silently repeating the same malformed patch or missing file path.',
      'Sub-Agent Lite now starts with read-only Explorer / Reviewer sessions: the parent Agent can open a small inspection lane, read its mailbox, and close it without giving the model shell or write access.',
      'Mailbox-lite traces make mobile AgentLoop progress more visible while true background worker agents remain deferred.',
      'The composer is being shaped into four mobile product layers: Mode, Model, Task Dispatch, and Input.',
      'The product direction is a mobile-safe command layer: familiar coding workflow for the model, Android-safe typed tools underneath.',
      'A phone build must also hide unavailable tools: if web relay is not configured, web_search and fetch_url are not offered to the model.',
      'When a model needs to repair existing code, apply_patch records a snapshot and evidence instead of exposing a raw shell command.',
    ],
  },
  {
    date: '2026-05-21',
    title: 'From Single-Shot Generation to Tool-Calling Harness',
    points: [
      'The project clarified that natural language is not an execution protocol.',
      'The honest baseline was single-shot generation with executable evidence.',
      'The next target became model intent -> tool call -> ActionRunner -> evidence -> observation -> next action.',
    ],
  },
];

const providerNativeNotes = [
  {
    title: 'Provider-native means structured action, not text theater',
    text: 'The model provider returns an official tool_call object with a tool name and arguments. MobileCode does not guess intent from a sentence like “I wrote the file.”',
  },
  {
    title: 'MobileCode still decides what is allowed',
    text: 'The App checks path boundaries, preset permissions, sandbox rules, size limits, and runtime availability before ActionRunner executes anything.',
  },
  {
    title: 'Virtual Command Layer is the mobile-safe facade',
    text: 'Unix-like requests such as find, grep, cat, mv, patch, and preview are mapped to typed tools such as find_files, grep_files, read_file, move_file, apply_patch, and preview_html.',
  },
  {
    title: 'Evidence is the truth source',
    text: 'After execution, MobileCode records the real result: success or failure, evidenceId, changed paths, snapshot metadata, logs, and recovery hints.',
  },
];

const deepSeekTuiLessons = [
  {
    title: 'Mobile sandbox first',
    text: 'A phone app cannot behave like an unrestricted desktop terminal. Every file, preview, and network action must stay inside clear app boundaries.',
  },
  {
    title: 'Typed tools before shell',
    text: 'Users should see familiar coding actions such as list, read, write, preview, and move, while MobileCode executes them through safe app-native tools.',
  },
  {
    title: 'Observation over claims',
    text: 'The app should not trust a sentence like “I wrote the file.” It should show the real path, result, preview state, evidence, and recovery hint.',
  },
  {
    title: 'Small agents, clear roles',
    text: 'Builder, Research, Repair, and Reviewer are user-facing work modes. They make the mobile experience understandable without exposing unsafe internals.',
  },
];

export default function Experiments() {
  return (
    <section className="page-section experiment-page">
      <div className="section-container">
        <div className="experiment-hero">
          <div>
            <p className="eyebrow">Experiment Logs / Daily</p>
            <h1>From Single-Shot Generation to Tool-Calling Harness</h1>
            <p>
              MobileCode keeps a public daily engineering log here. The rule is simple: every important
              harness decision should be visible in GitHub Pages, not only hidden in local plans.
            </p>
          </div>
          <div className="experiment-ledger" aria-label="Experiment status">
            <span>Baseline</span>
            <strong>last-recover-from-v039</strong>
            <span>Truth line</span>
            <strong>v0.1.39 UI + DeepSeek Agent Loop</strong>
            <span>Next gate</span>
            <strong>Restore snapshot / project summary / typed Termux tasks</strong>
          </div>
        </div>

        <div className="experiment-callout">
          <ShieldCheck size={22} />
          <p>
            Current version is <strong>a mixed harness</strong>: Single-shot remains the stable default,
            while DeepSeek can use a <strong>minimal provider-native Agent Loop</strong>. The next target
            is a richer typed tool surface without opening raw shell.
          </p>
        </div>

        <article className="experiment-panel">
          <div className="experiment-panel-title">
            <Braces size={24} />
            <div>
              <span>Provider-native tools</span>
              <h2>From “the model said it” to “the app executed it”</h2>
            </div>
          </div>
          <div className="experiment-flow">
            {providerNativeNotes.map((note, index) => (
              <div className="experiment-step" key={note.title}>
                <span>{String(index + 1).padStart(2, '0')}</span>
                <h3>{note.title}</h3>
                <p>{note.text}</p>
              </div>
            ))}
          </div>
        </article>

        <article className="experiment-panel">
          <div className="experiment-panel-title">
            <FileCode2 size={24} />
            <div>
              <span>Daily log</span>
              <h2>Public experiment notes</h2>
            </div>
          </div>
          <div className="experiment-grid">
            {dailyLogs.map((log) => (
              <article className="experiment-card" key={log.date}>
                <h2>{log.date}</h2>
                <h3>{log.title}</h3>
                <ul>
                  {log.points.map((point) => (
                    <li key={point}>{point}</li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </article>

        <div className="experiment-grid">
          <article className="experiment-card">
            <CheckCircle2 size={24} />
            <h2>What is real today</h2>
            <ul>
              {implemented.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>

          <article className="experiment-card warn">
            <TriangleAlert size={24} />
            <h2>What is still missing</h2>
            <ul>
              {missing.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>
        </div>

        <article className="experiment-panel">
          <div className="experiment-panel-title">
            <Workflow size={24} />
            <div>
              <span>Target loop</span>
              <h2>Model intent {'->'} tool call {'->'} ActionRunner {'->'} evidence {'->'} observation {'->'} next action</h2>
            </div>
          </div>
          <div className="experiment-flow">
            {loop.map((step, index) => (
              <div className="experiment-step" key={step.title}>
                <span>{String(index + 1).padStart(2, '0')}</span>
                <h3>{step.title}</h3>
                <p>{step.text}</p>
              </div>
            ))}
          </div>
        </article>

        <article className="experiment-panel">
          <div className="experiment-panel-title">
            <GitBranch size={24} />
            <div>
              <span>Mobile challenge</span>
              <h2>Building an agent on a phone is not the same as wrapping a desktop shell</h2>
            </div>
          </div>
          <div className="experiment-flow">
            {deepSeekTuiLessons.map((lesson, index) => (
              <div className="experiment-step" key={lesson.title}>
                <span>{String(index + 1).padStart(2, '0')}</span>
                <h3>{lesson.title}</h3>
                <p>{lesson.text}</p>
              </div>
            ))}
          </div>
        </article>

        <div className="experiment-split">
          <article className="experiment-card">
            <Braces size={24} />
            <h2>Provider-native tool call</h2>
            <p>
              Instead of placing a tool list only in natural-language prompts, MobileCode should pass
              structured tools to providers that support OpenAI tools or Anthropic tool_use.
            </p>
            <pre className="experiment-code">{`{
  "name": "write_file",
  "arguments": {
    "path": "snake_game/index.html",
    "content": "<!DOCTYPE html>..."
  }
}`}</pre>
          </article>

          <article className="experiment-card">
            <Hammer size={24} />
            <h2>Safe first tool surface</h2>
            <div className="experiment-pill-row">
              {safeTools.map((tool) => (
                <span className="ok" key={tool}>{tool}</span>
              ))}
            </div>
            <h3>Not in the first pass</h3>
            <div className="experiment-pill-row">
              {blockedTools.map((tool) => (
                <span className="blocked" key={tool}>{tool}</span>
              ))}
            </div>
          </article>
        </div>

        <article className="experiment-panel">
          <div className="experiment-panel-title">
            <GitBranch size={24} />
            <div>
              <span>Engineering lesson</span>
              <h2>Natural language is not an execution protocol</h2>
            </div>
          </div>
          <p>
            A model saying “I wrote the file” is not the same as a phone app writing the file. The durable
            boundary is: the model requests an action, MobileCode validates and executes it, and evidence
            records the result. This is the difference between a chat shell and a harness.
          </p>
          <div className="experiment-quotes">
            <blockquote>模型表达意图，App 执行动作，Evidence 记录事实。</blockquote>
            <blockquote>当前版本是 single-shot generation with executable evidence。</blockquote>
            <blockquote>下一阶段目标是 multi-step tool-calling agent loop。</blockquote>
          </div>
        </article>

        <div className="experiment-next">
          <div>
            <FileCode2 size={22} />
            <strong>H07</strong>
            <span>JSON action fallback for providers without native tool calls.</span>
          </div>
          <ArrowRight size={18} />
          <div>
            <Eye size={22} />
            <strong>H08</strong>
            <span>Provider ToolCallAdapter for OpenAI tools and Anthropic tool_use.</span>
          </div>
          <ArrowRight size={18} />
          <div>
            <RefreshCcw size={22} />
            <strong>H15</strong>
            <span>Failure evidence becomes repair proposal, user review, and retry.</span>
          </div>
        </div>
      </div>
    </section>
  );
}
