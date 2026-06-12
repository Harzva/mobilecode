import {
  ArrowRight,
  Boxes,
  CheckCircle2,
  Code2,
  FileSearch,
  GitBranch,
  Layers3,
  PackageCheck,
  Route,
  ShieldCheck,
  Smartphone,
  TerminalSquare,
  TriangleAlert,
  Workflow,
  Wrench,
  Cpu,
  GalleryHorizontalEnd,
} from 'lucide-react';

const architectureLayers = [
  {
    title: 'HomeScreen + Drawer',
    label: '一级主壳层',
    text: '左上角三横线是全局侧边栏，用于会话、入口和主功能跳转，不承担返回语义。',
  },
  {
    title: 'Chat / Tools / Settings',
    label: '二级主功能区',
    text: '_HomeTab 保留 control / ai / ship / guard / insight 五个逻辑区，实际收敛到三个主页面，切换不显示返回箭头。',
  },
  {
    title: 'Bottom Sheet Panels',
    label: '三级临时面板',
    text: '任务派发中心、Runtime、Build、Tool Lab 等是临时工作面板，使用明确关闭按钮，而不是路由返回箭头。',
  },
  {
    title: 'Navigator.push Routes',
    label: '四级独立页面',
    text: 'Editor、GitHub Repo Hub、API Usage 等完整页面使用左上返回箭头，语义是回到上一个路由。',
  },
];

const solvedProblems = [
  {
    title: '把“模型说完成了”变成“App 真的执行了”',
    text: 'Provider-native tool call 进入 ActionRunner，路径、权限、大小、风险先校验，再写入 ActionEvidence。',
    icon: CheckCircle2,
  },
  {
    title: '移动端不能假装是 Linux 终端',
    text: 'Virtual Command Layer 将 list/read/write/patch/preview 等习惯映射为 Android-safe typed tools，raw shell 默认关闭。',
    icon: TerminalSquare,
  },
  {
    title: 'Helper/Termux 任务必须可观察',
    text: 'typed task 返回 taskId、stdout/stderr、exitCode、failureKind、task history 和恢复建议，UI 可以停止、刷新、复制摘要。',
    icon: FileSearch,
  },
  {
    title: '预览证据不能夸大',
    text: 'preview_snapshot 明确标记 metadata_captured / captureMode=metadata / bitmapCaptured=false，除非真有图片 artifact，否则不声称截图。',
    icon: ShieldCheck,
  },
  {
    title: '一次 GitHub build 产出双端 app',
    text: 'Build Mobile Apps workflow 同时产出 Android APK、iOS simulator app zip 和 unsigned iOS archive，并挂到同一个 Release。',
    icon: PackageCheck,
  },
  {
    title: '移动端返回逻辑要有层级纪律',
    text: '主壳用 Drawer，主功能区用 tab/工作区切换，临时面板用关闭按钮，完整页面路由用返回箭头。',
    icon: Route,
  },
];

const hardProblems = [
  {
    title: '手机端 Agent Loop 的执行可信度',
    text: '难点不是让模型多说几句，而是让每一步都有可验证的 action、evidence、observation 和 recovery contract。',
  },
  {
    title: 'Helper/Termux 与 App 沙箱之间的边界',
    text: '需要给模型 typed task 能力，又不能把 raw shell、任意 git push、安装脚本和远程日志上传暴露为默认能力。',
  },
  {
    title: '预览验证从 metadata 走向视觉证据',
    text: '当前 metadata/DOM/viewport 已经诚实记录；下一步是稳定生产真实 bitmap artifact，再做 screenshot-grade validation。',
  },
  {
    title: 'Sub-Agent Lite 的读写边界',
    text: 'Explorer/Reviewer 可以后台只读扫描和总结；真正写入必须回到主 AgentLoop，通过 ActionRunner 统一应用。',
  },
  {
    title: 'Lark 是 Agent-facing API，不是 CLI 外壳',
    text: '手机端要暴露 Docx、Sheets、Base、Wiki 等 typed actions；CLI/MCP 只作为 Mac、CI 或 relay 侧的验证参考。',
  },
  {
    title: '移动端信息架构密度',
    text: 'Chat、Tools、Settings、Drawer、bottom sheets 和 pushed routes 必须有统一导航语义，避免用户不知道自己在哪一层。',
  },
];

const methods = [
  'Evidence-first：每个高层能力都要能指向 artifact、run、release asset、log 或 ActionEvidence。',
  'Typed tools over shell：把 Unix-like 意图收敛成 typed tool，而不是开放 exec_shell。',
  'Agent-facing Lark：模型只能调用固定 Lark OpenAPI action，写入必须先 preview，再由用户确认。',
  'Fail closed：缺依赖、越界路径、raw command、超时和 runtime lost 都产出 failureKind 与恢复建议。',
  'GitHub-first builds：本地 Flutter 不可用时，不反复卡死；用 GitHub Actions 作为权威构建环境。',
  'Navigation contract：侧边栏、主功能区、临时面板、独立页面四层分工固定，减少移动端迷路。',
  'Release honesty：未实现就是 planned，metadata 就是 metadata，unsigned archive 不包装成 signed IPA。',
];

const galleryPatterns = [
  {
    title: 'Task Gallery',
    text: '把功能入口升级为带 category、surface、runtime、permission 和 verifier 的 task metadata。',
    icon: GalleryHorizontalEnd,
  },
  {
    title: 'Skill Package',
    text: '用 SKILL.md、scripts/index.html、permission tokens 和 verifier contract 描述可审阅能力。',
    icon: Code2,
  },
  {
    title: 'Tool Bridge',
    text: 'MCP/Runtime/GitHub/WebView/Lark 统一进入 typed tool bridge，每次调用都能产出 evidence。',
    icon: Workflow,
  },
  {
    title: 'Benchmark Surface',
    text: 'MobileHarnessBench 从文档进入 App 内 Benchmark Lab，但真实 mobile evidence 仍单独计数。',
    icon: Cpu,
  },
];

const productNarrative = [
  {
    title: '产品展示',
    text: 'README 与 Pages 只展示 phone-native coding harness、产品预览图、walkthrough 和公开 release，不暴露内部工作线。',
    icon: Smartphone,
  },
  {
    title: '研究方向',
    text: 'Mobile Harness 论文、PhoneWorld 分析和长期 roadmp 共同说明：手机 Agent 的核心资产是可控环境、任务、验证器和轨迹。',
    icon: FileSearch,
  },
  {
    title: 'Benchmark 证据',
    text: 'MobileHarnessBench 明确区分 T0 fixture、移动端证据、baseline readiness 和 submission gate，避免把准备工作写成实验结果。',
    icon: Cpu,
  },
  {
    title: '双端构建',
    text: '正式 release 由 GitHub Actions 产出 Android APK、iOS simulator app zip 和 unsigned archive，构建证据统一指向 main。',
    icon: PackageCheck,
  },
];

const releaseAssets = [
  {
    label: 'Android APK',
    href: 'https://github.com/Harzva/mobilecode/releases/download/v0.1.68-mobile-harness-d2dd9a7/mobilecode-v0.1.68-mobile-harness-d2dd9a7.apk',
  },
  {
    label: 'iOS simulator app',
    href: 'https://github.com/Harzva/mobilecode/releases/download/v0.1.68-mobile-harness-d2dd9a7/mobilecode-ios-simulator-v0.1.68-mobile-harness-d2dd9a7.zip',
  },
  {
    label: 'iOS unsigned archive',
    href: 'https://github.com/Harzva/mobilecode/releases/download/v0.1.68-mobile-harness-d2dd9a7/mobilecode-ios-archive-v0.1.68-mobile-harness-d2dd9a7.xcarchive.zip',
  },
  {
    label: 'Build Mobile Apps run',
    href: 'https://github.com/Harzva/mobilecode/actions/runs/27287231941',
  },
  {
    label: 'Source branch',
    href: 'https://github.com/Harzva/mobilecode/tree/main',
  },
];

export default function Developer() {
  return (
    <section className="page-section developer-page">
      <div className="section-container">
        <div className="developer-hero">
          <div>
            <p className="eyebrow">Developer Page</p>
            <h1>MobileCode 工程实现与攻坚记录</h1>
            <p>
              这不是一个把网页套进手机的远程 IDE 外壳。MobileCode 的工程目标是把模型意图、
              手机工作区、typed tools、RuntimeProvider、ActionEvidence 和 GitHub 发布链路组织成可验证闭环。
            </p>
          </div>
          <div className="developer-proof">
            <span>Current release</span>
            <strong>v0.1.68-mobile-harness</strong>
            <span>Verified build</span>
            <strong>APK + iOS artifacts</strong>
            <span>Default branch</span>
            <strong>main</strong>
            <span>Public surface</span>
            <strong>GitHub Pages</strong>
          </div>
        </div>

        <div className="developer-callout">
          <Smartphone size={22} />
          <p>
            当前重点：让移动端 Agent 的每个动作都可执行、可观察、可恢复。我们已经解决双端构建、
            Helper 任务可见性、metadata-only 预览诚实表达和临时面板返回问题；下一步继续攻克真实截图级预览和更稳定的后台只读 worker。
          </p>
        </div>

        <section className="developer-section">
          <div className="section-heading compact">
            <p className="eyebrow">Public Narrative</p>
            <h2>四条公开主线</h2>
            <p>公开页面统一围绕产品、研究、benchmark 证据和双端构建，不再使用内部恢复分支叙事。</p>
          </div>
          <div className="solved-grid">
            {productNarrative.map(({ title, text, icon: Icon }) => (
              <article key={title} className="solved-card">
                <Icon size={22} />
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="developer-section">
          <div className="section-heading compact">
            <p className="eyebrow">Navigation Contract</p>
            <h2>四级导航语义</h2>
            <p>用户反馈“没有返回按钮”暴露的是层级语义问题：不同 UI 层级必须使用不同的退出方式。</p>
          </div>
          <div className="layer-grid">
            {architectureLayers.map((item, index) => (
              <article key={item.title} className="layer-card">
                <span>{String(index + 1).padStart(2, '0')}</span>
                <small>{item.label}</small>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="developer-section">
          <div className="section-heading compact">
            <p className="eyebrow">Solved Problems</p>
            <h2>已经攻克的工程难点</h2>
          </div>
          <div className="solved-grid">
            {solvedProblems.map(({ title, text, icon: Icon }) => (
              <article key={title} className="solved-card">
                <Icon size={22} />
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="developer-split">
          <article>
            <div className="developer-panel-title">
              <TriangleAlert size={22} />
              <h2>正在攻克的难点</h2>
            </div>
            <div className="challenge-list">
              {hardProblems.map((item) => (
                <div key={item.title}>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                </div>
              ))}
            </div>
          </article>

          <article>
            <div className="developer-panel-title">
              <Wrench size={22} />
              <h2>采用的方法</h2>
            </div>
            <ul className="method-list">
              {methods.map((method) => (
                <li key={method}>
                  <CheckCircle2 size={17} />
                  <span>{method}</span>
                </li>
              ))}
            </ul>
          </article>
        </section>

        <section className="developer-section gallery-patterns">
          <div className="section-heading compact">
            <p className="eyebrow">Inspired by On-device AI Gallery Patterns</p>
            <h2>从模型展示走向 Harness 产品面</h2>
            <p>
              On-device AI 应用正在从单一聊天演示，走向 task gallery、skill package、tool bridge、runtime management
              和 benchmark surface。MobileCode 吸收这个产品形态，但把目标换成手机端 AI coding harness：文件入口、代码 artifact、
              HTML/Markdown 预览、GitHub 交付、运行时路由和 verifier evidence。
            </p>
          </div>
          <div className="gallery-pattern-grid">
            {galleryPatterns.map(({ title, text, icon: Icon }) => (
              <article key={title}>
                <Icon size={22} />
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
          <div className="gallery-pattern-links">
            <a href="https://github.com/google-ai-edge/gallery" target="_blank" rel="noreferrer">
              <span>Reference pattern</span>
              <strong>google-ai-edge/gallery</strong>
              <ArrowRight size={16} />
            </a>
            <a href="https://harzva.github.io/mobilecode/#/developer" target="_blank" rel="noreferrer">
              <span>MobileCode direction</span>
              <strong>Skill spec + task registry + Benchmark Lab</strong>
              <ArrowRight size={16} />
            </a>
          </div>
        </section>

        <section className="developer-section">
          <div className="section-heading compact">
            <p className="eyebrow">System Shape</p>
            <h2>实现链路</h2>
          </div>
          <div className="system-flow">
            {[
              ['Model', 'provider-native tool call'],
              ['Adapter', 'schema normalization'],
              ['ActionRunner', 'validation + execution'],
              ['Evidence', 'paths, logs, failureKind'],
              ['RuntimeManager', 'Helper / Termux / WebView'],
              ['GitHub', 'Actions, Pages, Release'],
            ].map(([title, text], index) => (
              <article key={title}>
                <span>{index + 1}</span>
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="developer-section release-evidence">
          <div>
            <p className="eyebrow">Release Evidence</p>
            <h2>双端产物与公开证据</h2>
            <p>
              v0.1.68-mobile-harness-d2dd9a7 已由 GitHub Actions 验证产出 Android APK、iOS simulator app zip 和 unsigned iOS archive。
              iOS archive 未签名，signed IPA 需要 Apple signing secrets 与 provisioning profile。
            </p>
          </div>
          <div className="release-links">
            {releaseAssets.map((asset) => (
              <a key={asset.href} href={asset.href} target="_blank" rel="noreferrer">
                <PackageCheck size={18} />
                <span>{asset.label}</span>
                <ArrowRight size={16} />
              </a>
            ))}
          </div>
        </section>

        <section className="developer-section developer-roadmap">
          <div className="developer-panel-title">
            <GitBranch size={22} />
            <h2>下一阶段路线</h2>
          </div>
          <div className="roadmap-grid">
            <article>
              <Layers3 size={20} />
              <h3>视觉预览证据</h3>
              <p>从 metadata/DOM/viewport 走向真实 bitmap artifact，并建立 screenshot-grade verification。</p>
            </article>
            <article>
              <Boxes size={20} />
              <h3>Sub-Agent Lite</h3>
              <p>稳定 Explorer/Reviewer 后台只读 worker，保留主 AgentLoop 作为唯一写入通道。</p>
            </article>
            <article>
              <Workflow size={20} />
              <h3>Runtime Recovery</h3>
              <p>增强 task lost、timeout、dependencyMissing 的可恢复 UI 与证据链。</p>
            </article>
            <article>
              <Code2 size={20} />
              <h3>Release Honesty</h3>
              <p>持续把已实现、降级、阻断、计划能力分开，不把路线图包装成已交付。</p>
            </article>
          </div>
        </section>
      </div>
    </section>
  );
}
