#include "drama_conflict_prober.cuh"
#include <iostream>
#include <vector>

std::string CLI_PREFIX = "(load-modifiers): ";

int
main (int argc, char *argv[])
{
  uint64_t size = std::stoull (argv[1]);
  uint64_t range = 1;
  uint64_t it = std::stoull (argv[2]);
  uint64_t step = std::stoull (argv[3]);
  auto time_filename = argv[4];
  re_gddr::ConflictProber nc_test (2, size, range, it, step);

  std::ofstream time_file;
  time_file.open (time_filename); /* Argument File name */

  /* Initialize address pairs */
  nc_test.set_addr_lst_host (0, 0);
  nc_test.set_addr_lst_host (1, 0);
  nc_test.repeat_n_addr_exp ();

  // warm-up GPU clock if cannot set to fixed rate.
  for (int i = 0; i < 100000; i++)
    nc_test.repeat_n_addr_exp ();
  cudaDeviceSynchronize ();

  std::vector<std::string> modifiers
      = { "None", ".ca", ".cg", ".cs", ".cv", ".volatile" };
  for (int i = 0; i < modifiers.size (); i++)
    {
      uint64_t min = 0;
      nc_test.loop_range ([&nc_test, &time_file, &min, &i] (uint64_t step) {
        nc_test.set_addr_lst_host (0, step);
        nc_test.set_addr_lst_host (1, step);
        min = std::max (nc_test.repeat_n_addr_exp (nullptr, i), min);
      });
      time_file << modifiers[i] << '\t' << min << '\n';
    }

  time_file.close ();
  return 0;
}
