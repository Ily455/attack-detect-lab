$TranscriptDir = "/var/log/pwsh_transcripts"
if (-not (Test-Path $TranscriptDir)) {
    New-Item -ItemType Directory -Path $TranscriptDir | Out-Null
}
$TranscriptFile = "$TranscriptDir/$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_$PID.log"
Start-Transcript -Path $TranscriptFile -Append | Out-Null
