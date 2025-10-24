#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'USAGE'
Convert a file containing chained curl commands into sequence steps in endpoints.json

Usage:
  bash ./scripts/curl-to-sequence.sh [--input PATH] [--output PATH]

Defaults:
  --input  ./config/curls.txt
  --output ./config/endpoints.json
USAGE
}

input_file=""
output_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage; exit 0;
      ;;
    --input)
      input_file=${2:-}; shift 2;
      ;;
    --output)
      output_file=${2:-}; shift 2;
      ;;
    *)
      echo "Unknown option: $1" >&2; print_usage; exit 1;
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [[ -z "$input_file" ]]; then input_file="$repo_root/config/curls.txt"; fi
if [[ -z "$output_file" ]]; then output_file="$repo_root/config/endpoints.json"; fi

if [[ ! -f "$input_file" ]]; then
  echo "Input file not found: $input_file" >&2; exit 1;
fi

# Pick python interpreter
if command -v python3 >/dev/null 2>&1; then PYEXE=python3; 
elif command -v python >/dev/null 2>&1; then PYEXE=python; 
else echo "python3 or python not found in PATH" >&2; exit 1; fi

"$PYEXE" - "$input_file" "$output_file" <<'PY'
import json
import re
import sys
from pathlib import Path

inp = Path(sys.argv[1])
outp = Path(sys.argv[2])
raw = inp.read_text(encoding='utf-8')

# Normalize: remove shell chaining with '&' on newlines and caret continuations from Windows exports
normalized = re.sub(r"\r?\n\s*&\s*", "\n", raw)
normalized = re.sub(r"\s*\^\r?\n", " ", normalized)

# Split on 'curl ' boundaries preserving order
parts = [p for p in re.split(r"(?ms)\bcurl\s+", normalized) if p.strip()]

sequence = []
for p in parts:
    # URL
    url = None
    m1 = re.match(r'^\^"(?P<url>.+?)\^"', p)
    if m1:
        url = m1.group('url').replace('\^"', '"').replace('\^%', '%')
    else:
        m2 = re.match(r'^"(?P<url>[^\"]+)"', p)
        if m2:
            url = m2.group('url')
    if not url:
        continue

    # Filter base host (same as PS script)
    if not re.search(r'staging\.basuco\.eu', url):
        continue

    # Method
    method = 'GET'
    mm = re.search(r'-X\s*\^"(?P<m>[A-Z]+)\^"', p)
    if not mm:
        mm = re.search(r'-X\s*"(?P<m>[A-Z]+)"', p)
    if mm:
        method = mm.group('m')

    # Headers
    headers = {}
    hmatches = list(re.finditer(r'-H\s*\^"(?P<h>.+?)\^"', p))
    if not hmatches:
        hmatches = list(re.finditer(r'-H\s*"(?P<h>[^\"]+)"', p))
    for hm in hmatches:
        hv = hm.group('h').replace('\^"', '"').replace('\^%', '%')
        if ':' in hv:
            k, v = hv.split(':', 1)
            headers[k.strip()] = v.strip()

    # Cookies via -b
    cookie = None
    cm = re.search(r'-b\s*\^"(?P<c>.+?)\^"', p)
    if not cm:
        cm = re.search(r'-b\s*"(?P<c>[^\"]+)"', p)
    if cm:
        cookie = cm.group('c').replace('\^"', '"').replace('\^%', '%')
    if cookie:
        headers['Cookie'] = cookie

    # Body: capture after data flags up to next option or end
    body = None
    bm = re.search(r'(?:--data(?:-raw|-binary|-urlencode)?|-d)\s+(?P<b>.+?)(?=\s+-[A-Za-z-]+\b|$)', p, re.S | re.M)
    if bm:
        bval = bm.group('b').strip()
        # Strip surrounding quotes (^"...^" or "...")
        if bval.startswith('^"') and bval.endswith('^"'):
            bval = bval[2:-2]
        elif bval.startswith('"') and bval.endswith('"'):
            bval = bval[1:-1]
        # Unescape caret-escaped characters
        bval = (bval
                .replace('^"', '"')
                .replace('^{', '{')
                .replace('^}', '}')
                .replace('^%', '%')
                .replace('^&', '&')
                .replace('^@', '@')
                .replace('^<', '<')
                .replace('^>', '>')
                .replace('^^', '^'))
        body = bval

    sequence.append({
        'url': url,
        'method': method,
        'headers': headers,
        'body': body,
    })

# Merge into existing endpoints.json if present
base = { 'baseUrl': '', 'endpoints': [], 'sequence': [] }
if outp.exists():
    try:
        base = json.loads(outp.read_text(encoding='utf-8'))
    except Exception:
        pass

if isinstance(base, dict):
    base['sequence'] = sequence
else:
    base = { 'baseUrl': '', 'endpoints': [], 'sequence': sequence }

outp.write_text(json.dumps(base, ensure_ascii=False, indent=None), encoding='utf-8')
print(f"Sequence written to {outp} (steps: {len(sequence)})")
PY

if [[ ! -f "$output_file" ]]; then
  echo "Failed to create or update $output_file" >&2; exit 1;
fi


