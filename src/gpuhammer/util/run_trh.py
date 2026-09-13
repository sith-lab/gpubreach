import os, sys, subprocess
import argparse
import time
from datetime import datetime
from fractions import Fraction

NUM_AGG = 24

HAMMER_ROOT = os.environ['HAMMER_ROOT']

AGG_CONFIG = {
    8  : {'warp' : 8,  'thread' : 1, 'round' : 3},
    9  : {'warp' : 9,  'thread' : 1, 'round' : 2},
    10 : {'warp' : 10, 'thread' : 1, 'round' : 2},
    11 : {'warp' : 11, 'thread' : 1, 'round' : 2},
    12 : {'warp' : 6,  'thread' : 2, 'round' : 2},
    13 : {'warp' : 7,  'thread' : 2, 'round' : 1},
    14 : {'warp' : 7,  'thread' : 2, 'round' : 1},
    15 : {'warp' : 8,  'thread' : 2, 'round' : 1},
    16 : {'warp' : 8,  'thread' : 2, 'round' : 1},
    17 : {'warp' : 9,  'thread' : 2, 'round' : 1},
    18 : {'warp' : 9,  'thread' : 2, 'round' : 1},
    19 : {'warp' : 10, 'thread' : 2, 'round' : 1},
    20 : {'warp' : 10, 'thread' : 2, 'round' : 1},
    21 : {'warp' : 7,  'thread' : 3, 'round' : 1},
    22 : {'warp' : 11, 'thread' : 2, 'round' : 1},
    23 : {'warp' : 8,  'thread' : 3, 'round' : 1},
    24 : {'warp' : 8,  'thread' : 3, 'round' : 1},
    }

KNOWN_FLIPS = {
    'A1' : {'bank_id' : 'A', 'row' : 30329, 'vic_pat' : '55', 'agg_pat' : 'aa'}, 
    'B1' : {'bank_id' : 'B', 'row' : 3543,  'vic_pat' : 'aa', 'agg_pat' : '55'},
    'B2' : {'bank_id' : 'B', 'row' : 13057, 'vic_pat' : 'aa', 'agg_pat' : '55'}, 
    'B3' : {'bank_id' : 'B', 'row' : 23029, 'vic_pat' : 'aa', 'agg_pat' : '55'}, 
    'C1' : {'bank_id' : 'C', 'row' : 4371,  'vic_pat' : 'aa', 'agg_pat' : '55'}, 
    'D1' : {'bank_id' : 'D', 'row' : 13635, 'vic_pat' : 'aa', 'agg_pat' : '55'}, 
    'D2' : {'bank_id' : 'D', 'row' : 21801, 'vic_pat' : 'aa', 'agg_pat' : '55'}, 
    'D3' : {'bank_id' : 'D', 'row' : 28498, 'vic_pat' : 'aa', 'agg_pat' : '55'}
    }

def restricted_num_agg(x):
    if 8 <= int(x) <= 24: return x
    raise argparse.ArgumentTypeError("num_agg must be between 8 and 24 inclusive")

def get_delays_from_file(delay_file):
    """ 
    Reads a delay file and returns a dictionary mapping bank IDs to their
    respective delays for different numbers of aggressors.
    The file is expected to have lines in the format: "bank_id, num_agg, delay".
    """
    delays = {}

    with open(delay_file, 'r') as f:
        for line in f:
            bank_id, num_agg, delay = line.strip().split(',')
            if bank_id not in delays:
                delays[bank_id] = {}
            delays[bank_id][int(num_agg)] = int(delay)

    return delays


def find_closest_xy(target, ratio_list):
    # Return (x, y) closest to target ratio
    lo, hi = 0, len(ratio_list) - 1
    best = ratio_list[0]
    while lo <= hi:
        mid = (lo + hi) // 2
        r, xy = ratio_list[mid]
        if abs(r - target) < abs(best[0] - target):
            best = (r, xy)
        if r < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return best[1]


def run_trh_config(args, delays, flip, aggressor_period, dummy_period):
    """
    Runs the TRH characterization for a specific bitflip configuration.
    Returns True if a bit-flip is detected, False otherwise.
    """
    bank_id = KNOWN_FLIPS[flip]['bank_id']
    row_set_file = os.path.join(args.row_set_dir, f'ROW_SET_{bank_id}.txt')
    if not os.path.isfile(row_set_file):
        print(f"Error: Row set file {row_set_file} does not exist. \
              Please ensure the row sets are generated and available.")
        sys.exit(1)

    print(f"Testing aggressor period = {aggressor_period}, dummy period = {dummy_period}...")

    flip_dir = os.path.join(args.output_dir, flip)
    if not os.path.exists(flip_dir):
        os.makedirs(flip_dir)
    output_log_file = os.path.join(flip_dir, f'agg{aggressor_period}_dum{dummy_period}.log')
    output_flip_file = os.path.join(flip_dir, f'agg{aggressor_period}_dum{dummy_period}_bitflip.txt')

    victim_pattern = KNOWN_FLIPS[flip]['vic_pat']
    aggressor_pattern = KNOWN_FLIPS[flip]['agg_pat']

    flip_row = KNOWN_FLIPS[flip]['row']
    min_rowid = flip_row - 94
    max_rowid = flip_row + 5

    delay = delays.get(bank_id, {}).get(NUM_AGG)

    with open(output_log_file, 'w+') as log_file:
        log_file.write(f"\n=== Started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        log_file.write(f"Running TRH characterization for flip {flip}.\n")
        log_file.flush()

        subprocess.run([
            trh_path,                   # Path to the trh executable
            row_set_file,               # Row set file for the bank
            str(NUM_AGG - 1),           # num_aggressors
            str(args.addr_step),
            str(46000),                 # iterations
            str(min_rowid),             # min_rowid
            str(max_rowid),             # max_rowid
            str(1000),                  # dummy_rowid
            str(4),                     # row_step
            str(4),                     # skip_step
            str(args.mem_size),         # mem_size
            str(AGG_CONFIG[NUM_AGG]['warp']),       # num_warp
            str(AGG_CONFIG[NUM_AGG]['thread']),     # num_thread
            str(delay),                             # delay
            str(AGG_CONFIG[NUM_AGG]['round']),      # round
            str(args.pattern_iteration),            # count_iter
            str(args.num_rows),         # num_rows
            victim_pattern,             # vic_pat
            aggressor_pattern,          # agg_pat
            str(aggressor_period),      # aggressor_period
            str(dummy_period),          # dummy_period
            output_flip_file
        ], stdout=log_file, stderr=subprocess.STDOUT)

        log_file.write(f"\n=== Completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        log_file.flush()

        time.sleep(3)

        # Check for "Bit-flip detected!" in the log
        log_file.seek(0)
        return any("Bit-flip detected!" in line for line in log_file)


# ==============================================================================

parser = argparse.ArgumentParser()

# Bitflip parameters
parser.add_argument('--flip_names', nargs='*', default=list(KNOWN_FLIPS.keys()),
                    help="Specify which known bitflips to hammer. \
                         If not specified, all known bitflips will be hammered.")

# Hammering pattern parameters
parser.add_argument('--pattern_iteration', type=int, default=50,
                    help="Number of iterations to repeat for each hammering pattern.")

# Device parameters
parser.add_argument('--mem_size', type=int, default=50465865728, 
                    help="Size of allocatable GPU memory in bytes.")
parser.add_argument('--num_rows', type=int, default=64169,
                    help="Number of rows in each bank.")
parser.add_argument('--addr_step', type=int, default=256,
                    help="Stride between addresses in the row set file. \
                        Must match the 'step' parameter used to generate row sets.")

# Path parameters
parser.add_argument('--hammer_root', type=str, default=HAMMER_ROOT,
                    help="Path to the gpuhammer repository.")
parser.add_argument('--row_set_dir', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'row_sets'),
                    help="Path to the directory containing the row set files")
parser.add_argument('--output_dir', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'fig11'),
                    help="Path to store the results of the experiment.")
parser.add_argument('--delay_file', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'delay', 'delays.txt'),
                    help="Path to the file containing delay amounts.")

args = parser.parse_args()


# ==============================================================================

trh_path = os.path.join(args.hammer_root, 'src/out/build/trh')
if not os.path.isfile(trh_path):
    print(f"Error: {trh_path} does not exist. Please build the executables \
          and set the HAMMER_ROOT environment variable.")
    sys.exit(1)
if not os.path.exists(args.row_set_dir):
    print(f"Error: Row set directory {args.row_set_dir} does not exist. \
          Please ensure the row sets are generated and available.")
    sys.exit(1)
if not os.path.isfile(args.delay_file):
    print(f"Error: Delay file {args.delay_file} does not exist. \
          Please ensure the delay file is generated and available.")
    sys.exit(1)
if not os.path.exists(args.output_dir):
    os.makedirs(args.output_dir)

delays = get_delays_from_file(args.delay_file)


ratio_to_xy = {}
for x in range(1, 101):
    for y in range(1, 3):
        ratio = Fraction(x, x + y)
        if ratio not in ratio_to_xy or y < ratio_to_xy[ratio][1]:
            ratio_to_xy[ratio] = (x, y)

ratio_list = sorted([(float(r), xy) for r, xy in ratio_to_xy.items()])

# ==============================================================================
# START CAMPAIGN
# ==============================================================================

for flip in args.flip_names:
    if flip not in KNOWN_FLIPS:
        print(f"Warning: {flip} is not a known flip. Skipping.")
        continue
    
    print("..........................................................")
    print(f"Characterizing TRH for flip {flip}...")

    low, high = 0.0, 1.0
    best_xy = None
    cache = {}

    while high - low > 1e-6:
        mid = (low + high) / 2
        x, y = find_closest_xy(mid, ratio_list)
        key = (x, y)
        if key not in cache:
            cache[key] = run_trh_config(args, delays, flip, x, y)
        if cache[key]:
            best_xy = (x, y)
            high = mid
        else:
            low = mid
