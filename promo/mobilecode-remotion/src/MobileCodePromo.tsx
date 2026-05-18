import React from 'react';
import {
  AbsoluteFill,
  Easing,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {recordedClips} from './recordedClips';

type PromoFormat = 'vertical' | 'wide';

type PromoProps = {
  format: PromoFormat;
};

const colors = {
  bg: '#F7FAFF',
  surface: '#FFFFFF',
  ink: '#0B1020',
  muted: '#536079',
  border: '#DDE7F7',
  blue: '#2555FF',
  mint: '#0B9B7E',
  mintSoft: '#EAF8F3',
  purple: '#7557E8',
  purpleSoft: '#F0ECFF',
  amber: '#B7791F',
  amberSoft: '#FFF6E5',
  dark: '#111827',
};

const scenes = {
  hook: {from: 0, duration: 150},
  trace: {from: 150, duration: 180},
  artifact: {from: 330, duration: 180},
  runtime: {from: 510, duration: 180},
  github: {from: 690, duration: 210},
  proof: {from: 900, duration: 180},
  close: {from: 1080, duration: 180},
};

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));

const sceneProgress = (frame: number, from: number, duration: number) =>
  clamp((frame - from) / duration);

const fadeInOut = (frame: number, from: number, duration: number) => {
  const start = interpolate(frame, [from, from + 24], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const end = interpolate(frame, [from + duration - 24, from + duration], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.cubic),
  });
  return Math.min(start, end);
};

const lineReveal = (frame: number, offset: number) =>
  interpolate(frame, [offset, offset + 34], [26, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

const stackBase: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
};

const enabledRecordings = recordedClips.filter((clip) => clip.enabled);

const pill = (
  text: string,
  tint: 'blue' | 'mint' | 'purple' | 'amber' | 'dark',
): React.CSSProperties => {
  const map = {
    blue: [colors.blue, '#E9EEFF'],
    mint: [colors.mint, colors.mintSoft],
    purple: [colors.purple, colors.purpleSoft],
    amber: [colors.amber, colors.amberSoft],
    dark: [colors.dark, '#EEF2F7'],
  } as const;
  const [fg, bg] = map[tint];
  return {
    color: fg,
    background: bg,
    border: `2px solid ${fg}22`,
    borderRadius: 999,
    padding: '10px 18px',
    fontWeight: 900,
    fontSize: 24,
    lineHeight: 1,
    whiteSpace: 'nowrap',
  };
};

const Shell = ({children, format}: {children: React.ReactNode; format: PromoFormat}) => {
  const isWide = format === 'wide';
  return (
    <AbsoluteFill
      style={{
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
          inset: isWide ? 46 : 42,
          borderRadius: isWide ? 38 : 46,
          border: `3px solid ${colors.border}`,
          background: colors.surface,
          boxShadow: '0 28px 90px rgba(37, 85, 255, 0.12)',
          overflow: 'hidden',
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};

const PhoneMock = ({
  progress,
  compact = false,
}: {
  progress: number;
  compact?: boolean;
}) => {
  const traceDone = Math.floor(interpolate(progress, [0, 1], [1, 5], {extrapolateRight: 'clamp'}));
  return (
    <div
      style={{
        width: compact ? 520 : 620,
        height: compact ? 890 : 1120,
        background: colors.dark,
        borderRadius: compact ? 48 : 62,
        padding: compact ? 28 : 36,
        boxShadow: '0 34px 110px rgba(11, 16, 32, 0.28)',
      }}
    >
      <div
        style={{
          width: '100%',
          height: '100%',
          background: colors.bg,
          borderRadius: compact ? 34 : 44,
          padding: compact ? 30 : 36,
          ...stackBase,
          gap: compact ? 24 : 28,
        }}
      >
        <div style={{display: 'flex', alignItems: 'center', gap: 18}}>
          <div
            style={{
              width: 54,
              height: 54,
              borderRadius: 17,
              background: colors.mintSoft,
              color: colors.mint,
              fontSize: 34,
              fontWeight: 900,
              display: 'grid',
              placeItems: 'center',
            }}
          >
            ✓
          </div>
          <div>
            <div style={{fontSize: compact ? 26 : 34, fontWeight: 950}}>MobileCode</div>
            <div style={{fontSize: compact ? 17 : 22, color: colors.muted}}>
              Phone-native AI coding harness
            </div>
          </div>
        </div>

        <div
          style={{
            background: colors.surface,
            border: `2px solid ${colors.border}`,
            borderRadius: 24,
            padding: 24,
          }}
        >
          <div style={{fontSize: compact ? 19 : 24, color: colors.muted}}>Runtime ready</div>
          <div style={{fontSize: compact ? 24 : 30, fontWeight: 950, marginTop: 8}}>
            WebView Only · Helper · Termux fallback
          </div>
        </div>

        <div style={{...stackBase, gap: compact ? 14 : 18}}>
          {['Parse instruction', 'Select tool', 'Call model provider', 'Write artifact', 'Preview result'].map(
            (label, index) => {
              const done = index < traceDone;
              return (
                <div
                  key={label}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 16,
                    padding: compact ? '16px 18px' : '20px 22px',
                    background: done ? colors.mintSoft : colors.surface,
                    border: `2px solid ${done ? '#A8E7D9' : colors.border}`,
                    borderRadius: 20,
                  }}
                >
                  <div
                    style={{
                      width: compact ? 34 : 42,
                      height: compact ? 34 : 42,
                      borderRadius: 12,
                      background: done ? colors.mint : '#EEF2F7',
                      color: done ? '#FFFFFF' : colors.muted,
                      display: 'grid',
                      placeItems: 'center',
                      fontWeight: 900,
                    }}
                  >
                    {done ? '✓' : index + 1}
                  </div>
                  <div style={{fontSize: compact ? 22 : 28, fontWeight: 900}}>{label}</div>
                </div>
              );
            },
          )}
        </div>

        <div
          style={{
            marginTop: 'auto',
            background: colors.surface,
            border: `2px solid #A8E7D9`,
            borderRadius: 24,
            padding: 24,
          }}
        >
          <div style={{fontSize: compact ? 23 : 30, fontWeight: 950}}>Generated artifact</div>
          <div style={{fontSize: compact ? 16 : 20, color: colors.muted, marginTop: 8}}>
            mobilecode_projects/agent_snake/index.html
          </div>
          <div style={{display: 'flex', gap: 12, marginTop: 20, flexWrap: 'wrap'}}>
            <span style={pill('Code', 'blue')}>Code</span>
            <span style={pill('Preview', 'purple')}>Preview</span>
            <span style={pill('Publish', 'mint')}>Publish</span>
          </div>
        </div>
      </div>
    </div>
  );
};

const Headline = ({
  eyebrow,
  title,
  body,
  frame,
  from,
  align = 'left',
}: {
  eyebrow: string;
  title: string;
  body: string;
  frame: number;
  from: number;
  align?: 'left' | 'center';
}) => (
  <div style={{textAlign: align}}>
    <div
      style={{
        transform: `translateY(${lineReveal(frame, from)}px)`,
        opacity: interpolate(frame, [from, from + 18], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        }),
        fontSize: 24,
        fontWeight: 950,
        color: colors.blue,
        letterSpacing: 0,
        textTransform: 'uppercase',
      }}
    >
      {eyebrow}
    </div>
    <div
      style={{
        transform: `translateY(${lineReveal(frame, from + 10)}px)`,
        opacity: interpolate(frame, [from + 10, from + 34], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        }),
        fontSize: align === 'center' ? 78 : 72,
        lineHeight: 0.96,
        fontWeight: 1000,
        marginTop: 18,
        maxWidth: 820,
        marginLeft: align === 'center' ? 'auto' : 0,
        marginRight: align === 'center' ? 'auto' : 0,
      }}
    >
      {title}
    </div>
    <div
      style={{
        transform: `translateY(${lineReveal(frame, from + 22)}px)`,
        opacity: interpolate(frame, [from + 22, from + 48], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        }),
        fontSize: 30,
        lineHeight: 1.35,
        color: colors.muted,
        marginTop: 28,
        maxWidth: 760,
        marginLeft: align === 'center' ? 'auto' : 0,
        marginRight: align === 'center' ? 'auto' : 0,
      }}
    >
      {body}
    </div>
  </div>
);

const FeatureCard = ({
  title,
  body,
  tint,
  delay,
}: {
  title: string;
  body: string;
  tint: 'blue' | 'mint' | 'purple' | 'amber';
  delay: number;
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [delay, delay + 24], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const y = interpolate(frame, [delay, delay + 24], [36, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const tintColor = colors[tint];
  const soft = {
    blue: '#E9EEFF',
    mint: colors.mintSoft,
    purple: colors.purpleSoft,
    amber: colors.amberSoft,
  }[tint];
  return (
    <div
      style={{
        transform: `translateY(${y}px)`,
        opacity,
        background: colors.surface,
        border: `2px solid ${colors.border}`,
        borderRadius: 26,
        padding: 30,
        minHeight: 180,
      }}
    >
      <div
        style={{
          width: 52,
          height: 52,
          borderRadius: 17,
          background: soft,
          color: tintColor,
          display: 'grid',
          placeItems: 'center',
          fontSize: 30,
          fontWeight: 1000,
          marginBottom: 22,
        }}
      >
        ◆
      </div>
      <div style={{fontSize: 30, fontWeight: 950}}>{title}</div>
      <div style={{fontSize: 22, lineHeight: 1.35, color: colors.muted, marginTop: 12}}>
        {body}
      </div>
    </div>
  );
};

const RecordingReel = ({frame, isWide}: {frame: number; isWide: boolean}) => {
  if (enabledRecordings.length === 0) {
    return null;
  }

  const localFrame = frame >= scenes.artifact.from ? frame - scenes.artifact.from : frame;
  const slotLength = Math.max(1, Math.floor(scenes.artifact.duration / enabledRecordings.length));
  const activeIndex = Math.min(enabledRecordings.length - 1, Math.floor(localFrame / slotLength));
  const activeClip = enabledRecordings[activeIndex] ?? enabledRecordings[0];

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: isWide ? '0.9fr 1.1fr' : '1fr',
        gap: 28,
        alignItems: 'center',
      }}
    >
      <div
        style={{
          width: isWide ? 420 : 620,
          height: isWide ? 746 : 980,
          borderRadius: isWide ? 42 : 52,
          padding: isWide ? 18 : 24,
          background: colors.dark,
          boxShadow: '0 32px 90px rgba(11, 16, 32, 0.24)',
          justifySelf: 'center',
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            borderRadius: isWide ? 30 : 38,
            overflow: 'hidden',
            background: colors.bg,
          }}
        >
          <OffthreadVideo
            muted
            src={staticFile(activeClip.file)}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
            }}
          />
        </div>
      </div>
      <div style={{...stackBase, gap: 18}}>
        <div style={{fontSize: isWide ? 44 : 40, fontWeight: 1000, lineHeight: 1}}>
          {activeClip.title}
        </div>
        <div style={{fontSize: isWide ? 26 : 24, color: colors.muted, lineHeight: 1.35}}>
          {activeClip.caption}
        </div>
        <div style={{display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 18}}>
          {enabledRecordings.map((clip, index) => (
            <span
              key={clip.id}
              style={{
                ...pill(`${index + 1}. ${clip.title}`, index === activeIndex ? 'blue' : 'dark'),
                fontSize: 18,
              }}
            >
              {index + 1}. {clip.title}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
};

const HookScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const phoneScale = spring({frame, fps, config: {damping: 18, stiffness: 120}});
  const isWide = format === 'wide';
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '86px 90px' : '95px 72px',
          display: 'grid',
          gridTemplateColumns: isWide ? '1.15fr 0.85fr' : '1fr',
          alignItems: 'center',
          gap: 56,
        }}
      >
        <div>
          <Headline
            eyebrow="MobileCode"
            title="Not a remote IDE skin."
            body="A real AI coding harness that keeps the control loop, files, previews, runtime state, and shipping actions on the phone."
            frame={frame}
            from={12}
          />
          <div style={{display: 'flex', gap: 18, marginTop: 48, flexWrap: 'wrap'}}>
            <span style={pill('Phone-native harness', 'blue')}>Phone-native harness</span>
            <span style={pill('Remote model optional', 'mint')}>Remote model optional</span>
          </div>
        </div>
        <div
          style={{
            transform: `scale(${0.86 + phoneScale * 0.14}) rotate(${isWide ? -2 : 0}deg)`,
            justifySelf: 'center',
            display: isWide ? 'block' : 'none',
          }}
        >
          <PhoneMock progress={0.28} compact />
        </div>
      </div>
    </Shell>
  );
};

const TraceScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const p = sceneProgress(frame, scenes.trace.from, scenes.trace.duration);
  const isWide = format === 'wide';
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '70px 90px' : '76px 72px',
          display: 'grid',
          gridTemplateColumns: isWide ? '0.92fr 1.08fr' : '1fr',
          alignItems: 'center',
          gap: 62,
        }}
      >
        <PhoneMock progress={p} compact={isWide} />
        <div>
          <Headline
            eyebrow="Agent loop"
            title="The coding steps are visible."
            body="Parse intent, choose tools, call the model, write files, and preview results without hiding the harness behind a cloud session."
            frame={frame}
            from={scenes.trace.from + 8}
          />
        </div>
      </div>
    </Shell>
  );
};

const ArtifactScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const isWide = format === 'wide';
  const hasRecordings = enabledRecordings.length > 0;
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '90px' : '92px 72px',
          display: 'grid',
          gridTemplateRows: isWide ? 'auto 1fr' : 'auto 1fr',
          gap: 48,
        }}
      >
        <Headline
          eyebrow="Generated artifact"
          title="A file you can inspect, preview, open, and publish."
          body="MobileCode makes generated code tangible on the phone instead of leaving it as chat text."
          frame={frame}
          from={scenes.artifact.from + 8}
          align={isWide ? 'center' : 'left'}
        />
        {hasRecordings ? (
          <RecordingReel frame={frame} isWide={isWide} />
        ) : (
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: isWide ? 'repeat(4, 1fr)' : '1fr',
              gap: 26,
              alignContent: 'center',
            }}
          >
            <FeatureCard title="Code file" body="Open the generated HTML and copy the local path." tint="blue" delay={scenes.artifact.from + 50} />
            <FeatureCard title="Web preview" body="Check the result in WebView before publishing." tint="purple" delay={scenes.artifact.from + 65} />
            <FeatureCard title="Browser open" body="Open the same page in the phone's browser." tint="amber" delay={scenes.artifact.from + 80} />
            <FeatureCard title="Pages publish" body="Turn local HTML into a shareable GitHub Pages link." tint="mint" delay={scenes.artifact.from + 95} />
          </div>
        )}
      </div>
    </Shell>
  );
};

const RuntimeScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const isWide = format === 'wide';
  const providers = [
    ['WebViewOnly', 'Preview when shell is unavailable', 'mint'],
    ['MobileCode Helper', 'Foreground service for controlled execution', 'blue'],
    ['External Termux', 'Fallback shell and tools', 'amber'],
    ['Cloud Runtime', 'Heavy builds later', 'purple'],
  ] as const;
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '86px 110px' : '110px 74px',
          display: 'grid',
          gridTemplateColumns: isWide ? '0.95fr 1.05fr' : '1fr',
          gap: 54,
          alignItems: 'center',
        }}
      >
        <Headline
          eyebrow="RuntimeProvider"
          title="One interface. Many execution paths."
          body="The UI talks to RuntimeManager, then gracefully routes work through Helper, Termux, Cloud, or WebView-only mode."
          frame={frame}
          from={scenes.runtime.from + 8}
        />
        <div style={{...stackBase, gap: 24}}>
          {providers.map(([title, body, tint], index) => (
            <FeatureCard
              key={title}
              title={title}
              body={body}
              tint={tint}
              delay={scenes.runtime.from + 40 + index * 14}
            />
          ))}
        </div>
      </div>
    </Shell>
  );
};

const GithubScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const isWide = format === 'wide';
  const cards = [
    ['Public repo search', 'Any GitHub repo can be discovered without forcing login.', 'blue'],
    ['Owner repo management', 'Your token unlocks create, commit, Pages, and Actions.', 'mint'],
    ['Repo chat binding', 'Talk to MobileCode with a specific repo context.', 'purple'],
    ['Release assets', 'Find APK, zip, and artifacts from GitHub surfaces.', 'amber'],
  ] as const;
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '82px 92px' : '90px 72px',
          display: 'grid',
          gridTemplateRows: 'auto 1fr',
          gap: 44,
        }}
      >
        <Headline
          eyebrow="GitHub-first workspace"
          title="The phone stays light. GitHub does the heavy lifting."
          body="Repo Hub combines public discovery with token-gated management, Pages publishing, Actions runs, and artifact download."
          frame={frame}
          from={scenes.github.from + 8}
          align={isWide ? 'center' : 'left'}
        />
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: isWide ? 'repeat(4, 1fr)' : '1fr',
            gap: 24,
            alignContent: 'center',
          }}
        >
          {cards.map(([title, body, tint], index) => (
            <FeatureCard
              key={title}
              title={title}
              body={body}
              tint={tint}
              delay={scenes.github.from + 48 + index * 16}
            />
          ))}
        </div>
      </div>
    </Shell>
  );
};

const ProofScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const isWide = format === 'wide';
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '86px 112px' : '120px 78px',
          display: 'grid',
          gridTemplateColumns: isWide ? '1fr 1fr' : '1fr',
          gap: 48,
          alignItems: 'center',
        }}
      >
        <div>
          <Headline
            eyebrow="Release proof"
            title="CI green. APK ready. Pages live."
            body="The product loop is backed by reproducible checks and a public release artifact."
            frame={frame}
            from={scenes.proof.from + 8}
          />
          <div style={{display: 'flex', gap: 18, marginTop: 46, flexWrap: 'wrap'}}>
            <span style={pill('v0.1.24+43', 'dark')}>v0.1.24+43</span>
            <span style={pill('Android smoke passed', 'mint')}>Android smoke passed</span>
          </div>
        </div>
        <div style={{...stackBase, gap: 24}}>
          {[
            ['Mobile Runtime CI', 'passed'],
            ['Build Android APK', 'passed'],
            ['Android App Smoke Test', 'passed'],
            ['GitHub Pages demo', 'live'],
          ].map(([title, status], index) => (
            <div
              key={title}
              style={{
                opacity: interpolate(frame, [scenes.proof.from + 44 + index * 14, scenes.proof.from + 70 + index * 14], [0, 1], {
                  extrapolateLeft: 'clamp',
                  extrapolateRight: 'clamp',
                }),
                background: colors.surface,
                border: `2px solid #A8E7D9`,
                borderRadius: 26,
                padding: '28px 32px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: 22,
                fontSize: 30,
                fontWeight: 950,
              }}
            >
              <span>{title}</span>
              <span style={{...pill(status, 'mint'), fontSize: 22}}>✓ {status}</span>
            </div>
          ))}
        </div>
      </div>
    </Shell>
  );
};

const CloseScene = ({format}: {format: PromoFormat}) => {
  const frame = useCurrentFrame();
  const isWide = format === 'wide';
  const scale = interpolate(frame, [scenes.close.from, scenes.close.from + 80], [0.94, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  return (
    <Shell format={format}>
      <div
        style={{
          position: 'absolute',
          inset: isWide ? '86px 120px' : '150px 82px',
          display: 'grid',
          placeItems: 'center',
          textAlign: 'center',
        }}
      >
        <div style={{transform: `scale(${scale})`}}>
          <div
            style={{
              width: 110,
              height: 110,
              borderRadius: 34,
              background: colors.blue,
              color: '#FFFFFF',
              display: 'grid',
              placeItems: 'center',
              fontSize: 64,
              fontWeight: 1000,
              margin: '0 auto 36px',
              boxShadow: '0 24px 70px rgba(37, 85, 255, 0.28)',
            }}
          >
            M
          </div>
          <div style={{fontSize: isWide ? 96 : 92, lineHeight: 0.94, fontWeight: 1000}}>
            MobileCode
          </div>
          <div
            style={{
              fontSize: isWide ? 42 : 38,
              color: colors.muted,
              maxWidth: 960,
              lineHeight: 1.25,
              margin: '34px auto 0',
            }}
          >
            Phone-native AI coding harness.
            <br />
            Build, preview, publish from your phone.
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'center',
              gap: 18,
              flexWrap: 'wrap',
              marginTop: 48,
            }}
          >
            <span style={pill('Download APK', 'blue')}>Download APK</span>
            <span style={pill('Open Demo Lab', 'mint')}>Open Demo Lab</span>
            <span style={pill('GitHub Pages', 'purple')}>GitHub Pages</span>
          </div>
        </div>
      </div>
    </Shell>
  );
};

const WideReadmeComposition = () => {
  const frame = useCurrentFrame();
  const opacity = fadeInOut(frame, 0, 420);
  const p = sceneProgress(frame, 0, 420);
  return (
    <Shell format="wide">
      <div
        style={{
          position: 'absolute',
          inset: '70px 90px',
          display: 'grid',
          gridTemplateColumns: '0.92fr 1.08fr',
          gap: 76,
          alignItems: 'center',
          opacity,
        }}
      >
        <div style={{transform: `translateY(${interpolate(p, [0, 1], [30, -18])}px)`}}>
          <PhoneMock progress={p} compact />
        </div>
        <div>
          <Headline
            eyebrow="MobileCode"
            title="The AI coding harness runs on your phone."
            body="Remote model optional. Local agent trace, files, WebView preview, RuntimeProvider routing, GitHub Pages, and Actions artifacts."
            frame={frame}
            from={20}
          />
          <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18, marginTop: 46}}>
            <span style={pill('Phone-native harness', 'blue')}>Phone-native harness</span>
            <span style={pill('GitHub-first shipping', 'mint')}>GitHub-first shipping</span>
            <span style={pill('RuntimeProvider', 'purple')}>RuntimeProvider</span>
            <span style={pill('v0.1.24 APK', 'amber')}>v0.1.24 APK</span>
          </div>
        </div>
      </div>
    </Shell>
  );
};

export const MobileCodePromo = ({format}: PromoProps) => {
  const frame = useCurrentFrame();

  if (format === 'wide') {
    return <WideReadmeComposition />;
  }

  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Sequence from={scenes.hook.from} durationInFrames={scenes.hook.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.hook.from, scenes.hook.duration)}}>
          <HookScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.trace.from} durationInFrames={scenes.trace.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.trace.from, scenes.trace.duration)}}>
          <TraceScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.artifact.from} durationInFrames={scenes.artifact.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.artifact.from, scenes.artifact.duration)}}>
          <ArtifactScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.runtime.from} durationInFrames={scenes.runtime.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.runtime.from, scenes.runtime.duration)}}>
          <RuntimeScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.github.from} durationInFrames={scenes.github.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.github.from, scenes.github.duration)}}>
          <GithubScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.proof.from} durationInFrames={scenes.proof.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.proof.from, scenes.proof.duration)}}>
          <ProofScene format={format} />
        </div>
      </Sequence>
      <Sequence from={scenes.close.from} durationInFrames={scenes.close.duration}>
        <div style={{opacity: fadeInOut(frame, scenes.close.from, scenes.close.duration)}}>
          <CloseScene format={format} />
        </div>
      </Sequence>
    </AbsoluteFill>
  );
};
