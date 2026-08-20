#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Users/starkers/Projects/Zeroa"
cd "$PROJECT_ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed. Install Docker Desktop for Mac, then re-run." >&2
  exit 1
fi

read -r -p "GitHub Username (for ghcr.io): " GHCR_USERNAME
read -r -s -p "GitHub Token (PAT with read:packages): " GHCR_TOKEN; echo
read -r -s -p "Hugging Face Token: " HUGGING_FACE_TOKEN; echo

echo "Logging into GitHub Container Registry..."
echo -n "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin

echo "Pulling MLC packaging image..."
docker pull ghcr.io/mlc-ai/mlc-ci:latest

echo "Starting model packaging (this can take 45–90 minutes)..."
docker run --rm \
  -e HF_TOKEN="$HUGGING_FACE_TOKEN" \
  -v "$PROJECT_ROOT":/workspace -w /workspace \
  ghcr.io/mlc-ai/mlc-ci:latest bash -lc '
python - <<PY
import json, os
from pathlib import Path
from mlc_llm.interface.package import package

root = Path("external/mlc-llm")
out = root/"output_ios"
out.mkdir(parents=True, exist_ok=True)

cfg = {
  "device": "iphone",
  "model_list": [{
    "model": "HF://microsoft/Phi-3-mini-4k-instruct",
    "model_id": "phi-3-mini-4k-instruct",
    "estimated_vram_bytes": 2000000000,
    "bundle_weight": True
  }]
}

cfgp = out/"mlc-package-config.json"
cfgp.write_text(json.dumps(cfg, indent=2))

os.environ["HF_TOKEN"] = os.environ.get("HF_TOKEN", "")
package(cfgp, root, out)
print("MLC packaging complete")
PY'

echo "Copying packaged bundle into app Models directory..."
mkdir -p "$PROJECT_ROOT/NovaCompanionApp/NovaCompanion/Models"
rm -rf "$PROJECT_ROOT/NovaCompanionApp/NovaCompanion/Models/phi-3-mini-4k-instruct" || true
cp -R "$PROJECT_ROOT/external/mlc-llm/output_ios/bundle/phi-3-mini-4k-instruct" \
      "$PROJECT_ROOT/NovaCompanionApp/NovaCompanion/Models/phi-3-mini-4k-instruct"

echo "Done. Bundle copied to: NovaCompanionApp/NovaCompanion/Models/phi-3-mini-4k-instruct"
echo "Next: open Xcode and run the target 'NovaCompanion' on your iPhone."


