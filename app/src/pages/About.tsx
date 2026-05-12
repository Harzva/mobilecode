import { Code2, Compass, Layers, ShieldCheck } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

const principles: Array<{ title: string; text: string; Icon: LucideIcon }> = [
  { title: '移动优先', text: '先思考手机上的真实动作，再决定功能如何出现。', Icon: Compass },
  { title: 'AI 协作', text: '让 Agent 承担重复劳动，用户保留判断、选择和发布权。', Icon: Code2 },
  { title: '轻量架构', text: '把重计算放到云端，把本地体验做得快速、清晰、可靠。', Icon: Layers },
  { title: '安全可控', text: '密钥、仓库和执行环境都需要显式授权与可审计边界。', Icon: ShieldCheck },
];

export default function About() {
  return (
    <section className="page-section">
      <div className="section-container">
        <div className="page-title">
          <p className="eyebrow">About</p>
          <h1>MobileCode 是为移动设备重新设计的 AI 编程产品</h1>
          <p>
            项目当前处于 preview 阶段：产品方向清楚，宣传站可发布，Flutter 业务代码已有较多模块，
            下一步重点是补齐可安装包工程和真实设备验证。
          </p>
        </div>
        <div className="feature-grid">
          {principles.map(({ title, text, Icon }) => (
            <article className="feature-card" key={title}>
              <Icon size={24} />
              <h3>{title}</h3>
              <p>{text}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
