param(
  [string]$Namespace = "loadtest",
  [string]$JobName = "k6-loadtest"
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$k6Dir = Join-Path $root '..' | Join-Path -ChildPath 'k6'
$cfgDir = Join-Path $root '..' | Join-Path -ChildPath 'config'
$k8sDir = Join-Path $root '..' | Join-Path -ChildPath 'k8s'

Write-Host "Ensuring namespace '$Namespace' exists..."
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Creating/updating ConfigMap 'k6-test-files' from k6/test.js and config/endpoints.json..."
kubectl -n $Namespace create configmap k6-test-files `
  --from-file=(Join-Path $k6Dir 'test.js') `
  --from-file=(Join-Path $cfgDir 'endpoints.json') `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Applying Job manifest..."
kubectl -n $Namespace apply -f (Join-Path $k8sDir 'job.yaml')

Write-Host "Job applied. Pods:"
kubectl -n $Namespace get pods -l job-name=$JobName

Write-Host "To follow logs: kubectl -n $Namespace logs -f job/$JobName"


