#!/usr/bin/env bash

# generate_graph4_data.sh
# Generate the data required for Graph 4 in MP1 Instructions (with AAT).

echo "Generating Graph 4 Data (12 simulations and AAT calculation)..."

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

os.makedirs('graph_data/graph4', exist_ok=True)
output_file = 'graph_data/graph4/graph4.csv'

# L1 parameters for Graph 4 are fixed
l1_size = 1024
l1_assoc = 4
ht_l1 = ht_map.get((l1_size, l1_assoc))
if ht_l1 is None:
    print(f'WARNING: No hit time found for L1 size={l1_size}, assoc={l1_assoc}')
    ht_l1 = 0.0

with open(output_file, 'w') as f:
    f.write('l2_size_log2,aat_noninc,aat_inc\n')
    for l2_size_log2 in range(11, 17):
        l2_size = 2**l2_size_log2
        row = [str(l2_size_log2)]

        # Find L2 hit time
        ht_l2 = ht_map.get((l2_size, 8))
        if ht_l2 is None:
            print(f'WARNING: No hit time found for L2 size={l2_size}, assoc=8')
            ht_l2 = 0.0

        for inclusion in [0, 1]:
            cmd = ['./sim_cache', '32', str(l1_size), str(l1_assoc), str(l2_size), '8', '0', str(inclusion), 'MachineProblem1_Given/traces/gcc_trace.txt']
            res = subprocess.run(cmd, capture_output=True, text=True)

            l1_mr = 0.0
            l2_mr = 0.0
            for line in res.stdout.split('\n'):
                if 'e. L1 miss rate:' in line:
                    l1_mr = float(line.split()[-1])
                elif 'k. L2 miss rate:' in line:
                    l2_mr = float(line.split()[-1])

            # AAT = HT_L1 + MR_L1 * (HT_L2 + MR_L2 * MissPenalty)
            aat = ht_l1 + l1_mr * (ht_l2 + l2_mr * 100.0)
            row.append(f'{aat:.6f}')

        f.write(','.join(row) + '\n')
        print(f'Completed L2 size 2^{l2_size_log2} ({l2_size})')

print('Done generating data in ' + output_file)
\""
