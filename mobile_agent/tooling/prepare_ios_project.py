from pathlib import Path


def _insert_plist_string(text: str, key: str, value: str) -> str:
    if f'<key>{key}</key>' in text:
        return text
    marker = '</dict>'
    return text.replace(
        marker,
        f'\t<key>{key}</key>\n\t<string>{value}</string>\n{marker}',
        1,
    )


def main() -> None:
    plist = Path('ios/Runner/Info.plist')
    text = plist.read_text()
    text = _insert_plist_string(
        text,
        'NSMicrophoneUsageDescription',
        'MobileCode uses the microphone to turn spoken coding instructions into chat prompts.',
    )
    text = _insert_plist_string(
        text,
        'NSSpeechRecognitionUsageDescription',
        'MobileCode uses speech recognition to send voice coding prompts.',
    )
    plist.write_text(text)


if __name__ == '__main__':
    main()
