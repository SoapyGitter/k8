param(
  [string]$BaseUrl = "",
  [int]$Vus = 50,
  [string]$Duration = "30s",
  [string]$StagesJson = "",
  [double]$Sleep = 1,
  [string]$EndpointsFile = "",
  [string]$P95 = "800"
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $root '..')
$k6File = Join-Path $repoRoot 'k6/test.js'
$cfgFile = if ($EndpointsFile) { $EndpointsFile } else { Join-Path $repoRoot 'config/endpoints.json' }

if (-not (Test-Path $k6File)) { throw "k6 script not found at $k6File" }
if (-not (Test-Path $cfgFile)) { throw "Endpoints config not found at $cfgFile" }

$envArgs = @()
if ($BaseUrl) { $envArgs += "-e"; $envArgs += "BASE_URL=$BaseUrl" }
$envArgs += "-e"; $envArgs += "VUS=$Vus"
$envArgs += "-e"; $envArgs += "DURATION=$Duration"
$envArgs += "-e"; $envArgs += "SLEEP=$Sleep"
$envArgs += "-e"; $envArgs += "P95=$P95"
if ($StagesJson) { $envArgs += "-e"; $envArgs += "STAGES_JSON=$StagesJson" }
$envArgs += "-e"; $envArgs += "ENDPOINTS_FILE=/config/endpoints.json"

docker run --rm `
  $envArgs `
  -v "${k6File}:/scripts/test.js:ro" `
  -v "${cfgFile}:/config/endpoints.json:ro" `
  grafana/k6:latest run /scripts/test.js


