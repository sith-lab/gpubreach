import os, sys, subprocess
import argparse
import time
from datetime import datetime

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

# ==============================================================================

parser = argparse.ArgumentParser()

# Campaign parameters
parser.add_argument('--bank_ids', nargs='+', required=True,
                    help="List of bank IDs to run the campaign on.")
parser.add_argument('--num_agg', type=restricted_num_agg, nargs='*', default=[24],
                    help="List of number of aggressors to run the campaign on. \
                        Must be between 8 and 24, inclusive.")
parser.add_argument('--data_pattern', choices=['checkered', 'opposite', 'all'], 
                    default='checkered',
                    help="Data pattern for padding victim and aggressor rows.")

# Known bitflip parameters
# parser.add_argument('--only_known_flips', action='store_true',
#                     help="If set, the campaign will only hammer neighborhoods \
#                         of known bitflips.")
# parser.add_argument('--flip_names', nargs='*', default=list(KNOWN_FLIPS.keys()),
#                     help="Specify which known bitflips to hammer. \
#                         If not specified, all known bitflips will be hammered.")

# Hammering pattern parameters
parser.add_argument('--agg_distance', type=int, default=4,
                    help="Stride between aggressor rows in each hammering pattern.")
parser.add_argument('--skip_step', type=int, default=3,
                    help="Stride between hammering patterns.")
parser.add_argument('--pattern_iteration', type=int, default=1,
                    help="Number of iterations to repeat for each hammering pattern.")

# Device parameters
parser.add_argument('--mem_size', type=int, default=50465865728, 
                    help="Size of allocatable GPU memory in bytes.")
parser.add_argument('--num_rows', type=int, default=64169,
                    help="Number of rows in each bank.")
parser.add_argument('--addr_step', type=int, default=256,
                    help="Stride between addresses in the row set file. \
                        Must match the 'step' parameter used to generate row sets.")
parser.add_argument('--trefi', type=int, default=1407,
                    help="tREFI in nanoseconds.")

# Path parameters
parser.add_argument('--hammer_root', type=str, default=HAMMER_ROOT,
                    help="Path to the gpuhammer repository.")
parser.add_argument('--row_set_dir', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'row_sets'),
                    help="Path to the directory containing the row set files")
parser.add_argument('--output_dir', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'campaign'),
                    help="Path to store the results of the campaign.")
parser.add_argument('--delay_file', type=str, 
                    default=os.path.join(HAMMER_ROOT, 'results', 'delay', 'delays.txt'),
                    help="Path to the file containing delay amounts.")

args = parser.parse_args()

# ==============================================================================

hammer_path = os.path.join(args.hammer_root, 'src/out/build/gpu_hammer')
if not os.path.isfile(hammer_path):
    print(f"Error: {hammer_path} does not exist. Please build the executables \
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

# Generate pairs of data patterns for (victim, aggressor)
DATA_PATTERNS = [f"{i:01x}"*2 for i in range(16)]
if args.data_pattern == 'checkered':
    data_pattern_pairs = [('aa','55'), ('55','aa')]
elif args.data_pattern == 'opposite':
    data_pattern_pairs = [(pat, pat) for pat in DATA_PATTERNS]
elif args.data_pattern == 'all':
    data_pattern_pairs = [(pat1, pat2) for pat1 in DATA_PATTERNS for pat2 in DATA_PATTERNS]

delays = get_delays_from_file(args.delay_file)


# ==============================================================================
# START CAMPAIGN
# ==============================================================================

for bank_id in args.bank_ids:

    row_set_file = os.path.join(args.row_set_dir, f'ROW_SET_{bank_id}.txt')
    if not os.path.isfile(row_set_file):
        print(f"Error: Row set file {row_set_file} does not exist. \
              Please ensure the row sets are generated and available.")
        continue

    bank_dir = os.path.join(args.output_dir, f'bank_{bank_id}')
    if not os.path.exists(bank_dir):
        os.makedirs(bank_dir)

    for num_agg in args.num_agg:

        print(f"\n=== Starting campaign for bank {bank_id} with {num_agg}-sided patterns ===\n")

        delay = delays.get(bank_id, {}).get(num_agg)
        if delay is None:
            print(f"Warning: No delay found for bank {bank_id} with {num_agg} \
                   aggressors.")
            # TODO: Automate obtaining delay.

        # TODO: Handle known flips
        
        for victim_pattern, aggressor_pattern in data_pattern_pairs:

            print(f"Testing victim pattern '0x{victim_pattern}' and aggressor pattern '0x{aggressor_pattern}'")
            
            output_log_file = os.path.join(bank_dir, 
                                f'{num_agg}agg_{victim_pattern}{aggressor_pattern}_log.txt')
            output_flip_file = os.path.join(bank_dir, 
                                f'{num_agg}agg_{victim_pattern}{aggressor_pattern}_flip_count.txt')

            with open(output_log_file, 'w') as log_file:
                log_file.write(f"\n=== Started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
                log_file.write(f"Running campaign for bank {bank_id} with {num_agg} aggressors.\n")
                log_file.flush()

                subprocess.run([
                    hammer_path,                # Path to the hammer executable
                    row_set_file,               # Row set file for the bank
                    str(num_agg - 1),           # num_aggressors
                    str(args.addr_step),
                    str(46000),                      # iterations
                    str(6),                          # min_rowid
                    str(args.num_rows - 150),   # max_rowid
                    # str(100),
                    str(args.agg_distance),     # row_step
                    str(args.skip_step),        # skip_step
                    str(args.mem_size),         # mem_size
                    str(AGG_CONFIG[num_agg]['warp']),       # num_warp
                    str(AGG_CONFIG[num_agg]['thread']),     # num_thread
                    str(delay),                 # delay
                    str(AGG_CONFIG[num_agg]['round']),      # round
                    str(args.pattern_iteration),            # count_iter
                    str(args.num_rows),         # num_rows
                    victim_pattern,             # vic_pat
                    aggressor_pattern,          # agg_pat
                    output_flip_file
                ], stdout=log_file, stderr=subprocess.STDOUT)

                log_file.write(f"\n=== Completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
            
            time.sleep(3)