import argparse
import subprocess
import os

HAMMER_ROOT = os.environ['HAMMER_ROOT']

def get_parser_loads(parser):
    parse_load = parser.add_parser(
        "load",
        help="Gets the load timing of different load modifiers",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parse_load.add_argument(
        "--size",
        type=int,
        help="The size of the entire memory layout we will allocate in bytes",
        default=15 * (1 << 30),
    )
    parse_load.add_argument(
        "--it",
        type=int,
        help="Number of iterations when confirming conflict timing",
        default=10,
    )
    parse_load.add_argument(
        "--step",
        type=int,
        help="How many step bytes to step over for each iteration.",
        default=32,
    )
    parse_load.add_argument(
        "--file",
        type=str,
        help="File to store timing values",
        default="LOAD_TIMING.txt",
    )


def get_parser_conf_set(parser):
    parser_conf_set = parser.add_parser(
        "conf_set",
        help="Gets the conflict set of a bank given an address in a bank. The output file contains addresses offsets.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser_conf_set.add_argument(
        "--size",
        type=int,
        help="The size of the entire memory layout we will allocate in bytes",
        default=15 * (1 << 30),
    )
    parser_conf_set.add_argument(
        "--range",
        type=int,
        help="The amount of bytes to iterate over.",
        default=8 * (1 << 20),
    )
    parser_conf_set.add_argument(
        "--it",
        type=int,
        help="Number of iterations when confirming conflict timing",
        default=10,
    )
    parser_conf_set.add_argument(
        "--step",
        type=int,
        help="How many step bytes to step over for each iteration.",
        default=32,
    )
    parser_conf_set.add_argument(
        "--threshold",
        type=int,
        help="tRC value spike to be considered a conflict.",
        default=37,
    )
    parser_conf_set.add_argument(
        "--trgtBankOfs",
        type=int,
        help="Byte offset for address of the target bank. The program will get the offsets in the same bank as this address.",
        default=0,
    )
    parser_conf_set.add_argument(
        "--file",
        type=str,
        help="File to store offset.",
        default="CONF_SET.txt",
    )


def get_parser_row_set(parser):
    parser_row_set = parser.add_parser(
        "row_set",
        help="Finds the rows in the bank given conflict set. Outputs file with row addresses and offset between previous row address found"
        "Each line has multiple addresses representing the row.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser_row_set.add_argument(
        "--size",
        type=int,
        help="The size of the entire memory layout we will allocate in bytes",
        default=15 * (1 << 30),
    )
    parser_row_set.add_argument(
        "--it",
        type=int,
        help="Number of iterations when confirming conflict timing",
        default=10,
    )
    parser_row_set.add_argument(
        "--threshold",
        type=int,
        help="Time value to be considered a conflict.",
        default=37,
    )
    parser_row_set.add_argument(
        "--trgtBankOfs",
        type=int,
        help="Byte offset for address of the target bank. The program will get the offsets in the same bank as this address."
        "This is supposedly the first ever address appearance in that bank",
        default=0,
    )
    parser_row_set.add_argument(
        "--max",
        type=int,
        help="Maximum number of rows we will get.",
        default=0,
    )
    parser_row_set.add_argument(
        "inputFile",
        type=str,
        help="File to store offset.",
    )
    parser_row_set.add_argument(
        "--outputFile",
        type=str,
        help="File to store offset.",
        default="ROW_SET.txt",
    )

def get_parser_bank_set(parser):
    parser_bank_set = parser.add_parser(
        "bank_set",
        help="Gets first ever address appearances saw for banks. Each line represents a new bank.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser_bank_set.add_argument(
        "--size",
        type=int,
        help="The size of the entire memory layout we will allocate in bytes. Range will be the same as size",
        default=15 * (1 << 30),
    )
    parser_bank_set.add_argument(
        "--it",
        type=int,
        help="Number of iterations when confirming conflict timing",
        default=10,
    )
    parser_bank_set.add_argument(
        "--step",
        type=int,
        help="How many step bytes to step over for each iteration.",
        default=32,
    )
    parser_bank_set.add_argument(
        "--threshold",
        type=int,
        help="tRC value spike to be considered a conflict.",
        default=37,
    )
    parser_bank_set.add_argument(
        "--max",
        type=int,
        help="Maximum number of banks we will get.",
        default=1,
    )
    parser_bank_set.add_argument(
        "--outputFile",
        type=str,
        help="File to store bank offset.",
        default="BANK_SET.txt",
    )
def get_parser_gen_time(parser):
    parser_gt = parser.add_parser(
        "gt",
        help="Gets the timing values of all addresses on the first address. Mostly only used to get the threshold",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser_gt.add_argument(
        "--range",
        type=int,
        help="The amount of bytes to iterate over.",
        default=8 * (1 << 20),
    )
    parser_gt.add_argument(
        "--size",
        type=int,
        help="The size of the entire memory layout we will allocate in bytes",
        default=15 * (1 << 30),
    )
    parser_gt.add_argument(
        "--it",
        type=int,
        help="Number of iterations when confirming conflict timing",
        default=10,
    )
    parser_gt.add_argument(
        "--step",
        type=int,
        help="How many step bytes to step over for each iteration.",
        default=32,
    )
    parser_gt.add_argument(
        "--file",
        type=str,
        help="File to store timing values",
        default="TIMING_VALUE.txt",
    )
    parser_gt.add_argument(
        "--same",
        action='store_true',
        help="Get normal access time instead, not conflict.",
        default=False,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="run_timing_task",
        description="Facade Runner that executes different CUDA timing channel tasks",
    )
    subparsers = parser.add_subparsers(
        dest="task_name", help="use `<command> -h` to see respective arguments"
    )
    get_parser_conf_set(subparsers)
    get_parser_gen_time(subparsers)
    get_parser_row_set(subparsers)
    get_parser_bank_set(subparsers)
    get_parser_loads(subparsers)
    args = parser.parse_args()
    match args.task_name:
        case "conf_set":
            p = subprocess.Popen(
                f"{HAMMER_ROOT}/src/out/build/conf_set {args.size} {args.range} {args.it} {args.step} {args.threshold} {args.trgtBankOfs} {args.file}",
                shell=True,
            )
            p.wait()
        case "row_set":
            p = subprocess.Popen(
                f"{HAMMER_ROOT}/src/out/build/row_set {args.size} {args.it} {args.threshold} {args.trgtBankOfs} {args.max} {args.inputFile} {args.outputFile}",
                shell=True,
            )
            p.wait()
        case "bank_set":
            p = subprocess.Popen(
                f"{HAMMER_ROOT}/src/out/build/bank_set {args.size} {args.it} {args.step} {args.threshold} {args.max} {args.outputFile}",
                shell=True,
            )
            p.wait()
        case "gt":
            if (args.same):
                p = subprocess.Popen(
                    f"{HAMMER_ROOT}/src/out/build/gen_time_same {args.size} {args.range} {args.it} {args.step} {args.file}",
                    shell=True,
                )
                p.wait()
            else:
                p = subprocess.Popen(
                    f"{HAMMER_ROOT}/src/out/build/gen_time {args.size} {args.range} {args.it} {args.step} {args.file}",
                    shell=True,
                )
                p.wait()
        case "load":
            p = subprocess.Popen(
                f"{HAMMER_ROOT}/src/out/build/load_modifiers {args.size} {args.it} {args.step} {args.file}",
                shell=True,
            )
            p.wait()
