import React from 'react';
import {AbsoluteFill, Audio, Easing, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';

const fps = 30;
const sceneFrames = 300;

const colors = {
  bg: '#F7FAFF',
  surface: '#FFFFFF',
  ink: '#0B1020',
  muted: '#536079',
  line: '#DDE7F7',
  blue: '#2555FF',
  mint: '#0B9B7E',
  purple: '#7557E8',
  amber: '#B7791F',
  red: '#D64562',
  dark: '#111827',
  softBlue: '#E9EEFF',
  softMint: '#EAF8F3',
  softPurple: '#F0ECFF',
  softAmber: '#FFF6E5',
  softRed: '#FFF0F4',
};

type Tint = 'blue' | 'mint' | 'purple' | 'amber' | 'red' | 'dark';

const tintMap: Record<Tint, {fg: string; bg: string}> = {
  blue: {fg: colors.blue, bg: colors.softBlue},
  mint: {fg: colors.mint, bg: colors.softMint},
  purple: {fg: colors.purple, bg: colors.softPurple},
  amber: {fg: colors.amber, bg: colors.softAmber},
  red: {fg: colors.red, bg: colors.softRed},
  dark: {fg: colors.dark, bg: '#EEF2F7'},
};

const scenes = [
  {
    eyebrow: 'Why MobileCode exists',
    title: 'AI coding is moving to the phone.',
    body:
      'But the phone should not pretend to be a desktop workstation. It needs a smaller, clearer harness for generation, preview, recovery, and shipping.',
    caption: 'Not a cloud IDE wrapper. A phone-native coding harness.',
    subtitle: 'MobileCode 不是云端 IDE 外壳，而是把 AI coding harness 真正放到手机上。',
    type: 'hero',
  },
  {
    eyebrow: 'The pain',
    title: 'Mobile coding breaks when execution is unclear.',
    body:
      'Users do not want to debug whether an action belongs to the app, Termux, a cloud shell, GitHub, or a hidden preview.',
    caption: 'The problem is not the screen size. The problem is an undefined execution layer.',
    subtitle: '手机写代码的核心痛点不是屏幕小，而是执行层不清楚、失败不可恢复。',
    type: 'pain',
  },
  {
    eyebrow: 'The answer',
    title: 'Keep the harness on the phone. Move heavy work outward.',
    body:
      'MobileCode owns chat state, tool trace, local files, WebView preview, runtime diagnostics, repo context, and the final work card.',
    caption: 'Local control plane. External heavy lifting.',
    subtitle: '手机保留对话、文件、预览、诊断和发布控制，把重构建交给外部平台。',
    type: 'solution',
  },
  {
    eyebrow: 'Runtime principle',
    title: 'RuntimeProvider turns execution into a replaceable contract.',
    body:
      'The UI should not care whether work runs through Helper, Termux, WebViewOnly, Embedded Lite, or Cloud Runtime.',
    caption: 'Interface first, backend second.',
    subtitle: 'RuntimeProvider 让 Helper、Termux、WebViewOnly、Cloud 都成为可替换后端。',
    type: 'architecture',
  },
  {
    eyebrow: 'GitHub-first loop',
    title: 'The phone edits and explains. GitHub stores, builds, and ships.',
    body:
      'Repo Hub, Contents API commits, Pages publishing, Actions runs, and release artifacts keep MobileCode lightweight but real.',
    caption: 'Prompt to file to preview to repository to Pages or Actions.',
    subtitle: 'GitHub 负责仓库、Pages、Actions 和产物，MobileCode 负责手机端闭环体验。',
    type: 'github',
  },
  {
    eyebrow: 'Outcome',
    title: 'A phone can become the AI coding control room.',
    body:
      'Not because it compiles everything locally, but because it keeps the user-facing harness, state, explanations, previews, and shipping decisions close to the user.',
    caption: 'MobileCode — build, preview, publish from your phone.',
    subtitle: '最终目标：在手机上生成、预览、解释、发布，而不是伪装成桌面环境。',
    type: 'outcome',
  },
] as const;

export const principleDurationInFrames = scenes.length * sceneFrames;

const fade = (frame: number) => {
  const inOpacity = interpolate(frame, [0, 28], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const outOpacity = interpolate(frame, [sceneFrames - 28, sceneFrames], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.cubic),
  });
  return Math.min(inOpacity, outOpacity);
};

const rise = (frame: number, delay = 0, distance = 34) =>
  interpolate(frame, [delay, delay + 36], [distance, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

const reveal = (frame: number, delay = 0) =>
  interpolate(frame, [delay, delay + 30], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

const Pill = ({children, tint}: {children: React.ReactNode; tint: Tint}) => {
  const token = tintMap[tint];
  return (
    <span
      style={{
        color: token.fg,
        background: token.bg,
        border: `2px solid ${token.fg}33`,
        borderRadius: 16,
        padding: '14px 20px',
        fontSize: 27,
        fontWeight: 950,
        whiteSpace: 'nowrap',
      }}
    >
      {children}
    </span>
  );
};

const Card = ({
  title,
  body,
  tint,
  index,
  frame,
}: {
  title: string;
  body: string;
  tint: Tint;
  index: number;
  frame: number;
}) => {
  const token = tintMap[tint];
  const delay = 54 + index * 18;
  return (
    <div
      style={{
        opacity: reveal(frame, delay),
        transform: `translateY(${rise(frame, delay, 32)}px)`,
        display: 'grid',
        gridTemplateColumns: '72px 1fr',
        gap: 22,
        alignItems: 'center',
        minHeight: 154,
        padding: 28,
        background: colors.surface,
        border: `2px solid ${colors.line}`,
        borderRadius: 18,
        boxShadow: '0 18px 45px rgba(37, 85, 255, .08)',
      }}
    >
      <div
        style={{
          width: 72,
          height: 72,
          borderRadius: 18,
          display: 'grid',
          placeItems: 'center',
          background: token.bg,
          color: token.fg,
          fontSize: 34,
          fontWeight: 1000,
        }}
      >
        {index + 1}
      </div>
      <div>
        <div style={{fontSize: 32, fontWeight: 1000, marginBottom: 8}}>{title}</div>
        <div style={{fontSize: 24, lineHeight: 1.35, color: colors.muted, fontWeight: 700}}>
          {body}
        </div>
      </div>
    </div>
  );
};

const PhoneHarness = ({frame}: {frame: number}) => {
  const steps = ['Parse intent', 'Select tool', 'Call model', 'Write artifact', 'Preview', 'Publish'];
  const done = Math.floor(interpolate(frame, [35, 220], [1, steps.length], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  }));

  return (
    <div
      style={{
        width: 430,
        height: 760,
        borderRadius: 56,
        background: colors.dark,
        padding: 24,
        boxShadow: '0 34px 110px rgba(11, 16, 32, .28)',
      }}
    >
      <div
        style={{
          height: '100%',
          borderRadius: 38,
          background: colors.bg,
          padding: 28,
          display: 'grid',
          gridTemplateRows: 'auto auto 1fr auto',
          gap: 20,
        }}
      >
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
          <div style={{fontSize: 31, fontWeight: 1000}}>MobileCode</div>
          <Pill tint="mint">ready</Pill>
        </div>
        <div
          style={{
            background: colors.surface,
            border: `2px solid ${colors.line}`,
            borderRadius: 16,
            padding: 18,
          }}
        >
          <div style={{fontSize: 22, fontWeight: 1000}}>Runtime ready</div>
          <div style={{fontSize: 16, color: colors.muted, fontWeight: 750, marginTop: 6}}>
            Helper · Termux · WebViewOnly
          </div>
        </div>
        <div style={{display: 'grid', gap: 12, alignContent: 'start'}}>
          {steps.map((step, index) => {
            const active = index < done;
            return (
              <div
                key={step}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  padding: 14,
                  borderRadius: 14,
                  border: `2px solid ${active ? '#A8E7D9' : colors.line}`,
                  background: active ? colors.softMint : colors.surface,
                  fontSize: 18,
                  fontWeight: 950,
                }}
              >
                <span
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 10,
                    display: 'grid',
                    placeItems: 'center',
                    background: active ? colors.mint : '#EEF2F7',
                    color: active ? '#FFFFFF' : colors.muted,
                    fontWeight: 1000,
                  }}
                >
                  {active ? '✓' : index + 1}
                </span>
                {step}
              </div>
            );
          })}
        </div>
        <div
          style={{
            height: 58,
            borderRadius: 16,
            background: colors.blue,
            color: '#FFFFFF',
            display: 'grid',
            placeItems: 'center',
            fontSize: 22,
            fontWeight: 1000,
          }}
        >
          Publish GitHub Pages
        </div>
      </div>
    </div>
  );
};

const HeaderText = ({
  eyebrow,
  title,
  body,
  frame,
  centered = false,
}: {
  eyebrow: string;
  title: string;
  body: string;
  frame: number;
  centered?: boolean;
}) => {
  return (
    <div style={{textAlign: centered ? 'center' : 'left'}}>
      <div
        style={{
          opacity: reveal(frame, 8),
          transform: `translateY(${rise(frame, 8, 26)}px)`,
          color: colors.blue,
          fontSize: 25,
          fontWeight: 1000,
          textTransform: 'uppercase',
        }}
      >
        {eyebrow}
      </div>
      <h1
        style={{
          opacity: reveal(frame, 20),
          transform: `translateY(${rise(frame, 20, 36)}px)`,
          margin: '22px 0 0',
          color: colors.ink,
          fontSize: centered ? 92 : 76,
          lineHeight: 0.96,
          fontWeight: 1000,
          maxWidth: centered ? 1200 : 820,
        }}
      >
        {title}
      </h1>
      <p
        style={{
          opacity: reveal(frame, 36),
          transform: `translateY(${rise(frame, 36, 30)}px)`,
          maxWidth: centered ? 1050 : 780,
          margin: centered ? '34px auto 0' : '32px 0 0',
          color: colors.muted,
          fontSize: 34,
          lineHeight: 1.34,
          fontWeight: 700,
        }}
      >
        {body}
      </p>
    </div>
  );
};

const SceneFrame = ({scene, index}: {scene: (typeof scenes)[number]; index: number}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [0, sceneFrames], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const layout: React.CSSProperties =
    scene.type === 'hero' || scene.type === 'outcome'
      ? {
          position: 'absolute',
          inset: 96,
          display: 'grid',
          placeItems: 'center',
          textAlign: 'center',
        }
      : {
          position: 'absolute',
          inset: 92,
          display: 'grid',
          gridTemplateColumns: '0.92fr 1.08fr',
          alignItems: 'center',
          gap: 70,
        };

  return (
    <AbsoluteFill
      style={{
        opacity: fade(frame),
        background: colors.bg,
        color: colors.ink,
        fontFamily:
          'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 54,
          border: `3px solid ${colors.line}`,
          borderRadius: 36,
          background: colors.surface,
          boxShadow: '0 30px 110px rgba(37, 85, 255, .13)',
          overflow: 'hidden',
        }}
      />

      <div style={layout}>
        {scene.type === 'hero' && (
          <div>
            <HeaderText
              centered
              eyebrow={scene.eyebrow}
              title={scene.title}
              body={scene.body}
              frame={frame}
            />
            <div
              style={{
                opacity: reveal(frame, 74),
                transform: `translateY(${rise(frame, 74)}px)`,
                display: 'flex',
                justifyContent: 'center',
                gap: 16,
                marginTop: 48,
              }}
            >
              <Pill tint="blue">phone-native harness</Pill>
              <Pill tint="mint">remote model optional</Pill>
              <Pill tint="amber">GitHub-first shipping</Pill>
            </div>
          </div>
        )}

        {scene.type === 'pain' && (
          <>
            <HeaderText eyebrow={scene.eyebrow} title={scene.title} body={scene.body} frame={frame} />
            <div style={{display: 'grid', gap: 18}}>
              <Card title="Heavy local toolchains" body="Flutter SDK, Gradle, Android SDK, and native deps are too large for the default phone path." tint="red" index={0} frame={frame} />
              <Card title="Opaque remote IDEs" body="If the real harness lives in the cloud, the phone becomes a thin remote control skin." tint="red" index={1} frame={frame} />
              <Card title="Raw shell exposure" body="Terminals are powerful, but they rarely explain failure, permission, path, and recovery state." tint="red" index={2} frame={frame} />
            </div>
          </>
        )}

        {scene.type === 'solution' && (
          <>
            <div style={{justifySelf: 'center', opacity: reveal(frame, 32), transform: `translateY(${rise(frame, 32)}px)`}}>
              <PhoneHarness frame={frame} />
            </div>
            <div>
              <HeaderText eyebrow={scene.eyebrow} title={scene.title} body={scene.body} frame={frame} />
              <div style={{display: 'flex', flexWrap: 'wrap', gap: 16, marginTop: 42, opacity: reveal(frame, 84)}}>
                <Pill tint="blue">agent trace</Pill>
                <Pill tint="purple">file cards</Pill>
                <Pill tint="mint">preview</Pill>
                <Pill tint="amber">publish</Pill>
              </div>
            </div>
          </>
        )}

        {scene.type === 'architecture' && (
          <>
            <HeaderText eyebrow={scene.eyebrow} title={scene.title} body={scene.body} frame={frame} />
            <div style={{display: 'grid', gap: 18}}>
              <Card title="Flutter App" body="Chat, files, settings, preview, diagnostics, work cards." tint="blue" index={0} frame={frame} />
              <Card title="RuntimeManager" body="Chooses Helper, Termux, WebViewOnly, Cloud, or future Embedded Lite." tint="purple" index={1} frame={frame} />
              <Card title="RuntimeProvider" body="A stable contract: capabilities, execute, stream, sync, health." tint="mint" index={2} frame={frame} />
            </div>
          </>
        )}

        {scene.type === 'github' && (
          <>
            <HeaderText eyebrow={scene.eyebrow} title={scene.title} body={scene.body} frame={frame} />
            <div style={{display: 'grid', gap: 18}}>
              <Card title="Repo Hub" body="Discover public repos without login; manage owned repos with scoped token auth." tint="blue" index={0} frame={frame} />
              <Card title="GitHub Pages" body="Turn phone-generated HTML into a shareable website." tint="mint" index={1} frame={frame} />
              <Card title="GitHub Actions" body="Move heavy APK/Web/release builds into CI and pull artifacts back to the phone." tint="amber" index={2} frame={frame} />
            </div>
          </>
        )}

        {scene.type === 'outcome' && (
          <div>
            <HeaderText centered eyebrow={scene.eyebrow} title={scene.title} body={scene.body} frame={frame} />
            <div
              style={{
                opacity: reveal(frame, 82),
                transform: `translateY(${rise(frame, 82)}px)`,
                display: 'grid',
                gridTemplateColumns: 'repeat(3, 1fr)',
                gap: 18,
                marginTop: 54,
              }}
            >
              {[
                ['Local', 'chat, trace, files, preview, recovery', 'blue'],
                ['Routed', 'Helper, Termux, WebViewOnly, Cloud', 'purple'],
                ['Shipped', 'GitHub Pages, Actions, artifacts', 'mint'],
              ].map(([title, body, tint]) => {
                const token = tintMap[tint as Tint];
                return (
                  <div
                    key={title}
                    style={{
                      minHeight: 150,
                      padding: 30,
                      borderRadius: 20,
                      border: `2px solid ${colors.line}`,
                      background: colors.surface,
                      textAlign: 'left',
                    }}
                  >
                    <div style={{fontSize: 48, fontWeight: 1000, color: token.fg}}>{title}</div>
                    <div style={{fontSize: 22, lineHeight: 1.35, color: colors.muted, fontWeight: 800, marginTop: 10}}>{body}</div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      <div
        style={{
          position: 'absolute',
          left: 96,
          right: 96,
          bottom: 142,
          display: 'flex',
          justifyContent: 'center',
          pointerEvents: 'none',
        }}
      >
        <div
          style={{
            opacity: reveal(frame, 64),
            transform: `translateY(${rise(frame, 64, 18)}px)`,
            maxWidth: 1180,
            padding: '18px 28px',
            borderRadius: 18,
            color: '#FFFFFF',
            background: 'rgba(11, 16, 32, .82)',
            boxShadow: '0 18px 50px rgba(11, 16, 32, .25)',
            fontSize: 34,
            lineHeight: 1.28,
            fontWeight: 950,
            textAlign: 'center',
          }}
        >
          {scene.subtitle}
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 96,
          right: 96,
          bottom: 82,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          color: colors.muted,
          fontSize: 24,
          fontWeight: 850,
        }}
      >
        <span>
          <strong style={{color: colors.ink}}>Scene {String(index + 1).padStart(2, '0')}</strong> /{' '}
          {String(scenes.length).padStart(2, '0')}
        </span>
        <span>{scene.caption}</span>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 96,
          right: 96,
          bottom: 52,
          height: 8,
          borderRadius: 999,
          background: '#DBE5F6',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            width: `${((index + p) / scenes.length) * 100}%`,
            height: '100%',
            background: colors.blue,
          }}
        />
      </div>
    </AbsoluteFill>
  );
};

export const MobileCodePrincipleExplainer = () => {
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Audio src={staticFile('audio/mobilecode-principle-voiceover.wav')} volume={0.92} />
      {scenes.map((scene, index) => (
        <Sequence key={scene.eyebrow} from={index * sceneFrames} durationInFrames={sceneFrames}>
          <SceneFrame scene={scene} index={index} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
