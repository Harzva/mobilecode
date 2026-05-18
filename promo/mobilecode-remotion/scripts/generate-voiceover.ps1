param(
  [string]$VoiceName = "Microsoft Huihui Desktop",
  [int]$Rate = 5
)

Add-Type -AssemblyName System.Speech

$root = Split-Path -Parent $PSScriptRoot
$audioDir = Join-Path $root "public\audio"
New-Item -ItemType Directory -Force -Path $audioDir | Out-Null

function Save-Voiceover {
  param(
    [string]$Path,
    [string]$Text,
    [string]$VoiceName,
    [int]$Rate
  )

  $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  try {
    $synth.SelectVoice($VoiceName)
  } catch {
    $culture = New-Object System.Globalization.CultureInfo("zh-CN")
    $synth.SelectVoiceByHints(
      [System.Speech.Synthesis.VoiceGender]::Female,
      [System.Speech.Synthesis.VoiceAge]::Adult,
      0,
      $culture
    )
  }
  $synth.Rate = $Rate
  $synth.Volume = 96
  $synth.SetOutputToWaveFile($Path)
  $synth.Speak($Text)
  $synth.SetOutputToNull()
  $synth.Dispose()
}

$principleText = [System.IO.File]::ReadAllText(
  (Join-Path $PSScriptRoot "voiceover-principle.zh.txt"),
  [System.Text.Encoding]::UTF8
)

$shortText = [System.IO.File]::ReadAllText(
  (Join-Path $PSScriptRoot "voiceover-short.zh.txt"),
  [System.Text.Encoding]::UTF8
)

Save-Voiceover `
  -Path (Join-Path $audioDir "mobilecode-principle-voiceover.wav") `
  -Text $principleText `
  -VoiceName $VoiceName `
  -Rate $Rate

Save-Voiceover `
  -Path (Join-Path $audioDir "mobilecode-short-voiceover.wav") `
  -Text $shortText `
  -VoiceName $VoiceName `
  -Rate ($Rate + 1)

Write-Host "Generated voiceovers in $audioDir"
