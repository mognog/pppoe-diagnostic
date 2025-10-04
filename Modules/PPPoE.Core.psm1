
# PPPoE.Core.psm1 - helpers, transcript & ASCII

Set-StrictMode -Version 3.0

function Start-AsciiTranscript {
  param([string]$Path)
  $global:_TranscriptPath = $Path
  $script:_TranscriptWriter = [System.IO.StreamWriter]::new($Path, $true, [System.Text.Encoding]::ASCII)
  $script:_TranscriptWriter.AutoFlush = $true
  Write-Log "Transcript started: $Path"
}

function Stop-AsciiTranscript {
  try {
    if ($script:_TranscriptWriter) { $script:_TranscriptWriter.Dispose() }
  } catch {}
}

function Write-Log {
  param([string]$Message)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[{0}] {1}" -f $ts, ($Message -replace '[^\x00-\x7F]', '?')
  if ($script:_TranscriptWriter) { $script:_TranscriptWriter.WriteLine($line) }
  Write-Host $line
}

function Write-Ok { param([string]$m) ; Write-Log "[OK] $m" }
function Write-Warn { param([string]$m) ; Write-Log "[WARN] $m" }
function Write-Err { param([string]$m) ; Write-Log "[FAIL] $m" }

function Test-PwshVersion7Plus {
  try {
    $v = $PSVersionTable.PSVersion
    return [bool]($v.Major -ge 7)
  } catch { return $false }
}

function Test-AsciiOnly {
  param([string]$text)
  return -not ($text -match '[^\x00-\x7F]')
}

function Test-PingHost {
  param(
    [Parameter(Mandatory=$true)][string]$TargetName,
    [int]$Count = 2,
    [int]$TimeoutMs = 1500,
    [int]$Ttl = 64,
    [int]$DelayMs = 50,
    [string]$Source = $null
  )
  try {
    $params = @{
      TargetName = $TargetName
      Count      = $Count
      TimeoutSeconds = [Math]::Ceiling($TimeoutMs/1000)
      TimeToLive = $Ttl
      Delay      = $DelayMs
      ErrorAction = 'Stop'
    }
    if ($Source) { $params['Source'] = $Source }
    $r = Test-Connection @params
    return $true
  } catch {
    return $false
  }
}

function Get-IpClass {
  param([string]$IPv4)
  if (-not $IPv4) { return 'NONE' }
  if ($IPv4.StartsWith('169.254.')) { return 'APIPA' }
  $oct = $IPv4.Split('.').ForEach([int])
  $i = ($oct[0] -shl 24) -bor ($oct[1] -shl 16) -bor ($oct[2] -shl 8) -bor $oct[3]

  # RFC1918
  if ($oct[0] -eq 10) { return 'PRIVATE' }
  if ($oct[0] -eq 172 -and $oct[1] -ge 16 -and $oct[1] -le 31) { return 'PRIVATE' }
  if ($oct[0] -eq 192 -and $oct[1] -eq 168) { return 'PRIVATE' }

  # CGNAT 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
  $start = (100 -shl 24) -bor (64 -shl 16)
  $end   = (100 -shl 24) -bor (127 -shl 16) -bor (255 -shl 8) -bor 255
  if ($i -ge $start -and $i -le $end) { return 'CGNAT' }

  return 'PUBLIC'
}

Export-ModuleMember -Function * -Alias *

