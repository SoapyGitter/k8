param(
  [string]$InputFile = "C:\Users\user\Desktop\Projects\Basuco\k8\loadtest\config\curls.txt",
  [string]$OutputFile = "C:\Users\user\Desktop\Projects\Basuco\k8\loadtest\config\endpoints.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputFile)) { throw "Input file not found: $InputFile" }

$raw = Get-Content -Raw -LiteralPath $InputFile

# Normalize Windows caret continuations and '&' chaining
$normalized = $raw -replace "\r?\n\s*&\s*", "`n"
$normalized = $normalized -replace "\s*\^\r?\n", " "

# Split by 'curl ' boundaries while keeping order
$parts = ($normalized -split "(?ms)\bcurl\s+" | Where-Object { $_.Trim() -ne '' })

$sequence = @()
foreach ($p in $parts) {
  # Extract URL (caret-escaped or plain quoted)
  $url = $null
  $urlMatch = [regex]::Match($p, '^\^"(?<url>.+?)\^"')
  if ($urlMatch.Success) {
    $url = ($urlMatch.Groups['url'].Value -replace '\^"','"' -replace '\^%','%')
  } else {
    $urlMatch2 = [regex]::Match($p, '^"(?<url>[^\"]+)"')
    if ($urlMatch2.Success) { $url = $urlMatch2.Groups['url'].Value }
  }
  if (-not $url) { continue }

  # Filter: include only URLs that contain the required base host
  if ($url -notmatch 'staging\.basuco\.eu') { continue }

  # Method
  $method = "GET"
  $m = [regex]::Match($p, '-X\s*\^"(?<m>[A-Z]+)\^"')
  if (-not $m.Success) { $m = [regex]::Match($p, '-X\s*"(?<m>[A-Z]+)"') }
  if ($m.Success) { $method = $m.Groups['m'].Value }

  # Headers (multiple -H "Key: Value")
  $headers = @{}
  $hMatches = [regex]::Matches($p, '-H\s*\^"(?<h>.+?)\^"')
  if ($hMatches.Count -eq 0) { $hMatches = [regex]::Matches($p, '-H\s*"(?<h>[^"]+)"') }
  foreach ($hm in $hMatches) {
    $hv = ($hm.Groups['h'].Value -replace '\^"','"' -replace '\^%','%')
    $idx = $hv.IndexOf(":")
    if ($idx -gt 0) {
      $k = $hv.Substring(0, $idx).Trim()
      $v = $hv.Substring($idx+1).Trim()
      $headers[$k] = $v
    }
  }

  # Cookies via -b "..." or caret-escaped
  $cookie = $null
  $cm = [regex]::Match($p, '-b\s*\^"(?<c>.+?)\^"')
  if (-not $cm.Success) { $cm = [regex]::Match($p, '-b\s*"(?<c>[^"]+)"') }
  if ($cm.Success) { $cookie = ($cm.Groups['c'].Value -replace '\^"','"' -replace '\^%','%') }
  if ($cookie) { $headers['Cookie'] = $cookie }

  # Body (--data-raw "...")
  $body = $null
  $b = [regex]::Match($p, '--data-raw\s*\^"(?<b>.*?)\^"', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $b.Success) { $b = [regex]::Match($p, '--data-raw\s*"(?<b>.*?)"', [System.Text.RegularExpressions.RegexOptions]::Singleline) }
  if ($b.Success) {
    $body = ($b.Groups['b'].Value -replace '\^"','"' -replace '\^%','%')
  }

  $sequence += [pscustomobject]@{
    url = $url
    method = $method
    headers = $headers
    body = $body
  }
}

# Load existing endpoints.json if present
$outPath = Resolve-Path -LiteralPath $OutputFile -ErrorAction SilentlyContinue
if (-not $outPath) { $outPath = $OutputFile }

$base = @{ baseUrl = ""; endpoints = @(); sequence = @() }
if (Test-Path $outPath) {
  try { $base = Get-Content -Raw -LiteralPath $outPath | ConvertFrom-Json } catch {}
}

if (-not $base) {
  $base = [pscustomobject]@{ baseUrl = ""; endpoints = @(); sequence = @() }
}

if ($base -is [hashtable]) {
  $base['sequence'] = $sequence
} elseif ($base.PSObject -and ($base.PSObject.Properties.Name -contains 'sequence')) {
  $base.sequence = $sequence
} else {
  $null = Add-Member -InputObject $base -NotePropertyName 'sequence' -NotePropertyValue $sequence -Force
}

$json = $base | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $outPath -Value $json
Write-Host "Sequence written to $outPath (steps: $($sequence.Count))"


