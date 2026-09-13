#!/bin/bash

echo ""
echo "-------------------------------------------"
echo ""
echo "[INFO] Starting Generation of Row Sets"

# A: 23607368960
# B: 23607370752
# C: 23607340288
# D: 23607376896
# E: 23607362560
# F: 23607337984
declare -A bank_map; bank_map[406784]="A"; bank_map[408576]="B"; bank_map[360448]="C"; bank_map[398336]="D"; bank_map[400384]="E"; bank_map[375040]="F";

# for val in 408576 360448 400384 398336 375040; do
for val in 400384 398336 375040; do
  python3 $HAMMER_ROOT/util/run_timing_task.py conf_set --range $((300 * (2 ** 20))) --size $((47 * (2 ** 30))) --it 15 --step 256 --threshold 27 --file $HAMMER_ROOT/results/row_sets/CONF_SET_${bank_map[$val]}.txt --trgtBankOfs $val
  sleep 3s
  python3 $HAMMER_ROOT/util/run_timing_task.py row_set --size $((47 * (2 ** 30))) --it 15 --threshold 27 --trgtBankOfs $val --outputFile $HAMMER_ROOT/results/row_sets/ROW_SET_${bank_map[$val]}.txt $HAMMER_ROOT/results/row_sets/CONF_SET_${bank_map[$val]}.txt
  sleep 3s
done

echo "[INFO] Done. Row Sets are stored in 'results/row_sets'"