#include "drama_conflict_prober.cuh"
#include <iostream>


std::string CLI_PREFIX = "(gen-time): ";

int
main (int argc, char *argv[])
{
  uint64_t size = std::stoull (argv[1]);
  uint64_t range = std::stoull (argv[2]);
  uint64_t it = std::stoull (argv[3]);
  uint64_t step = std::stoull (argv[4]);
  auto time_filename = argv[5];

  re_gddr::ConflictProber nc_test (2, size, range, it, step);

  std::ofstream *time_file = new std::ofstream;
  time_file->open (time_filename);

  /* Initialize address pairs */
  nc_test.set_addr_lst_host (0, 0);
  nc_test.set_addr_lst_host (1, 0);
  nc_test.repeat_n_addr_exp ();

  // warm-up GPU clock if cannot set to fixed rate.
  for (int i = 0; i < 100000; i++)
    nc_test.repeat_n_addr_exp ();
  cudaDeviceSynchronize ();

  nc_test.loop_range ([&nc_test, time_file] (uint64_t step) {
    nc_test.set_addr_lst_host (1, step);
    nc_test.repeat_n_addr_exp (time_file);
  });

  time_file->close ();
  return 0;
}
