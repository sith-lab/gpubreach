#include <rh_utils.cuh>
#include <rh_impls.cuh>

#include <atomic>
#include <chrono>
#include <fstream>
#include <iostream>
#include <pthread.h>
#include <stdint.h>
#include <vector>

std::string CLI_PREFIX = "(simple_hammer): ";
int main(int argc, char *argv[])
{
  
  const uint64_t num_victim = std::stoull(argv[2]);
  const uint64_t step = std::stoull(argv[3]);
  const uint64_t it = std::stoull(argv[4]);
  const uint64_t rowId = std::stoull(argv[5]);
  const uint64_t size = std::stoull(argv[6]);
  
  /* Read the row set */
  uint8_t *layout;
  cudaMalloc(&layout, size);
  std::ifstream row_set_file(argv[1]);
  RowList rows = read_row_from_file(row_set_file, layout);
  if ((int64_t)(rows.size() - 2 * num_victim - 1) < 0)
  {
    std::cout << CLI_PREFIX << "Error: "
              << "Not enough rows to generate the specified victims." << '\n';
    exit(-1);
  }

  /* Initialize indexes of victims and aggressors */
  std::vector<uint64_t> victims = get_sequential_victims(rows, rowId, num_victim);
  std::vector<uint64_t> aggressors = get_aggressors(victims);
  std::cout << CLI_PREFIX << "Chosen Victims:" << vector_str(victims) << '\n';
  std::cout << CLI_PREFIX << "Chosen Aggressors:" << vector_str(aggressors)
            << '\n';

  /* Sets the row and evict cache to store it in the memory. */
  set_rows(rows, victims, MEM_PAT::VICTIM_PAT, step);
  set_rows(rows, aggressors, MEM_PAT::AGGRES_PAT, step);
  evict_L2cache(layout);
  clear_L2cache_rows(rows, victims, step);

  /* Dummy hammer to keep timing consistent, due to device startup time */
  start_simple_hammer(rows, aggressors, 1);
  cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess)
    {
      std::cerr << "Error: " << cudaGetErrorString(err) << '\n';
      exit(-1);
    }
  
  /* Initialize hammer kernel */
  uint64_t time = start_simple_hammer(rows, aggressors, it);
  print_time(time);

  std::cout << CLI_PREFIX << "Done\n";

  /* Output time */
  std::ofstream time_file(argv[7]);
  time_file << time;
  time_file.close();

  return 0;
}