import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Code2, Menu, X } from 'lucide-react';

const navLinks = [
  { label: '功能', path: '/features' },
  { label: '定价', path: '/pricing' },
  { label: '文档', path: '/docs' },
  { label: '日志', path: '/changelog' },
  { label: '关于', path: '/about' },
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

        <Link to="/contact" className="nav-cta">
          获取预览版
        </Link>

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
          <Link to="/contact" onClick={() => setOpen(false)}>获取预览版</Link>
        </nav>
      )}
    </header>
  );
}
