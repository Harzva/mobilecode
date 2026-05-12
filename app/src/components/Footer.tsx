import { Github, Mail } from 'lucide-react';
import { Link } from 'react-router-dom';

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="section-container footer-grid">
        <div>
          <strong>MobileCode</strong>
          <p>AI coding workspace for mobile devices.</p>
        </div>
        <div className="footer-links">
          <Link to="/features">功能</Link>
          <Link to="/docs">文档</Link>
          <Link to="/contact">联系</Link>
          <a href="https://github.com" target="_blank" rel="noreferrer" aria-label="GitHub">
            <Github size={18} />
          </a>
          <a href="mailto:hello@mobilecode.dev" aria-label="Email">
            <Mail size={18} />
          </a>
        </div>
      </div>
    </footer>
  );
}
