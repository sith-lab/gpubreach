#include "drama_conflict_prober.cuh"
#include <iostream>

std::string CLI_PREFIX = "(conf-set): ";

int
main (int argc, char *argv[])
{
  uint64_t size = std::stoull (argv[1]);
  uint64_t range = std::stoull (argv[2]);
  uint64_t it = std::stoull (argv[3]);
  uint64_t step = std::stoull (argv[4]);
  uint64_t threshold = std::stoull (argv[5]);

  /* Offset to an address in Target Bank */
  uint64_t offset_to_bank = std::stoull (argv[6]);

  auto output_filename = argv[7];

  re_gddr::ConflictProber nc_test (2, size, range, it, step);

  // std::cin.clear();
  // int c;
  // while ((c = std::cin.get()) != '\n' && c != EOF);

  std::ofstream offset_file;
  offset_file.open (output_filename); /* Argument File name */

  /* Initialize address pairs */
  nc_test.set_addr_lst_host (0, offset_to_bank);
  nc_test.set_addr_lst_host (1, offset_to_bank);

  uint64_t base_delay = nc_test.repeat_n_addr_exp ();

  // warm-up GPU clock if cannot set to fixed rate.
  for (int i = 0; i < 100000; i++)
    base_delay = nc_test.repeat_n_addr_exp ();
  cudaDeviceSynchronize ();

  // Minimum delay to be considered a conflict
  uint64_t conflict_delay = base_delay + threshold;
  std::cout << base_delay << '\n';

  nc_test.loop_range ([&] (uint64_t step) {
    nc_test.set_addr_lst_host (1, step);

    /* Found conflict */
    if (conflict_delay < nc_test.repeat_n_addr_exp ())
      {
        /* Prepare for run of 'step' with itself */
        nc_test.set_addr_lst_host (0, step);

        /* Should be in reasonable range of base_delay as in same bank chip */
        if (std::abs ((int32_t)(nc_test.repeat_n_addr_exp ())
                      - (int32_t)(base_delay))
            <= 10)
          offset_file << step << '\n';

        /* Reset [0] */
        nc_test.set_addr_lst_host (0, offset_to_bank);
      }
  });

  offset_file.close ();
  return 0;
}
