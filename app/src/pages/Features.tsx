import { Bot, Camera, Cloud, GitPullRequest, Mic, Smartphone, Terminal } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

const items: Array<{ title: string; text: string; Icon: LucideIcon }> = [
  { title: '截图到代码', text: '识别 UI 截图、白板草图和页面灵感，生成可编辑组件。', Icon: Camera },
  { title: '语音到任务', text: '把自然语言转成任务计划、改动步骤和代码补丁。', Icon: Mic },
  { title: '触屏代码编辑', text: '为小屏优化文件树、代码片段、预览和快捷操作。', Icon: Smartphone },
  { title: 'Agent Action', text: '让 AI 执行搜索、编辑、构建、修复和复盘等连续动作。', Icon: Bot },
  { title: '云端运行', text: '把重型模型和构建任务放到远端，手机保留轻量交互。', Icon: Cloud },
  { title: 'GitHub 协作', text: '移动端完成仓库浏览、提交、PR、Issue 和团队反馈。', Icon: GitPullRequest },
];

export default function Features() {
  return (
    <section className="page-section">
      <div className="section-container">
        <div className="page-title">
          <p className="eyebrow">Features</p>
          <h1>MobileCode 的核心能力</h1>
          <p>它不是桌面 IDE 的缩小版，而是一套围绕移动输入、AI 执行和云端能力设计的开发流程。</p>
        </div>
        <div className="feature-grid">
          {items.map(({ title, text, Icon }) => (
            <article className="feature-card" key={title}>
              <Icon size={24} />
              <h3>{title}</h3>
              <p>{text}</p>
            </article>
          ))}
        </div>
        <div className="terminal-panel">
          <Terminal size={20} />
          <code>mobilecode run preview --agent --github-sync</code>
        </div>
      </div>
    </section>
  );
}
