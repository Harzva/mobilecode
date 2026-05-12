import { CheckCircle2, CircleDot, PackageCheck } from 'lucide-react';

const entries = [
  {
    version: 'v0.1.0',
    title: 'Preview release',
    text: '整理产品定位、修复宣传站乱码、输出 Web 构建产物，准备 GitHub Release。',
    done: true,
  },
  {
    version: 'Next',
    title: 'Android build recovery',
    text: '安装 Flutter SDK，补齐 Android Gradle 工程、assets 和签名配置，生成 APK/AAB。',
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
          <PackageCheck size={16} /> Release 会包含 Web 产物和源码包，移动安装包后续追加。
        </div>
      </div>
    </section>
  );
}
