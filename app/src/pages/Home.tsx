import {
  ArrowRight,
  Bot,
  Braces,
  Camera,
  Cloud,
  GitBranch,
  Mic,
  ShieldCheck,
  Smartphone,
  Terminal,
} from 'lucide-react';
import { Link } from 'react-router-dom';

const features = [
  {
    icon: Camera,
    title: '截图生成代码',
    text: '把草图、截图、白板方案交给 AI，快速生成可继续编辑的页面和组件。',
  },
  {
    icon: Mic,
    title: '语音描述需求',
    text: '在路上也能说出改动意图，让 Agent 拆解任务、补代码、写说明。',
  },
  {
    icon: Terminal,
    title: '移动端开发工作台',
    text: '项目、终端、预览、代码片段和任务计划都围绕触屏重新组织。',
  },
  {
    icon: GitBranch,
    title: 'GitHub 工作流',
    text: '查看仓库、同步代码、处理 Issue 和 PR，把轻量协作搬到手机上。',
  },
];

const metrics = [
  { value: '0.1.0', label: '当前产品版本' },
  { value: '70+', label: 'Flutter 模块文件' },
  { value: '6', label: '核心使用场景' },
  { value: 'Web', label: '已可发布宣传页' },
];

const workflow = [
  '记录想法',
  'AI 拆任务',
  '编辑代码',
  '预览验证',
  '同步 GitHub',
];

function ProductMockup() {
  return (
    <div className="device-showcase" aria-label="MobileCode product preview">
      <div className="phone-shell">
        <div className="phone-status">
          <span>9:41</span>
          <span>MobileCode</span>
        </div>
        <div className="agent-panel">
          <div>
            <p className="panel-kicker">Active task</p>
            <h3>Build a login screen</h3>
          </div>
          <Bot className="panel-icon" />
        </div>
        <div className="code-window">
          <div className="code-line"><span>01</span>import LoginForm</div>
          <div className="code-line"><span>02</span>run preview --device</div>
          <div className="code-line accent"><span>03</span>AI: fixing layout</div>
          <div className="code-line"><span>04</span>git commit -m ui-login</div>
        </div>
        <div className="task-strip">
          {workflow.slice(1, 4).map((item) => (
            <span key={item}>{item}</span>
          ))}
        </div>
      </div>
      <img src="/og-image-en.jpg" alt="MobileCode brand visual" className="brand-visual" />
    </div>
  );
}

export default function Home() {
  return (
    <>
      <section className="hero">
        <div className="section-container hero-grid">
          <div className="hero-copy">
            <p className="eyebrow">Mobile AI Coding Workspace</p>
            <h1>MobileCode</h1>
            <p className="hero-lede">
              把 AI 编程、项目管理、预览验证和 GitHub 协作装进手机。适合随时记录灵感、
              修小功能、复盘代码，也适合把移动设备变成轻量开发工作台。
            </p>
            <div className="hero-actions">
              <Link to="/contact" className="btn-primary">
                获取预览版 <ArrowRight size={18} />
              </Link>
              <Link to="/features" className="btn-secondary">
                查看能力
              </Link>
            </div>
          </div>
          <ProductMockup />
        </div>
      </section>

      <section className="section-band">
        <div className="section-container">
          <div className="section-heading">
            <p className="eyebrow">Product Signal</p>
            <h2>完整度结论：宣传站可发布，移动 App 仍是预览工程</h2>
            <p>
              当前代码已经具备产品叙事、Flutter 业务模块和多项 Agent 服务雏形，但移动端缺少完整构建脚手架，
              发布包需要补齐 Flutter SDK、Android Gradle 工程和 iOS 工程后再生成。
            </p>
          </div>
          <div className="metric-grid">
            {metrics.map((metric) => (
              <div className="metric" key={metric.label}>
                <strong>{metric.value}</strong>
                <span>{metric.label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section-band alt">
        <div className="section-container split">
          <div>
            <p className="eyebrow">Core Flow</p>
            <h2>把碎片时间变成可交付的开发动作</h2>
            <p>
              MobileCode 的重点不是复刻桌面 IDE，而是把手机擅长的输入方式、AI 的任务执行能力、
              云端环境和 GitHub 协作串成一条短路径。
            </p>
          </div>
          <div className="workflow">
            {workflow.map((item, index) => (
              <div className="workflow-step" key={item}>
                <span>{String(index + 1).padStart(2, '0')}</span>
                <strong>{item}</strong>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section-band">
        <div className="section-container">
          <div className="section-heading">
            <p className="eyebrow">Feature Set</p>
            <h2>为移动场景重排的 AI 编程能力</h2>
          </div>
          <div className="feature-grid">
            {features.map((feature) => {
              const Icon = feature.icon;
              return (
                <article className="feature-card" key={feature.title}>
                  <Icon size={24} />
                  <h3>{feature.title}</h3>
                  <p>{feature.text}</p>
                </article>
              );
            })}
          </div>
        </div>
      </section>

      <section className="section-band alt">
        <div className="section-container release-strip">
          <div>
            <p className="eyebrow">Release Ready</p>
            <h2>先发布 Web 宣传页和源码，移动安装包等待工程补齐</h2>
            <p>
              我会把当前可构建的 Web 产物打成 release asset；APK/IPA 不会伪造，等 Flutter 环境和平台工程恢复后再补发。
            </p>
          </div>
          <div className="release-icons" aria-label="release channels">
            <Smartphone />
            <Cloud />
            <Braces />
            <ShieldCheck />
          </div>
        </div>
      </section>
    </>
  );
}
