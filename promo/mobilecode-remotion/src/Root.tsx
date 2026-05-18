import {Composition} from 'remotion';
import {MobileCodePromo} from './MobileCodePromo';
import {
  MobileCodePrincipleExplainer,
  principleDurationInFrames,
} from './MobileCodePrincipleExplainer';
import {MobileCodeShortTeaser, shortTeaserDurationInFrames} from './MobileCodeShortTeaser';

export const Root = () => {
  return (
    <>
      <Composition
        id="MobileCodeVertical"
        component={MobileCodePromo}
        durationInFrames={1260}
        fps={30}
        width={1080}
        height={1920}
        defaultProps={{format: 'vertical'}}
      />
      <Composition
        id="MobileCodeReadmeCover"
        component={MobileCodePromo}
        durationInFrames={420}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{format: 'wide'}}
      />
      <Composition
        id="MobileCodePrincipleExplainer"
        component={MobileCodePrincipleExplainer}
        durationInFrames={principleDurationInFrames}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="MobileCodeShortTeaser"
        component={MobileCodeShortTeaser}
        durationInFrames={shortTeaserDurationInFrames}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
