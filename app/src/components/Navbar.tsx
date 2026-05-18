import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Code2, Menu, X } from 'lucide-react';

const apkUrl = 'https://github.com/Harzva/mobilecode/releases/download/v0.1.0/mobilecode-v0.1.0.apk';

const navLinks = [
  { label: '产品特性', path: '/features' },
  { label: '文档中心', path: '/docs' },
  { label: '更新日志', path: '/changelog' },
  { label: '关于我们', path: '/about' },
];

export default function Navbar() {
  const [open, setOpen] = useState(false);
  const location = useLocation();

  return (
    <header className="site-header">
      <div className="section-container nav-wrap">
        <Link to="/" className="brand">
          <Code2 size={22} />
          <span>MobileCode</span>
        </Link>

        <nav className="desktop-nav" aria-label="Main navigation">
          {navLinks.map((link) => (
            <Link key={link.path} to={link.path} className={location.pathname === link.path ? 'active' : ''}>
              {link.label}
            </Link>
          ))}
        </nav>

        <a href={apkUrl} className="nav-cta">
          下载应用
        </a>

        <button className="menu-button" onClick={() => setOpen((value) => !value)} aria-label="Toggle menu">
          {open ? <X size={22} /> : <Menu size={22} />}
        </button>
      </div>

      {open && (
        <nav className="mobile-nav" aria-label="Mobile navigation">
          {navLinks.map((link) => (
            <Link key={link.path} to={link.path} onClick={() => setOpen(false)}>
              {link.label}
            </Link>
          ))}
          <a href={apkUrl} onClick={() => setOpen(false)}>
            下载应用
          </a>
        </nav>
      )}
    </header>
  );
}
