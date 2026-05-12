import {
  ArrowRight,
  BrainCircuit,
  CheckCircle2,
  Code2,
  Gamepad2,
  Github,
  HeartPulse,
  KeyRound,
  MessageSquareText,
  Rocket,
  Smartphone,
  Terminal,
  Wrench,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

const pageBase = import.meta.env.BASE_URL;
const apkUrl = 'https://github.com/Harzva/mobilecode/releases/download/v0.1.0/mobilecode-v0.1.0.apk';
const releaseUrl = 'https://github.com/Harzva/mobilecode/releases/tag/v0.1.0';
const repoUrl = 'https://github.com/Harzva/mobilecode';
const demo2048Url = `${pageBase}demo/2048/`;
const githubTestUrl = `${pageBase}github-test/`;

const heroStats = [
  { value: 'v0.1.0+5', label: 'Android APK' },
  { value: '62+', label: '后端服务能力' },
  { value: 'GitHub', label: 'Pages + Release' },
];

const demoCards: Array<{ title: string; text: string; Icon: LucideIcon; href: string; label: string }> = [
  {
    title: '2048 在线 Demo',
    text: '手机浏览器直接打开，验证 MobileCode 能把轻量玩法发布成可体验网页。',
    Icon: Gamepad2,
    href: demo2048Url,
    label: '开始试玩',
  },
  {
    title: 'GitHub 联通测试',
    text: '填写 GitHub token，检查账号身份、仓库权限和 Pages 发布状态。',
    Icon: Github,
    href: githubTestUrl,
    label: '测试连接',
  },
  {
    title: '真实 APK 下载',
    text: 'GitHub Actions 构建的 Flutter release APK，包含 Demo Lab、Chat Memory、Tool Lab。',
    Icon: Smartphone,
    href: apkUrl,
    label: '下载 APK',
  },
];

const capabilityCards: Array<{ title: string; text: string; Icon: LucideIcon }> = [
  {
    title: '多轮 AI Chat',
    text: '会话列表、本地持久化、最近上下文随请求发送，接近 ChatGPT/豆包式连续对话。',
    Icon: MessageSquareText,
  },
  {
    title: '移动工具调用',
    text: 'Tool Lab 将 AI Health、Web Demo、本地存储、Termux handler 做成可点击检测。',
    Icon: Wrench,
  },
  {
    title: 'Termux 开发桥',
    text: '先做安装与 URL handler 检测，下一步接入 Android package visibility 和 TermuxService。',
    Icon: Terminal,
  },
  {
    title: '安全配置入口',
    text: 'API Base URL、Key、Model 与 provider health 放在 APK 首屏，优先保障模型可用。',
    Icon: KeyRound,
  },
];

const flow = [
  '手机输入想法',
  'AI 拆解任务',
  '生成 Demo / 文件',
  '测试工具联通',
  '同步 GitHub 发布',
];

const layers = [
  'AI Core',
  'Agents',
  'Code Intelligence',
  'Remote Dev',
  'Security',
  'Analytics',
  'Tools',
  'Performance',
];

function HeroProof() {
  return (
    <div className="hero-proof" aria-label="MobileCode proof panel">
      <div className="proof-topline">
        <span>Live build</span>
        <CheckCircle2 size={18} />
      </div>
      <div className="proof-screen">
        <div className="proof-row">
          <HeartPulse size={18} />
          <span>Provider health</span>
          <strong>Healthy</strong>
        </div>
        <div className="proof-row">
          <Github size={18} />
          <span>GitHub workflow</span>
          <strong>Ready</strong>
        </div>
        <div className="proof-row">
          <BrainCircuit size={18} />
          <span>Chat memory</span>
          <strong>On</strong>
        </div>
        <div className="proof-row">
          <Terminal size={18} />
          <span>Termux check</span>
          <strong>Probe</strong>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <>
      <section className="hero">
        <img className="hero-bg-image" src={`${pageBase}og-image.jpg`} alt="" aria-hidden="true" />
        <div className="hero-vignette" aria-hidden="true" />
        <div className="section-container hero-center">
          <p className="hero-pill">下一代移动端 AI 编程体验</p>
          <h1>
            <span>MobileCode</span>
            <strong>重新定义移动端编程</strong>
          </h1>
          <p className="hero-lede">
            用安卓开发安卓，用手机连接 AI、GitHub、Termux 和云端构建。它不是缩小版 IDE，而是为触屏、碎片时间和 Agent 工作流重新设计的移动开发控制台。
          </p>
          <div className="hero-actions">
            <a href={apkUrl} className="btn-primary">
              下载应用 <ArrowRight size={18} />
            </a>
            <a href={demo2048Url} className="btn-secondary">
              立即体验
            </a>
            <a href={githubTestUrl} className="btn-secondary">
              GitHub 测试
            </a>
          </div>
          <div className="hero-stats">
            {heroStats.map((item) => (
              <div key={item.label}>
                <strong>{item.value}</strong>
                <span>{item.label}</span>
              </div>
            ))}
          </div>
          <a className="scroll-cue" href="#demo-lab" aria-label="Scroll to demos">
            <ArrowRight size={18} />
          </a>
        </div>
      </section>

      <section className="section-band demo-section" id="demo-lab">
        <div className="section-container">
          <div className="section-heading">
            <p className="eyebrow">Demo Lab</p>
            <h2>把当前 GitHub Pages 的测试能力，收进正式宣传页里</h2>
            <p>
              这三个入口就是现在最应该给用户验证的重点：能打开在线 Demo、能检查 GitHub 是否打通、能下载真实 APK。
            </p>
          </div>
          <div className="demo-grid">
            {demoCards.map(({ title, text, Icon, href, label }) => (
              <a className="demo-card" key={title} href={href}>
                <Icon size={26} />
                <h3>{title}</h3>
                <p>{text}</p>
                <span>{label}</span>
              </a>
            ))}
          </div>
        </div>
      </section>

      <section className="section-band alt">
        <div className="section-container split product-split">
          <div>
            <p className="eyebrow">Product Focus</p>
            <h2>首要目标不是堆功能，而是让手机端真的能完成一次开发闭环</h2>
            <p>
              APK 现在已经从“能力地图”调整为“可点击验证”：API 配置、健康检查、AI Chat、GitHub、工具调用、Termux、日记 Demo 和在线游戏 Demo 都有明确入口。
            </p>
            <div className="flow-list">
              {flow.map((item, index) => (
                <div className="flow-item" key={item}>
                  <span>{String(index + 1).padStart(2, '0')}</span>
                  <strong>{item}</strong>
                </div>
              ))}
            </div>
          </div>
          <HeroProof />
        </div>
      </section>

      <section className="section-band">
        <div className="section-container">
          <div className="section-heading">
            <p className="eyebrow">Mobile Runtime</p>
            <h2>APK 已经开始具备基本移动开发环境的形状</h2>
          </div>
          <div className="capability-grid">
            {capabilityCards.map(({ title, text, Icon }) => (
              <article className="capability-card" key={title}>
                <Icon size={24} />
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section-band alt">
        <div className="section-container release-strip">
          <div>
            <p className="eyebrow">Backend Surface</p>
            <h2>后端能力很厚，前端要按用户任务重新组织</h2>
            <p>
              AI Core、Agent、代码智能、远程开发、安全存储、数据分析、工具集成和性能优化不应该散落展示。MobileCode 会把它们压缩成几个手机上能理解、能测试、能完成的工作台。
            </p>
            <div className="layer-strip">
              {layers.map((layer) => (
                <span key={layer}>{layer}</span>
              ))}
            </div>
          </div>
          <div className="terminal-preview">
            <div className="terminal-title">
              <Code2 size={16} />
              <span>mobilecode release</span>
            </div>
            <code>provider.health: healthy</code>
            <code>chat.memory: persisted</code>
            <code>github.pages: deployed</code>
            <code>apk.release: v0.1.0+5</code>
          </div>
        </div>
      </section>

      <section className="section-band final-cta">
        <div className="section-container">
          <Rocket size={34} />
          <h2>MobileCode 已经可以被安装、打开、测试、发布。</h2>
          <p>下一步要做的是把工具调用和 Termux 从“可检测”推进到“可执行”。</p>
          <div className="hero-actions">
            <a href={releaseUrl} className="btn-primary">
              查看 Release <ArrowRight size={18} />
            </a>
            <a href={repoUrl} className="btn-secondary">
              GitHub 仓库
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
