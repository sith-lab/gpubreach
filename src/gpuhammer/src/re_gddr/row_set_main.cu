#include "drama_conflict_prober.cuh"
#include <iostream>
#include <map>
#include <vector>

std::string CLI_PREFIX = "(row-set): ";

/* Key is the first ever address in row, Value is the row including key */
using Conf_Map = std::map<uint64_t, std::vector<uint64_t>>;

/**
 * @brief Return a tuple query result where <0> contians whether the address
 * pair in nc_test is in the same row and <1> contains the address in conf_map
 * if <0> is true.
 *
 * @param conf_map
 * @param nc_test
 * @param base_delay
 * @param threshold
 * @return std::tuple<bool, uint64_t>
 */
static std::tuple<bool, uint64_t>
find_same_row (Conf_Map &conf_map, re_gddr::ConflictProber &nc_test,
               uint64_t conf_delay);

int
main (int argc, char *argv[])
{
  uint64_t size = std::stoull (argv[1]);
  uint64_t range = 0; // UNUSED
  uint64_t it = std::stoull (argv[2]);
  uint64_t step = 32; // UNUSED
  uint64_t threshold = std::stoull (argv[3]);
  uint64_t offset_to_bank = std::stoull (argv[4]);
  uint64_t max_row = std::stoull (argv[5]);
  auto conf_set_filename = argv[6];

  re_gddr::ConflictProber nc_test (2, size, range, it, step);

  Conf_Map conf_map{ { offset_to_bank, { offset_to_bank } } };
  std::vector<uint64_t> conf_vec{ offset_to_bank };

  /* Initialize address pairs */
  nc_test.set_addr_lst_host (0, offset_to_bank);
  nc_test.set_addr_lst_host (1, offset_to_bank);
  uint64_t conf_delay = nc_test.repeat_n_addr_exp () + threshold;
  for (int i = 0; i < 100000; i++)
    {
      conf_delay = nc_test.repeat_n_addr_exp () + threshold;
    }
  cudaDeviceSynchronize ();

  std::string buf;
  std::ifstream conf_set_file (conf_set_filename);

  /* If max_row is 0, it will obviously get all row since conf_map.size() == 1
     from the start.
  */
  while (conf_set_file.peek () != EOF && max_row != conf_map.size ())
    {
      while (std::getline (conf_set_file, buf))
        {
          uint64_t conf_step = std::stoull (buf.c_str ());

          /* Address to be tested for whether it should be in conf_set */
          nc_test.set_addr_lst_host (0, conf_step);

          /* <0>: Bool, <1>: row id step or NULL */
          auto qry_res = find_same_row (conf_map, nc_test, conf_delay);

          if (std::get<0> (qry_res))
            conf_map[std::get<1> (qry_res)].push_back (conf_step);
          else
            {
              conf_map[conf_step] = { conf_step };
              break; /* New row added so we breakout to check max_row */
            }
        }
    }

  std::ofstream row_set_file (argv[7]);

  /* First row is a dummy row */
  conf_map.erase (offset_to_bank);
  for (const auto it : conf_map)
    {
      for (const auto a : it.second)
        row_set_file << a << '\t';
      row_set_file << '\n';
    }

  conf_set_file.close ();
  return 0;
}

static std::tuple<bool, uint64_t>
find_same_row (Conf_Map &conf_map, re_gddr::ConflictProber &nc_test,
               uint64_t conf_delay)
{
  int i = 5;
  bool all_conflict = true;

  /* Heuristic: If we do not see the a conflict soon, it is a new row. */
  for (auto it = conf_map.rbegin (); it != conf_map.rend () && i != 0; it++)
    {
      /* Run against element in conf_map */
      nc_test.set_addr_lst_host (1, it->first);

      uint64_t time = nc_test.repeat_n_addr_exp ();
      all_conflict &= (time > conf_delay);

      if (!all_conflict)
        return { true, it->first };

      i--;
    }

  return { false, 0 };
}
