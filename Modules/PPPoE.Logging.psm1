
# PPPoE.Logging.psm1 - banners & helpers

Set-StrictMode -Version 3.0

function Show-Banner {
@"
=====================================================
 PPPoE Diagnostic Toolkit (v11) - ASCII Transcript
=====================================================
"@
}

# Privacy helpers (ON = redacted; Evidence = fuller output)
$script:_PrivacyMode = 'On'
function Set-PrivacyMode { param([ValidateSet('On','Evidence')] [string]$Mode = 'On') $script:_PrivacyMode = $Mode }

function Hide-IPv4Sensitive {
  param([string]$IPv4)
  if ($script:_PrivacyMode -eq 'Evidence') { return $IPv4 }
  if (-not $IPv4) { return $null }
  $p = $IPv4.Split('.')
  if ($p.Count -ne 4) { return $IPv4 }
  return ("{0}.{1}.x.x" -f $p[0], $p[1])
}

function Hide-MacAddress {
  param([string]$Mac)
  if ($script:_PrivacyMode -eq 'Evidence') { return $Mac }
  if (-not $Mac) { return $null }
  # 00-E0-xx-xx-xx-xx style
  return ($Mac -replace '(?i)^([0-9A-F]{2}-[0-9A-F]{2})-([0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2})$','$1-xx-xx-xx-xx')
}

function Get-IPv4LogDescription {
  param([string]$IPv4)
  try {
    $cls = Get-IpClass -IPv4 $IPv4
  } catch { $cls = 'UNKNOWN' }
  if ($script:_PrivacyMode -eq 'Evidence') {
    return "$cls ($IPv4)"
  } else {
    return "$cls ($(Hide-IPv4Sensitive $IPv4))"
  }
}

function Protect-LogText {
  param([string]$Text)
  if ($script:_PrivacyMode -eq 'Evidence') { return $Text }
  if (-not $Text) { return $Text }
  $t = $Text
  # Redact emails
  $t = ($t -replace '(?i)\b[0-9A-Z._%+-]+@[0-9A-Z.-]+\.[A-Z]{2,}\b','[redacted-email]')
  # Redact DOMAIN\\User patterns
  $t = ($t -replace '(?i)\b[0-9A-Z._-]+\\[0-9A-Z._-]+\b','[redacted-user]')
  # Redact explicit username/password key-value snippets
  $t = ($t -replace '(?i)\buser(name)?\s*[:=]\s*\S+','user:[redacted]')
  $t = ($t -replace '(?i)\bpassword\s*[:=]\s*\S+','password:[redacted]')
  # Redact MAC addresses similar to Hide-MacAddress pattern
  $t = ($t -replace '(?i)\b([0-9A-F]{2}-[0-9A-F]{2})-([0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2})\b','$1-xx-xx-xx-xx')
  return $t
}

Export-ModuleMember -Function *

