import matplotlib.pyplot as plt
import sys, os

HAMMER_ROOT = os.environ['HAMMER_ROOT']
iteration = int(sys.argv[1])         # 10000
trefi = int(sys.argv[2])             # 1407
bank_id = sys.argv[3]           # 1

# Function to read the file and return y-values and corresponding x-values
def read_file(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
    y_values = [float(line.strip()) for line in lines]
    z_values = [iteration * trefi / y * 24 for y in y_values]
    x_values = list(range(len(y_values)))
    return x_values, z_values

def generate_filename_str(num_agg, bank):
    return f"{HAMMER_ROOT}/src/log/delay/{num_agg}agg_b{bank}_timing_delay.txt"

# Read the data from the files
for num_agg in [int(x) for x in sys.argv[4:]]:
    x, y = read_file(generate_filename_str(num_agg, bank_id))
    plt.plot(x, y, label=f"{num_agg} agg")

# Add labels and title
plt.xlabel('Delay')
plt.ylabel('# ACTS / tREFI')
plt.legend()
plt.grid(True)
plt.title(f"Bank{bank_id} Timing Synchronization")

# Display the plot
plt.show()
plt.savefig(f"delay_plot_21agg_b{bank_id}.png")