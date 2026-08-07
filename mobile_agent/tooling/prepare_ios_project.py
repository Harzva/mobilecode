from __future__ import annotations

import plistlib
from pathlib import Path


MICROPHONE_USAGE = (
    'MobileCode uses the microphone to turn spoken coding instructions into chat prompts.'
)
SPEECH_RECOGNITION_USAGE = (
    'MobileCode uses speech recognition to send voice coding prompts.'
)


def prepare(plist: Path) -> None:
    """Write privacy usage descriptions into the root Info.plist dictionary."""
    document = plistlib.loads(plist.read_bytes())
    if not isinstance(document, dict):
        raise ValueError(f'Expected a dictionary at the root of {plist}.')

    document['NSMicrophoneUsageDescription'] = MICROPHONE_USAGE
    document['NSSpeechRecognitionUsageDescription'] = SPEECH_RECOGNITION_USAGE
    plist.write_bytes(
        plistlib.dumps(
            document,
            fmt=plistlib.FMT_XML,
            sort_keys=False,
        )
    )


def main() -> None:
    prepare(Path('ios/Runner/Info.plist'))


if __name__ == '__main__':
    main()
