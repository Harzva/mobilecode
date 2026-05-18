import React from 'react';
import {AbsoluteFill, Audio, Easing, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';

const fps = 30;
const sceneFrames = 150;

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
  dark: '#111827',
  softBlue: '#E9EEFF',
  softMint: '#EAF8F3',
  softPurple: '#F0ECFF',
};

const scenes = [
  {
    eyebrow: 'Not remote IDE',
    title: 'The harness runs on your phone.',
    subtitle: 'MobileCode 不是远程 IDE 外壳，而是真正运行在手机上的 AI coding harness。',
    chips: ['local files', 'tool trace', 'preview'],
  },
  {
    eyebrow: 'Runtime routing',
    title: 'Light local loop. Heavy work routed out.',
    subtitle: '手机负责生成、预览、解释，Helper、Termux、GitHub Actions 负责执行和构建。',
    chips: ['RuntimeProvider', 'Helper', 'GitHub Actions'],
  },
  {
    eyebrow: 'Ship from mobile',
    title: 'Prompt to page. Phone to GitHub.',
    subtitle: '生成 HTML，WebView 预览，一键发布 GitHub Pages，并得到可分享作品卡。',
    chips: ['WebView', 'GitHub Pages', 'release card'],
  },
] as const;

export const shortTeaserDurationInFrames = scenes.length * sceneFrames;

const reveal = (frame: number, delay = 0) =>
  interpolate(frame, [delay, delay + 24], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

const rise = (frame: number, delay = 0, distance = 34) =>
  interpolate(frame, [delay, delay + 30], [distance, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

const fade = (frame: number) => {
  const fadeIn = interpolate(frame, [0, 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const fadeOut = interpolate(frame, [sceneFrames - 20, sceneFrames], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return Math.min(fadeIn, fadeOut);
};

const MiniPhone = ({frame}: {frame: number}) => {
  const progress = interpolate(frame, [20, 130], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <div
      style={{
        width: 380,
        height: 690,
        borderRadius: 52,
        background: colors.dark,
        padding: 22,
        boxShadow: '0 34px 110px rgba(11, 16, 32, .32)',
        transform: `rotate(${interpolate(progress, [0, 1], [-2, 1])}deg)`,
      }}
    >
      <div
        style={{
          height: '100%',
          borderRadius: 34,
          background: colors.bg,
          padding: 24,
          display: 'grid',
          gap: 18,
          gridTemplateRows: 'auto 1fr auto',
        }}
      >
        <div>
          <div style={{fontSize: 28, fontWeight: 1000}}>MobileCode</div>
          <div style={{fontSize: 15, color: colors.muted, marginTop: 6, fontWeight: 800}}>
            phone-native harness
          </div>
        </div>
        <div style={{display: 'grid', gap: 12, alignContent: 'center'}}>
          {['Trace', 'Runtime', 'Preview', 'Publish'].map((label, index) => {
            const active = progress > index / 4;
            return (
              <div
                key={label}
                style={{
                  padding: 16,
                  borderRadius: 16,
                  border: `2px solid ${active ? '#A8E7D9' : colors.line}`,
                  background: active ? colors.softMint : colors.surface,
                  color: active ? colors.mint : colors.muted,
                  fontSize: 20,
                  fontWeight: 1000,
                }}
              >
                {active ? '✓ ' : '· '}
                {label}
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
            fontSize: 20,
            fontWeight: 1000,
          }}
        >
          Publish Pages
        </div>
      </div>
    </div>
  );
};

const Scene = ({scene, index}: {scene: (typeof scenes)[number]; index: number}) => {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [0, sceneFrames], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

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
          boxShadow: '0 30px 110px rgba(37, 85, 255, .14)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 96,
          display: 'grid',
          gridTemplateColumns: '1fr 430px',
          gap: 74,
          alignItems: 'center',
        }}
      >
        <div>
          <div
            style={{
              opacity: reveal(frame, 8),
              transform: `translateY(${rise(frame, 8, 28)}px)`,
              color: colors.blue,
              fontSize: 28,
              fontWeight: 1000,
              textTransform: 'uppercase',
            }}
          >
            {scene.eyebrow}
          </div>
          <h1
            style={{
              opacity: reveal(frame, 18),
              transform: `translateY(${rise(frame, 18, 34)}px)`,
              margin: '20px 0 0',
              fontSize: 88,
              lineHeight: 0.96,
              fontWeight: 1000,
              maxWidth: 980,
            }}
          >
            {scene.title}
          </h1>
          <div
            style={{
              opacity: reveal(frame, 42),
              transform: `translateY(${rise(frame, 42, 26)}px)`,
              marginTop: 42,
              display: 'flex',
              flexWrap: 'wrap',
              gap: 16,
            }}
          >
            {scene.chips.map((chip, chipIndex) => {
              const chipColors = [colors.softBlue, colors.softMint, colors.softPurple];
              const chipInk = [colors.blue, colors.mint, colors.purple];
              return (
                <span
                  key={chip}
                  style={{
                    padding: '14px 18px',
                    borderRadius: 16,
                    background: chipColors[chipIndex],
                    color: chipInk[chipIndex],
                    fontSize: 28,
                    fontWeight: 1000,
                    border: `2px solid ${chipInk[chipIndex]}33`,
                  }}
                >
                  {chip}
                </span>
              );
            })}
          </div>
        </div>
        <div style={{opacity: reveal(frame, 24), transform: `translateY(${rise(frame, 24, 36)}px)`}}>
          <MiniPhone frame={frame} />
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 120,
          right: 120,
          bottom: 96,
          display: 'grid',
          placeItems: 'center',
        }}
      >
        <div
          style={{
            maxWidth: 1250,
            padding: '18px 28px',
            borderRadius: 18,
            color: '#FFFFFF',
            background: 'rgba(11, 16, 32, .84)',
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
          left: 120,
          right: 120,
          bottom: 52,
          height: 8,
          borderRadius: 999,
          background: '#DBE5F6',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            width: `${((index + progress) / scenes.length) * 100}%`,
            height: '100%',
            background: colors.blue,
          }}
        />
      </div>
    </AbsoluteFill>
  );
};

export const MobileCodeShortTeaser = () => {
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Audio src={staticFile('audio/mobilecode-short-voiceover.wav')} volume={0.92} />
      {scenes.map((scene, index) => (
        <Sequence key={scene.eyebrow} from={index * sceneFrames} durationInFrames={sceneFrames}>
          <Scene scene={scene} index={index} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
