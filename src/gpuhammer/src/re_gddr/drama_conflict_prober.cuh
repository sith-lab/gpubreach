#include <fstream>
#include <stdint.h>
#ifndef GPU_ROWHAMMER_RE_GDDR_CONFLICTPROBER_H
#define GPU_ROWHAMMER_RE_GDDR_CONFLICTPROBER_H

namespace re_gddr
{

class ConflictProber
{
private:
  uint64_t *mp_time_arr_device; /* GPU side time array */
  uint64_t *mp_time_arr_host;   /* HOST side time array */
  uint8_t *mp_addr_layout;         /* GPU memory layout */
  uint8_t **mp_addr_lst_device;    /* GPU side memory address array */
  uint8_t **mp_addr_lst_host;      /* HOST side memory address array */

  /* Input Arguments */
  uint64_t m_n;     /* How many accesses are done in a kernel */
  uint64_t m_range; /* RANGE we run the expriment over */
  uint64_t m_size;  /* SIZE of memory layout */
  uint64_t m_it;    /* Number of iteration for a single access */
  uint64_t m_step;  /* Steps we skip for each access */

public:
  ConflictProber (uint64_t n, uint64_t size, uint64_t range, uint64_t it,
              uint64_t step);
  ~ConflictProber ();

  uint8_t *
  get_addr_layout ()
  {
    return mp_addr_layout;
  };

  uint64_t
  get_exp_range ()
  {
    return m_range;
  };

  uint8_t **
  get_addr_lst_host ()
  {
    return mp_addr_lst_host;
  };

  uint64_t
  get_step ()
  {
    return m_step;
  };

  uint64_t get_addr_lst_elm (uint64_t idx);

  void
  set_exp_range (uint64_t range)
  {
    m_range = range;
  };
  
  void set_addr_lst_host (uint64_t idx, uint64_t ofs);

  /**
   * @brief Runs the device code to access addresses stored in ADDR_LST_HOST
   * at the same time. The code is written with the assumption that you are
   * unning it within 1 single block with <= 32 threads.
   *
   * @param file writes the time values to file.
   * @return uint64_t time value of the access.
   */
  uint64_t repeat_n_addr_exp (std::ofstream *file = nullptr, int modifier = 5);

  /**
   * @brief Runs f through the experiment range with a step size start from i.
   *
   * https://stackoverflow.com/questions/24392000/define-a-for-loop-macro-in-c
   * @tparam FUNCTION lambda type holder
   * @param f function to run for each step
   * @param i initial step
   */
  template <typename FUNCTION>
  inline void
  loop_range (FUNCTION &&f, uint64_t i = 0)
  {
    for (; i < m_range; i += m_step)
      std::forward<FUNCTION> (f) (i);
  }

  /**
   * @brief Runs f through until cond is not met with a step size and start
   * from i.
   *
   * @tparam FUNCTION (uint64_t) -> any
   * @tparam COND (uint64_t) -> bool
   * @param f function to run for each step
   * @param cond custom condition to stop
   * @param i initial step
   */
  template <typename FUNCTION, typename COND>
  inline void
  loop_range (FUNCTION &&f, COND &&cond, uint64_t i = 0)
  {
    for (; std::forward<COND> (cond) (i); i += m_step)
      std::forward<FUNCTION> (f) (i);
  }
};

__global__ void n_address_conflict_kernel(uint8_t **addr_arr,
                                          uint64_t *time_arr, int modifier = 5);
                                          
} // namespace re_gddr
#endif /* RE_GDDR_CONFLICTPROBER */
