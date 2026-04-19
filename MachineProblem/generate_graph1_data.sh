#!/usr/bin/env bash

# generate_graph1_data.sh
# Generate the data required for Graph 1 in MP1 Instructions.

mkdir -p graph_data/graph1
OUTPUT_FILE="graph_data/graph1/graph1.csv"

echo "size_log2,assoc_1,assoc_2,assoc_4,assoc_8,assoc_FA" > "$OUTPUT_FILE"

echo "Generating Graph 1 Data (55 simulations)..."

for size_log2 in {10..20}; do
    size=$((2 ** size_log2))
    row="$size_log2"

    # Assoc 1, 2, 4, 8
    for assoc in 1 2 4 8; do
        output=$(./sim_cache 32 "$size" "$assoc" 0 0 0 0 MachineProblem1_Given/traces/gcc_trace.txt)
        miss_rate=$(echo "$output" | grep "e. L1 miss rate:" | awk '{print $5}')
        row="$row,$miss_rate"
    done

    # Fully associative
    assoc_fa=$((size / 32))
    output=$(./sim_cache 32 "$size" "$assoc_fa" 0 0 0 0 MachineProblem1_Given/traces/gcc_trace.txt)
    miss_rate=$(echo "$output" | grep "e. L1 miss rate:" | awk '{print $5}')
    row="$row,$miss_rate"

    echo "$row" >> "$OUTPUT_FILE"
    echo "Completed size 2^$size_log2 ($size)"
done

echo "Done generating data in $OUTPUT_FILE"
