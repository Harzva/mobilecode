import { BookOpen, Package, Rocket, Wrench } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

const docs: Array<{ title: string; text: string; Icon: LucideIcon }> = [
  { title: '安装依赖', text: '进入 app 目录执行 npm install，再运行 npm run build。', Icon: Package },
  { title: '启动宣传页', text: 'npm run dev 可启动 Vite 本地预览，默认使用 React Router。', Icon: Rocket },
  { title: '移动端工程', text: 'mobile_agent 当前保留 Flutter 业务源码，需补齐 Flutter SDK 与平台脚手架。', Icon: Wrench },
  { title: '发布流程', text: '先创建 GitHub 仓库，构建 Web dist，再把可生成产物上传到 Release。', Icon: BookOpen },
];

export default function Docs() {
  return (
    <section className="page-section">
      <div className="section-container">
        <div className="page-title">
          <p className="eyebrow">Docs</p>
          <h1>开发与发布说明</h1>
          <p>这里保留最关键的本地运行、构建和发布信息，方便 GitHub 访问者快速判断项目状态。</p>
        </div>
        <div className="doc-list">
          {docs.map(({ title, text, Icon }) => (
            <article key={title}>
              <Icon size={22} />
              <div>
                <h2>{title}</h2>
                <p>{text}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
