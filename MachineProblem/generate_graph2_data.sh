#!/usr/bin/env bash

# generate_graph2_data.sh
# Generate the data required for Graph 2 in MP1 Instructions.

echo "Generating Graph 2 Data (55 simulations and AAT calculation)..."

nix-shell -p python3Packages.pandas python3Packages.xlrd --run "python3 -c \"
import pandas as pd
import subprocess
import os

df = pd.read_excel('MachineProblem1_Given/cacti_table.xls')
df_32 = df[df[' Block Size(bytes)'] == 32]
ht_map = {}
for _, row in df_32.iterrows():
    assoc = str(row[' Associativity']).strip()
    if assoc != 'FA':
        assoc = int(assoc)
    ht_map[(int(row['Cache Size(bytes)']), assoc)] = float(row[' Access Time(ns)'])

os.makedirs('graph_data/graph1', exist_ok=True)
output_file = 'graph_data/graph1/graph2.csv'

with open(output_file, 'w') as f:
    f.write('size_log2,assoc_1,assoc_2,assoc_4,assoc_8,assoc_FA\n')
    for size_log2 in range(10, 21):
        size = 2**size_log2
        row = [str(size_log2)]
        for assoc in [1, 2, 4, 8, 'FA']:
            sim_assoc = size // 32 if assoc == 'FA' else assoc
            ht = ht_map.get((size, assoc))
            if ht is None:
                print(f'WARNING: No hit time found for size={size}, assoc={assoc}')
                ht = 0.0

            cmd = ['./sim_cache', '32', str(size), str(sim_assoc), '0', '0', '0', '0', 'MachineProblem1_Given/traces/gcc_trace.txt']
            res = subprocess.run(cmd, capture_output=True, text=True)

            miss_rate = 0.0
            for line in res.stdout.split('\n'):
                if 'e. L1 miss rate:' in line:
                    miss_rate = float(line.split()[-1])
                    break

            aat = ht + miss_rate * 100.0
            row.append(f'{aat:.6f}')

        f.write(','.join(row) + '\n')
        print(f'Completed size 2^{size_log2} ({size})')

print('Done generating data in ' + output_file)
\""
