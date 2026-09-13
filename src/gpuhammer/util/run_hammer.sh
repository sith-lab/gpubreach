# Set the first parameter to <Stable Max Clock Rate> reported by run_timing_task.py
# Set the second parameter to a stable memory clock rate
bash $HAMMER_ROOT/util/init_cuda.sh 1800 7600

# Variables
bank_id=A
delay=56            # Delay, set to an optimal delay found by run_delay.sh

num_rows=64169      # Number of rows in the row_set (line number - 1)
min_rowid=6         # Minimum row id to hammer (set to >=6 to avoid list overflow in the code)
max_rowid=64000     # Maximum row id to hammer (set to <= num_rows - 100 to avoid overflow)

vic_pat=55          # Victim row data pattern in hex
agg_pat=aa          # Aggressor row data pattern in hex

num_agg=24          # Number of aggressors
num_warp=8          # Number of warps
num_thread=3        # Number of threads per warp
round=1             # No. of round per tREFI, each round hammers <num_agg> rows
# Make sure that:
#   - num_warp * num_thread >= num_agg
#   - num_agg * round <= max number of activations per tREFI

row_step=4          # Distance between two aggressor rows in a hammering pattern
skip_step=1         # Increment <skip_step> rows after hammering each pattern
count_iter=1        # Hammer each pattern <count_iter> times

iterations=91000    # Number of tREFI intervals to hammer

# Memory Properties
addr_step=256           # Set to be the <step> parameter used in finding conf_set/row_set
mem_size=50465865728    # Bytes of memory allocated for hammering (recommend: size of memory - 1GB)

# File paths
mkdir -p $HAMMER_ROOT/results/campaign/raw_data
rowset_file="$HAMMER_ROOT/results/row_sets/ROW_SET_${bank_id}.txt"
log_file="$HAMMER_ROOT/results/campaign/raw_data/${num_agg}agg_b${bank_id}_${vic_pat}${agg_pat}.log"
bitflip_file="$HAMMER_ROOT/results/campaign/raw_data/${num_agg}agg_b${bank_id}_${vic_pat}${agg_pat}_bitflip_count.txt"


# Running the test
nvidia-smi -q > $log_file
echo "Start hammering ..."

$HAMMER_ROOT/src/out/build/gpu_hammer $rowset_file $((num_agg - 1)) $addr_step $iterations $min_rowid $max_rowid $row_step $skip_step $mem_size $num_warp $num_thread $delay $round $count_iter $num_rows $vic_pat $agg_pat $bitflip_file > $log_file

echo "Hammering done."