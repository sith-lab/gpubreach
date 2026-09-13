#include <rh_utils.cuh>
#include <rh_impls.cuh>

#include <atomic>
#include <chrono>
#include <fstream>
#include <iostream>
#include <pthread.h>
#include <stdint.h>
#include <vector>
#include <numeric>

std::string CLI_PREFIX = "(synchronization): ";
int main(int argc, char *argv[])
{
  
  const uint64_t num_victim = std::stoull(argv[2]);
  const uint64_t step       = std::stoull(argv[3]);
  const uint64_t it         = std::stoull(argv[4]);
  const uint64_t rowId      = std::stoull(argv[5]);
  const uint64_t size       = std::stoull(argv[6]);
  std::ofstream time_file(argv[7]);
  const uint64_t n          = std::stoull(argv[8]);
  const uint64_t k          = std::stoull(argv[9]);
  const uint64_t period     = std::stoull(argv[10]);
  const uint64_t min_delay  = std::stoull(argv[11]);
  const uint64_t max_delay  = std::stoull(argv[12]);
  const uint64_t num_rows   = std::stoull(argv[13]);

  /* Read the row set */
  uint8_t *layout;
  cudaMalloc(&layout, size);
  std::ifstream row_set_file(argv[1]);
  RowList rows = read_row_from_file(row_set_file, layout);
  row_set_file.close();

  if ((int64_t)(rows.size() - 2 * num_victim - 1) < 0)
  {
    std::cout << CLI_PREFIX << "Error: "
              << "Not enough rows to generate the specified victims." << '\n';
    exit(-1);
  }

  /* Treat all rows as victim rows */
  std::vector<uint64_t> all_vics(num_rows);
  std::iota(all_vics.begin(), all_vics.end(), 0);
  set_rows(rows, all_vics, MEM_PAT::VICTIM_PAT, step);

  /* Dummy hammer to keep timing consistent, due to device startup time */
  start_simple_hammer(rows, all_vics, 1);

  /* Running */

  /* Testing delay amounts */
  int i = rowId;
  for (int delay_inc = 0; delay_inc < max_delay; delay_inc ++) {

    /* Initialize indexes of victims and aggressors */
    std::vector<uint64_t> victims = get_sequential_victims(rows, i, num_victim + 2, 4);
    std::vector<uint64_t> aggressors = get_aggressors(rows, i, num_victim + 1, 4);
    std::cout << CLI_PREFIX << "Chosen Victims:" << vector_str(victims) << '\n';
    std::cout << CLI_PREFIX << "Chosen Aggressors:" << vector_str(aggressors)
              << '\n';

    /* Sets the row and evict cache to store it in the memory. */
    set_rows(rows, victims, MEM_PAT::VICTIM_PAT, step);
    set_rows(rows, aggressors, MEM_PAT::AGGRES_PAT, step);
    evict_L2cache(layout);
    clear_L2cache_rows(rows, victims, step);
    
    /* Dummy hammer to keep timing consistent, due to device startup time */
    start_simple_hammer(rows, victims, 1);

    /* Start the hammering and measure the time */
    uint64_t time = start_multi_thread_hammer(rows, aggressors, it, n, k, aggressors.size(), min_delay + delay_inc, period);
    time_file << time << '\n';
    print_time(time);
    std::cout << CLI_PREFIX << "Average time per round:" << time / it << '\n';
  }

  time_file.close();

  return 0;
}