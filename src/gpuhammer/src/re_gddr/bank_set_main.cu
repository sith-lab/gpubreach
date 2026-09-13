#include "drama_conflict_prober.cuh"
#include <algorithm>
#include <iostream>
#include <map>
#include <unordered_map>
#include <vector>

std::string CLI_PREFIX = "(bank-set): ";

/* Idea:
     - Iterate through each address
     - for each address, find an address that conflict (same bank)
     - Check if any of the addresses in the bank set conflict with that
   address. If no, then it is a new bank and add it to bank set
     - (Also keep each address found and seen in a seen_set. If has a hit,
        remove it to save space.)
     - Not sure how to know how many banks there are yet but can just use a
        max for it.
*/

/* Key is the first ever value seen of a bank. Value is a pair of where <0>
   is the base_delay and <1> is the next conflicting address of Key.
*/
using Bank_Map = std::unordered_map<uint64_t, std::pair<uint64_t, uint64_t>>;

static uint64_t next_conf_step (re_gddr::ConflictProber &nc_test,
                                uint64_t step /* step to source address */,
                                uint64_t base_delay, uint64_t threshold);

static bool in_bank_set (re_gddr::ConflictProber &nc_test, Bank_Map &bank_map,
                         uint64_t step, uint64_t base_delay,
                         uint64_t threshold);

int
main (int argc, char *argv[])
{
  uint64_t size = std::stoull (argv[1]);
  uint64_t range = std::stoull (argv[1]);
  uint64_t it = std::stoull (argv[2]);
  uint64_t step = std::stoull (argv[3]);
  uint64_t threshold = std::stoull (argv[4]);
  uint64_t max_bank = std::stoull (argv[5]);
  auto banks_filename = argv[6];

  re_gddr::ConflictProber nc_test (2, size, range, it, step);

  Bank_Map bank_map;
  std::ofstream banks_file (banks_filename);

  /* Initialize address pairs and data structures*/
  nc_test.set_addr_lst_host (0, 0);
  nc_test.set_addr_lst_host (1, 0);
  uint64_t temp_base = nc_test.repeat_n_addr_exp ();

  // warm-up GPU clock if cannot set to fixed rate.
  for (int i = 0; i < 100000; i++)
    temp_base = nc_test.repeat_n_addr_exp ();
  cudaDeviceSynchronize ();

  bank_map[0]
      = { temp_base, next_conf_step (nc_test, 0, temp_base, threshold) };

  nc_test.loop_range (
      [&nc_test, &bank_map, threshold] (uint64_t step) {
        // Find address's base_delay
        nc_test.set_addr_lst_host (0, step);
        nc_test.set_addr_lst_host (1, step);
        uint64_t base_delay = nc_test.repeat_n_addr_exp ();

        // Find if address is part of a found bank.
        if (!in_bank_set (nc_test, bank_map, step, base_delay, threshold))
          /* Add it and its next conflicting address to bank set */
          bank_map[step]
              = { base_delay,
                  next_conf_step (nc_test, step, base_delay, threshold) };
      },

      /* Stop when end of range or reached max_bank size */
      [&bank_map, &nc_test, max_bank] (uint64_t step) {
        return step < nc_test.get_exp_range () && max_bank != bank_map.size ();
      },

      /* Skip the initial 0 since it is our first bank */
      nc_test.get_step ());

  std::vector<uint64_t> res;
  for (auto &it : bank_map)
    res.push_back (it.first);

  std::sort (res.begin (), res.end ());

  for (const auto &item : res)
    banks_file << item << '\n';

  banks_file.close ();

  return 0;
}

/**
 * @brief Returns the next address step that conflicts with this_step. This
 * funtion doesn't handle the case where there isn't a conflict since by our
 * discovery, most of the banks are identifiable in the first few blocks of
 * memory.
 *
 * @param nc_test
 * @param this_step
 * @param base_delay
 * @param threshold
 * @return uint64_t
 */
uint64_t
next_conf_step (re_gddr::ConflictProber &nc_test, uint64_t this_step,
                uint64_t base_delay, uint64_t threshold)
{

  uint64_t conflict_delay = base_delay + threshold;
  nc_test.set_addr_lst_host (0, this_step);

  /* Unconventionally, we are choosing a point to stop so we will put the
     lambda in condition section.

     We start looping from step + nc_test.step since testing the same addr
     is unncessary.
  */
  nc_test.loop_range (
      [] (uint64_t it_step) {},
      [&nc_test, conflict_delay, base_delay, this_step] (uint64_t it_step) {
        if (it_step >= nc_test.get_exp_range ())
          return false;

        /* Run against the it_step */
        nc_test.set_addr_lst_host (1, it_step);

        if (conflict_delay < nc_test.repeat_n_addr_exp ())
          {

            /* Run experiement on it_step with itself */
            nc_test.set_addr_lst_host (0, nc_test.get_addr_lst_elm (1));

            /* Should be in reasonable range of base_delay as in same bank chip
             */
            if (std::abs ((int32_t)(nc_test.repeat_n_addr_exp ())
                          - (int32_t)(base_delay))
                <= 10)
              return false;

            /* Reset [0] to original step */
            nc_test.set_addr_lst_host (0, this_step);
          }

        return true;
      },
      this_step + nc_test.get_step ());

  return nc_test.get_addr_lst_elm (1);
}

/**
 * @brief Return truth value based on whether this_step is in an already seen
 * bank in bank_map.
 *
 * @param nc_test
 * @param bank_map
 * @param this_step
 * @param base_delay
 * @param threshold
 * @return true this_step is in the bank set
 * @return false otherwise
 */
bool
in_bank_set (re_gddr::ConflictProber &nc_test, Bank_Map &bank_map,
             uint64_t this_step, uint64_t base_delay, uint64_t threshold)
{
  nc_test.set_addr_lst_host (0, this_step);

  /* To know conflict:
      1.  test whether the two addresses have similar base_delay. If not,
          they cannot conflict as from different chip
      2.  If similar, they could be from same bank, so test conflict.
      3. if conflict, same bank, otherwise, diff bank, bring it in to map */
  for (auto it = bank_map.begin (); it != bank_map.end (); it++)
    {
      if (std::abs ((int32_t)(it->second.first) - (int32_t)(base_delay)) > 10)
        continue;

      /* test original address */
      nc_test.set_addr_lst_host (1, it->first);
      if (base_delay + threshold < nc_test.repeat_n_addr_exp ())
        return true;

      /* test address in the same bank but another row to prevent same row */
      nc_test.set_addr_lst_host (1, it->second.second);
      if (base_delay + threshold < nc_test.repeat_n_addr_exp ())
        return true;
    }
  return false;
}
