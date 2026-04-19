#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIVEN_DIR="$SCRIPT_DIR/MachineProblem1_Given"
TRACE_DIR="$GIVEN_DIR/traces"
SIM_CACHE="$SCRIPT_DIR/sim_cache"
OUTPUT_DIR="$SCRIPT_DIR/valgrind_output"

mkdir -p "$OUTPUT_DIR"

CONFIGS=(
    "16 1024 2 0    0 0 0 gcc_trace.txt"           # validation0
    "16 1024 1 0    0 0 0 perl_trace.txt"          # validation1
    "16 1024 2 0    0 1 0 gcc_trace.txt"           # validation2
    "16 1024 2 0    0 2 0 vortex_trace.txt"        # validation3
    "16 1024 2 8192 4 0 0 gcc_trace.txt"           # validation4
    "16 1024 1 8192 4 0 0 go_trace.txt"            # validation5
    "16 1024 2 8192 4 0 1 gcc_trace.txt"           # validation6
    "16 1024 1 8192 4 0 1 compress_trace.txt"      # validation7
)

echo "Building sim_cache..."
make -C "$SCRIPT_DIR" clean > /dev/null
make -C "$SCRIPT_DIR" > /dev/null

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=${#CONFIGS[@]}

for i in "${!CONFIGS[@]}"; do
    read -r BLOCKSIZE L1_SIZE L1_ASSOC L2_SIZE L2_ASSOC REPL_POLICY INCLUSION TRACE <<< "${CONFIGS[$i]}"
    TRACE_PATH="$TRACE_DIR/$TRACE"
    ACTUAL="$OUTPUT_DIR/validation${i}_valgrind.txt"

    echo "Running Valgrind on configuration $i..."

    if valgrind --leak-check=full --error-exitcode=1 "$SIM_CACHE" "$BLOCKSIZE" "$L1_SIZE" "$L1_ASSOC" "$L2_SIZE" "$L2_ASSOC" "$REPL_POLICY" "$INCLUSION" "$TRACE_PATH" > "$ACTUAL" 2>&1; then
        echo "Configuration $i: NO MEMORY LEAKS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "Configuration $i: MEMORY LEAK OR ERROR DETECTED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "Check $ACTUAL for more details."
        # Print a tail of the file to show the valgrind summary
        tail -n 15 "$ACTUAL" >&2
    fi
done

echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
exit $FAIL_COUNT
