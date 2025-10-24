### K8s Load/Stress Testing Scaffold (k6)

This folder contains a ready-to-use scaffold for running k6 load/stress tests locally (Docker) and in Kubernetes (Job). You can plug in your endpoints and target users later.

### Structure
- `k6/test.js`: k6 test template reading endpoints from a JSON file and env vars
- `config/endpoints.json`: placeholder for your endpoints; edit this later
- `k8s/job.yaml`: Kubernetes Job that runs k6 using the files above
- `scripts/run-local.ps1` / `scripts/run-local.sh`: Run the test locally via Docker (Windows/macOS/Linux)
- `scripts/deploy.ps1` / `scripts/deploy.sh`: Create/update ConfigMap and Job in your cluster (Windows/macOS/Linux)
- `scripts/cleanup.ps1` / `scripts/cleanup.sh`: Remove Job/ConfigMap and (optionally) namespace (Windows/macOS/Linux)
- `scripts/curl-to-sequence.ps1` / `scripts/curl-to-sequence.sh`: Convert a caret-escaped or standard curl chain into `sequence` steps for k6

### Quick start (local via Docker)
Prereqs: Docker Desktop.

1) Edit `config/endpoints.json` with your endpoints.
2) Run (Windows):

```powershell
cd ./loadtest
./scripts/run-local.ps1 -BaseUrl "https://your.api" -Vus 10 -Duration "30s"
```

2) Run (macOS/Linux):

```bash
cd ./loadtest
bash ./scripts/run-local.sh --base-url https://your.api --vus 10 --duration 30s
```

Optional flags: `-StagesJson '[{"duration":"30s","target":10}]'` or `--stages-json '[{"duration":"30s","target":10}]'` instead of `-Vus/-Duration`.

To import a pasted curl chain into the test sequence:

- Windows (caret-escaped supported):
```powershell
cd ./loadtest/scripts
Set-Content -Path .\input-curl.txt -Value @'
<paste your caret-escaped curl commands here>
'@
./curl-to-sequence.ps1 -InputFile .\input-curl.txt -OutputFile ..\config\endpoints.json
```

- macOS/Linux (standard quotes supported, Windows caret-escaped also handled):
```bash
cd ./loadtest/scripts
printf "%s\n" "<paste your curl commands here>" > ./input-curl.txt
bash ./curl-to-sequence.sh --input ./input-curl.txt --output ../config/endpoints.json
```

Then run the local script as usual. You can adjust per-step sleep via `--sleep`.

### Run in Kubernetes
Prereqs: `kubectl` access to the cluster and a namespace (default: `loadtest`).

1) Edit `config/endpoints.json` with your endpoints.
2) (Optional) Edit `k8s/job.yaml` to set defaults (e.g., `BASE_URL`, `VUS`, `DURATION`).
3) Deploy:

```powershell
cd ./loadtest
./scripts/deploy.ps1 -Namespace loadtest
```

or (macOS/Linux):

```bash
cd ./loadtest
bash ./scripts/deploy.sh --namespace loadtest
```

This will:
- Create/update ConfigMap `k6-test-files` from `k6/test.js` and `config/endpoints.json`
- Apply Job `k6-loadtest`

4) Observe logs:

```powershell
$ns = "loadtest"
kubectl -n $ns get pods -l job-name=k6-loadtest
kubectl -n $ns logs -f job/k6-loadtest
```

5) Cleanup:

```powershell
./scripts/cleanup.ps1 -Namespace loadtest
```

or (macOS/Linux):

```bash
bash ./scripts/cleanup.sh --namespace loadtest
```

### Configuration
- **Endpoints file**: `config/endpoints.json` (mounted at `/config/endpoints.json` in the Job)
- **Env vars** (local and K8s):
  - `BASE_URL`: prefix for endpoints (e.g., `https://api.example.com`)
  - `VUS`, `DURATION`: basic load settings (ignored if `STAGES_JSON` is provided)
  - `STAGES_JSON`: k6 stages JSON string for ramping patterns
  - `SLEEP`: seconds to sleep between iterations (default `1`)
  - `ENDPOINTS_FILE`: path to endpoints JSON (default `/config/endpoints.json`)

### Next steps
- Provide your endpoints and desired user load; update `config/endpoints.json` and/or environment variables accordingly.
- If you need auth or test data setup, extend `k6/test.js` accordingly or add init setup code.


