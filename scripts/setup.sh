#!/usr/bin/env bash
# One-time workbench setup. Idempotent — safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> forge-std"
if [ ! -d lib/forge-std ]; then
  git submodule add https://github.com/foundry-rs/forge-std lib/forge-std || \
    forge install foundry-rs/forge-std
fi

echo "==> DeFiHackLabs (runnable ground truth — submodule, not copied in)"
if [ ! -d lib/DeFiHackLabs ]; then
  git submodule add https://github.com/SunWeb3Sec/DeFiHackLabs lib/DeFiHackLabs
fi

git submodule update --init --recursive

echo "==> knowledge-base index"
python3 scripts/ingest.py

echo
echo "Done. Next:"
echo "  export ETH_RPC_URL=<archive-rpc>   # required for fork/exploit runs"
echo "  Drop a contract in targets/<name>/ and run the detection-agent."
