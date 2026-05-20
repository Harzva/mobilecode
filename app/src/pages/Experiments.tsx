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
  'v0.1.43-last restores the v0.1.39 product UI baseline.',
  'ActionRunner now executes writeFile, readFile, and previewHtml.',
  'ActionEvidence records action name, success, duration, artifact paths, URLs, logs, and recovery hints.',
  'Tools -> Activity / Logs reads recent and failed evidence without search, remote logging, or new execution paths.',
];

const missing = [
  'The model still usually returns one complete answer, and the app extracts/saves the artifact.',
  'The model does not yet choose tools through provider-native tool calls.',
  'Tool results are not yet fed back into a multi-step observation loop.',
  'Failure evidence does not yet trigger model reflection, repair actions, and reviewed retry.',
];

const safeTools = ['write_file', 'read_file', 'preview_html', 'report_result'];
const blockedTools = ['shell', 'git push', 'publish', 'remote logs', 'arbitrary command'];

const loop = [
  { title: 'Model intent', text: 'The model expresses what should happen, not a claim that it already happened.' },
  { title: 'Tool call', text: 'A provider-native tool call carries a structured name and arguments.' },
  { title: 'ActionRunner', text: 'MobileCode validates the request and performs only allowed local actions.' },
  { title: 'Evidence', text: 'The result becomes observable facts: paths, URLs, duration, logs, and failure kind.' },
  { title: 'Observation', text: 'The model can continue from the real tool result instead of guessing.' },
  { title: 'Next action', text: 'A loop can repair, preview, report, or stop with an honest final answer.' },
];

export default function Experiments() {
  return (
    <section className="page-section experiment-page">
      <div className="section-container">
        <div className="experiment-hero">
          <div>
            <p className="eyebrow">Experiment Log / 2026-05-21</p>
            <h1>From Single-Shot Generation to Tool-Calling Harness</h1>
            <p>
              This note records a turning point in MobileCode: the project now has executable evidence,
              but it should not be described as a complete provider-native tool-calling agent yet.
            </p>
          </div>
          <div className="experiment-ledger" aria-label="Experiment status">
            <span>Baseline</span>
            <strong>v0.1.43-last</strong>
            <span>Truth line</span>
            <strong>v0.1.39 UI + ActionRunner evidence</strong>
            <span>Next gate</span>
            <strong>ToolCallAdapter</strong>
          </div>
        </div>

        <div className="experiment-callout">
          <ShieldCheck size={22} />
          <p>
            Current version is <strong>single-shot generation with executable evidence</strong>. The next
            engineering target is a <strong>multi-step tool-calling agent loop</strong>.
          </p>
        </div>

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

        <div className="experiment-split">
          <article className="experiment-card">
            <Braces size={24} />
            <h2>Minimal provider-native tool call</h2>
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
