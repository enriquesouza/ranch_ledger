#!/usr/bin/env bash
# simulate_100.sh — Reproducible 100-agent spawn for CI.
#
# Boots anvil with --accounts 100, runs Deploy.s.sol then BulkMint.s.sol,
# asserts totalBovines == 100, and tears down anvil.
#
# Exit codes:
#   0 — success (totalBovines == 100)
#   1 — assertion failure or script error

set -euo pipefail

ANVIL_PORT=8545
ANVIL_PID=""
RPC="http://127.0.0.1:${ANVIL_PORT}"

cleanup() {
    if [[ -n "${ANVIL_PID}" ]]; then
        kill "${ANVIL_PID}" 2>/dev/null || true
        wait "${ANVIL_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# ── Boot anvil ────────────────────────────────────────────────
echo "==> Starting anvil with 100 accounts..."
anvil --accounts 100 --balance 1000 --block-time 1 > /tmp/anvil.log 2>&1 &
ANVIL_PID=$!

# Wait for anvil to be ready (up to 30s)
for i in $(seq 1 60); do
    if cast block-number --rpc-url "${RPC}" >/dev/null 2>&1; then
        echo "==> Anvil ready at ${RPC} (block $(cast block-number --rpc-url "${RPC}"))"
        break
    fi
    [[ $i -eq 60 ]] && { echo "ERROR: anvil did not start within 30s"; exit 1; }
    sleep 0.5
done

# ── Deploy contracts ──────────────────────────────────────────
echo "==> Running Deploy.s.sol..."
forge script script/Deploy.s.sol --rpc-url "${RPC}" --broadcast \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    -vvvv

# ── Spawn 100 agents ──────────────────────────────────────────
echo "==> Running BulkMint.s.sol..."
forge script script/BulkMint.s.sol --rpc-url "${RPC}" --broadcast \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    -vvvv

# ── Assert totalBovines == 100 ────────────────────────────────
echo "==> Verifying totalBovines..."
TOTAL=$(cast call "$(jq -r '.BovineTracking' deployments/local.json)" "totalBovines()")
echo "    totalBovines = ${TOTAL}"

if [[ "${TOTAL}" != "100" ]]; then
    echo "ERROR: expected 100, got ${TOTAL}"
    exit 1
fi

echo "==> ✅ simulate_100 passed — 100 bovines on-chain."
