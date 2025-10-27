param(
  [string]$InputFile = "C:\Users\user\Desktop\Projects\Basuco\k8\loadtest\config\ps1s.txt",
  [string]$OutputFile = "C:\Users\user\Desktop\Projects\Basuco\k8\loadtest\config\endpoints.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputFile)) { throw "Input file not found: $InputFile" }

$raw = Get-Content -Raw -LiteralPath $InputFile

$sequence = @()

# Prefer parsing PowerShell Invoke-* requests; fallback to curl only if not present
if ($raw -match 'Invoke-(WebRequest|RestMethod)\s') {
  $requests = [regex]::Split($raw, '(?ms)Invoke-(?:WebRequest|RestMethod)\s+') | Where-Object { $_.Trim() -ne '' }
  foreach ($p in $requests) {
    # URI
    $url = $null
    $um = [regex]::Match($p, '-Uri\s+"(?<u>[^\"]+)"')
    if (-not $um.Success) { $um = [regex]::Match($p, "-Uri\s+'(?<u>[^']+)'") }
    if ($um.Success) { $url = $um.Groups['u'].Value }
    if (-not $url) { continue }

    # Filter base host
    if ($url -notmatch 'staging\.basuco\.eu') { continue }

    # Method
    $method = 'GET'
    $mm = [regex]::Match($p, '-Method\s+"(?<m>[A-Za-z]+)"')
    if (-not $mm.Success) { $mm = [regex]::Match($p, "-Method\s+'(?<m>[A-Za-z]+)'") }
    if ($mm.Success) { $method = $mm.Groups['m'].Value.ToUpperInvariant() }

    # Headers hashtable
    $headers = @{}
    $hm = [regex]::Match($p, '-Headers\s+(?<h>@\{[\s\S]*?\})')
    if ($hm.Success) {
      $hlit = $hm.Groups['h'].Value
      try { $headers = Invoke-Expression $hlit } catch {}
    }

    # ContentType param
    $ct = $null
    $ctm = [regex]::Match($p, '-ContentType\s+"(?<ct>[^\"]+)"')
    if (-not $ctm.Success) { $ctm = [regex]::Match($p, "-ContentType\s+'(?<ct>[^']+)'") }
    if ($ctm.Success) { $ct = $ctm.Groups['ct'].Value }
    if ($ct) { $headers['Content-Type'] = $ct }

    # Body: robustly parse quoted PS string honoring backtick escapes
    $body = $null
    $bsm = [regex]::Match($p, '-Body\s+(?<q>["''])')
    if ($bsm.Success) {
      $q = $bsm.Groups['q'].Value
      $start = $bsm.Index + $bsm.Length
      $text = $p.Substring($start)
      $sb = New-Object System.Text.StringBuilder
      $escaped = $false
      foreach ($ch in $text.ToCharArray()) {
        if ($escaped) { [void]$sb.Append($ch); $escaped = $false; continue }
        if ($ch -eq '`') { $escaped = $true; continue }
        if ($ch -eq $q) { break }
        [void]$sb.Append($ch)
      }
      $body = $sb.ToString().Trim()
      # Drop trailing Windows command chaining ampersand
      $body = ($body -replace '\s*&\s*$', '').Trim()
      # If looks like JSON, try parse (including double-encoded case)
      if ($body -match '^(\s*\{|\s*\[|\s*"\{|\s*"\[)') {
        $parsed = $null
        try { $parsed = $body | ConvertFrom-Json -ErrorAction Stop } catch {}
        if ($parsed -is [string] -and ($parsed -match '^(\s*\{|\s*\[)')) {
          try { $parsed2 = $parsed | ConvertFrom-Json -ErrorAction Stop; if ($parsed2) { $parsed = $parsed2 } } catch {}
        }
        if ($parsed) { $body = $parsed }
      }
    }

    $sequence += [pscustomobject]@{ url = $url; method = $method; headers = $headers; body = $body }
  }
} else {
  # Normalize Windows caret continuations and '&' chaining
  $normalized = $raw -replace "\r?\n\s*&\s*", "`n"
  $normalized = $normalized -replace "\s*\^\r?\n", " "

  # Split by 'curl ' boundaries while keeping order
  $parts = ($normalized -split "(?ms)\bcurl\s+" | Where-Object { $_.Trim() -ne '' })

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

  # Sanitize caret escapes inside URL (e.g., "%^20" -> "%20")
  $url = $url `
    -replace '\^\&','&' `
    -replace '\^\?','?' `
    -replace '\^=','=' `
    -replace '\^/','/' `
    -replace '\^',''

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

  # Body: capture everything after data flags up to next option or end
  $body = $null
  $b = [regex]::Match($p, '(?ms)(?:--data(?:-raw|-binary|-urlencode)?|-d)\s+(?<b>.+?)(?=\s+-[A-Za-z-]+\b|$)')
  if ($b.Success) {
    $body = $b.Groups['b'].Value.Trim()
    # Drop trailing Windows command chaining ampersand
    $body = ($body -replace '\s*&\s*$', '').Trim()
    # Strip surrounding quotes if present (^"...^" or "...")
    if ($body -match '^\^".*\^"$') { $body = $body.Substring(2, $body.Length-4) }
    elseif ($body -match '^".*"$') { $body = $body.Substring(1, $body.Length-2) }
    # Unescape common Windows caret-escapes
    $body = $body `
      -replace '\^"','"' `
      -replace '\^\{','{' `
      -replace '\^\}','}' `
      -replace '\^%','%' `
      -replace '\^\&','&' `
      -replace '\^@','@' `
      -replace '\^<','<' `
      -replace '\^>','>' `
      -replace '\^\^','^' `
      -replace '\^\\','\\'

    # If body looks like JSON, parse it so it is stored as an object
    if ($body -match '^(\s*\{|\s*\[|\s*"\{|\s*"\[)') {
      $parsed = $null
      try {
        $parsed = $body | ConvertFrom-Json -ErrorAction Stop
      } catch {
        # ignore, will try other heuristics
      }
      # If first parse yielded a string that looks like JSON, parse again
      if ($parsed -is [string] -and ($parsed -match '^(\s*\{|\s*\[)')) {
        try {
          $parsed2 = $parsed | ConvertFrom-Json -ErrorAction Stop
          if ($parsed2) { $parsed = $parsed2 }
        } catch {}
      }
      if ($parsed) { $body = $parsed }
    }
  }

  $sequence += [pscustomobject]@{
    url = $url
    method = $method
    headers = $headers
    body = $body
  }
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

$json = $base | ConvertTo-Json -Depth 50
Set-Content -LiteralPath $outPath -Value $json
Write-Host "Sequence written to $outPath (steps: $($sequence.Count))"


