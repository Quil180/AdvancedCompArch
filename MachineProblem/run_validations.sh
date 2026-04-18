#!/usr/bin/env bash
#
# run_validations.sh
# Builds sim_cache, runs all 8 validation configurations, and compares
# output against the expected results in MachineProblem1_Given/validation_runs/.
#
# Usage:  ./run_validations.sh
#
# Exit codes:
#   0  – all validations passed
#   1  – one or more validations failed (or build error)

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIVEN_DIR="$SCRIPT_DIR/MachineProblem1_Given"
TRACE_DIR="$GIVEN_DIR/traces"
VALID_DIR="$GIVEN_DIR/validation_runs"
SIM_CACHE="$SCRIPT_DIR/sim_cache"
OUTPUT_DIR="$SCRIPT_DIR/validation_output"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Build ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  sim_cache Validation Runner${NC}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}▶ Building sim_cache ...${NC}"

if ! make -C "$SCRIPT_DIR" clean > /dev/null 2>&1; then
    echo -e "${RED}✗ make clean failed${NC}"
fi

if ! make -C "$SCRIPT_DIR" > /dev/null 2>&1; then
    echo -e "${RED}✗ Build failed. Fix compilation errors and retry.${NC}"
    exit 1
fi

if [[ ! -x "$SIM_CACHE" ]]; then
    echo -e "${RED}✗ sim_cache binary not found after build.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build succeeded${NC}"
echo ""

# ── Prepare output directory ─────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Validation configurations ────────────────────────────────────────────────
# Format: "BLOCKSIZE L1_SIZE L1_ASSOC L2_SIZE L2_ASSOC REPL_POLICY INCLUSION trace_file"
#
# REPL_POLICY:  0 = LRU,  1 = FIFO,  2 = Optimal
# INCLUSION:    0 = non-inclusive,  1 = inclusive

CONFIGS=(
    "16 1024 2 0    0 0 0 gcc_trace.txt"          # validation0: L1-only, LRU, non-inclusive
    "16 1024 1 0    0 0 0 perl_trace.txt"          # validation1: L1-only DM, LRU, non-inclusive
    "16 1024 2 0    0 1 0 gcc_trace.txt"           # validation2: L1-only, FIFO, non-inclusive
    "16 1024 2 0    0 2 0 vortex_trace.txt"        # validation3: L1-only, optimal, non-inclusive
    "16 1024 2 8192 4 0 0 gcc_trace.txt"           # validation4: L1+L2, LRU, non-inclusive
    "16 1024 1 8192 4 0 0 go_trace.txt"            # validation5: L1+L2 DM, LRU, non-inclusive
    "16 1024 2 8192 4 0 1 gcc_trace.txt"           # validation6: L1+L2, LRU, inclusive
    "16 1024 1 8192 4 0 1 compress_trace.txt"      # validation7: L1+L2 DM, LRU, inclusive
)

# ── Run validations ──────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=${#CONFIGS[@]}

echo -e "${BOLD}Running $TOTAL validation tests ...${NC}"
echo -e "────────────────────────────────────────────────────"

for i in "${!CONFIGS[@]}"; do
    # Parse config
    read -r BLOCKSIZE L1_SIZE L1_ASSOC L2_SIZE L2_ASSOC REPL_POLICY INCLUSION TRACE <<< "${CONFIGS[$i]}"

    TRACE_PATH="$TRACE_DIR/$TRACE"
    EXPECTED="$VALID_DIR/validation${i}.txt"
    ACTUAL="$OUTPUT_DIR/validation${i}_out.txt"

    # Describe the run
    case $REPL_POLICY in
        0) REPL_NAME="LRU"     ;;
        1) REPL_NAME="FIFO"    ;;
        2) REPL_NAME="Optimal" ;;
        *) REPL_NAME="???"     ;;
    esac

    case $INCLUSION in
        0) INCL_NAME="non-inclusive" ;;
        1) INCL_NAME="inclusive"     ;;
        *) INCL_NAME="???"          ;;
    esac

    if [[ "$L2_SIZE" == "0" ]]; then
        L2_DESC="no L2"
    else
        L2_DESC="L2=${L2_SIZE}B/${L2_ASSOC}-way"
    fi

    DESC="BS=${BLOCKSIZE} L1=${L1_SIZE}B/${L1_ASSOC}-way ${L2_DESC} ${REPL_NAME} ${INCL_NAME} [${TRACE}]"

    printf "  [%d/%d] %-70s " "$((i+1))" "$TOTAL" "$DESC"

    # Run sim_cache
    if ! "$SIM_CACHE" "$BLOCKSIZE" "$L1_SIZE" "$L1_ASSOC" "$L2_SIZE" "$L2_ASSOC" \
         "$REPL_POLICY" "$INCLUSION" "$TRACE_PATH" > "$ACTUAL" 2>&1; then
        echo -e "${RED}✗ RUNTIME ERROR${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Compare with expected output (ignore whitespace differences and case)
    if diff -iw "$ACTUAL" "$EXPECTED" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # Show first few lines of diff for debugging
        echo -e "    ${YELLOW}Differences (first 20 lines):${NC}"
        diff -iw "$ACTUAL" "$EXPECTED" | head -20 | sed 's/^/    /'
        echo ""
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "────────────────────────────────────────────────────"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}🎉 All ${TOTAL} validations PASSED!${NC}"
else
    echo -e "${RED}${BOLD}❌ ${FAIL_COUNT}/${TOTAL} validations FAILED${NC}"
    echo -e "${GREEN}   ${PASS_COUNT}/${TOTAL} passed${NC}"
fi

echo ""
echo -e "Output files saved in: ${CYAN}${OUTPUT_DIR}/${NC}"

exit $FAIL_COUNT
