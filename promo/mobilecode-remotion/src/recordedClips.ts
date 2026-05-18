export type RecordedClip = {
  id: string;
  title: string;
  caption: string;
  file: string;
  enabled: boolean;
};

export const recordedClips: RecordedClip[] = [
  {
    id: 'chat-generate',
    title: 'Real phone run',
    caption: 'Prompt, trace, generated artifact, and preview on Android.',
    file: 'recordings/phone-chat-generate.mp4',
    enabled: false,
  },
  {
    id: 'github-pages',
    title: 'Pages publish',
    caption: 'Publish phone-generated HTML to GitHub Pages.',
    file: 'recordings/phone-github-pages.mp4',
    enabled: false,
  },
  {
    id: 'repo-hub',
    title: 'Repo Hub',
    caption: 'Search repos, bind workspace, inspect Actions, download artifacts.',
    file: 'recordings/phone-repo-hub.mp4',
    enabled: false,
  },
];
