import { CheckCircle2, CircleDot, PackageCheck } from 'lucide-react';

const entries = [
  {
    version: 'v0.1.46-last',
    title: 'Last release APK',
    text: '发布 last 分支 Android APK，并补充 relay/provider 修复后的可验证发布证据。',
    done: true,
  },
  {
    version: 'Next',
    title: 'README and Pages showcase',
    text: '把新增 PNG/MP4 视觉证明接入 README 和 GitHub Pages，保持公开展示素材一致。',
    done: false,
  },
  {
    version: 'Later',
    title: 'iOS product package',
    text: '在 macOS/Xcode 环境生成 iOS Runner 工程，配置 Bundle ID、签名和 TestFlight 流程。',
    done: false,
  },
];

export default function Changelog() {
  return (
    <section className="page-section">
      <div className="section-container narrow">
        <div className="page-title">
          <p className="eyebrow">Changelog</p>
          <h1>发布日志</h1>
          <p>当前发布重点是把可验证的内容先交付，不把缺失平台工程的安装包伪装成正式产物。</p>
        </div>
        <div className="timeline-list">
          {entries.map((entry) => (
            <article key={entry.version}>
              {entry.done ? <CheckCircle2 size={22} /> : <CircleDot size={22} />}
              <div>
                <span>{entry.version}</span>
                <h2>{entry.title}</h2>
                <p>{entry.text}</p>
              </div>
            </article>
          ))}
        </div>
        <div className="release-note">
          <PackageCheck size={16} /> Release 页面已经提供可下载 APK，Pages 展示最新视觉证据。
        </div>
      </div>
    </section>
  );
}
