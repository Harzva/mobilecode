import { Github, Mail, MessageSquare } from 'lucide-react';

export default function Contact() {
  return (
    <section className="page-section">
      <div className="section-container contact-grid">
        <div className="page-title left">
          <p className="eyebrow">Contact</p>
          <h1>想试用 MobileCode 或继续完善移动端工程？</h1>
          <p>可以先通过 GitHub Issue 跟踪需求，也可以把 APK/iOS 打包环境补齐后继续发布安装包。</p>
        </div>
        <div className="contact-card">
          <a href="mailto:hello@mobilecode.dev">
            <Mail size={20} />
            hello@mobilecode.dev
          </a>
          <a href="https://github.com" target="_blank" rel="noreferrer">
            <Github size={20} />
            GitHub repository
          </a>
          <a href="/docs">
            <MessageSquare size={20} />
            查看发布说明
          </a>
        </div>
      </div>
    </section>
  );
}
