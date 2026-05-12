import { Check, Clock } from 'lucide-react';

const tiers = [
  {
    name: 'Preview',
    price: 'Free',
    note: '适合早期试用、产品验证和开源演示。',
    features: ['宣传页源码', '核心 Flutter 模块', 'GitHub 工作流雏形', '本地配置文档'],
  },
  {
    name: 'Pro',
    price: 'Planned',
    note: '面向独立开发者的完整移动开发体验。',
    features: ['Agent 自动执行', '多模型接入', '云端构建', '高级代码索引'],
  },
  {
    name: 'Team',
    price: 'Planned',
    note: '面向小团队的移动协作和知识沉淀。',
    features: ['团队项目空间', '共享知识库', 'PR 评审辅助', '审计与权限'],
  },
];

export default function Pricing() {
  return (
    <section className="page-section">
      <div className="section-container">
        <div className="page-title">
          <p className="eyebrow">Pricing</p>
          <h1>先开放预览版，商业版本按能力逐步发布</h1>
          <p>当前仓库适合作为产品预览、技术验证和后续发布的起点。</p>
        </div>
        <div className="pricing-grid">
          {tiers.map((tier) => (
            <article className="price-card" key={tier.name}>
              <div className="price-head">
                <h2>{tier.name}</h2>
                <strong>{tier.price}</strong>
              </div>
              <p>{tier.note}</p>
              <ul>
                {tier.features.map((feature) => (
                  <li key={feature}>
                    <Check size={16} /> {feature}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>
        <p className="release-note">
          <Clock size={16} /> APK/IPA 会在平台工程补齐后作为 GitHub Release 资产追加。
        </p>
      </div>
    </section>
  );
}
