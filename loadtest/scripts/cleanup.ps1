param(
  [string]$Namespace = "loadtest",
  [string]$JobName = "k6-loadtest",
  [switch]$DeleteNamespace
)

$ErrorActionPreference = 'Stop'

Write-Host "Deleting Job $JobName in '$Namespace'..."
kubectl -n $Namespace delete job $JobName --ignore-not-found

Write-Host "Deleting ConfigMap k6-test-files in '$Namespace'..."
kubectl -n $Namespace delete configmap k6-test-files --ignore-not-found

if ($DeleteNamespace) {
  Write-Host "Deleting namespace '$Namespace'..."
  kubectl delete namespace $Namespace --ignore-not-found
}


