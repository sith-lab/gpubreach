#include "drama_conflict_prober.cuh"
#include <rh_utils.cuh>
#include <cuda.h>
#include <algorithm>
#include <gpubreach_util.cuh>
#include <iostream>
namespace re_gddr
{

ConflictProber::ConflictProber (uint64_t n, uint64_t size, uint64_t range, uint64_t it,
                        uint64_t step)
    : m_n{ n }, m_size{ size }, m_range{ range }, m_it{ it }, m_step{ step }
{
  size_t total_byte = get_memory_limit ();

  int device;
  cudaGetDevice (&device);
  cudaMallocManaged (&mp_addr_layout, total_byte);
  cudaMemPrefetchAsync (mp_addr_layout, m_size, device);
  cudaDeviceSynchronize ();
  // cudaMalloc (&mp_addr_layout, m_size);
  cudaMalloc (&mp_time_arr_device, sizeof (uint64_t) * m_it);
  cudaMalloc (&mp_addr_lst_device, m_n * sizeof (uint8_t *));
  std::cout << (void*) mp_addr_layout << '\n';
  mp_addr_lst_host = new uint8_t *[m_n];
  mp_time_arr_host = new uint64_t[m_it];
}

ConflictProber::~ConflictProber ()
{
  cudaFree (mp_addr_layout);
  cudaFree (mp_time_arr_device);
  cudaFree (mp_addr_lst_device);
  delete[] mp_addr_lst_host;
  delete[] mp_time_arr_host;
}

uint64_t
ConflictProber::get_addr_lst_elm (uint64_t idx)
{
  if (idx >= m_n)
    throw std::out_of_range ("Index greater than address list size");

  return mp_addr_lst_host[idx] - mp_addr_layout;
}

void
ConflictProber::set_addr_lst_host (uint64_t idx, uint64_t ofs)
{
  if (idx >= m_n)
    throw std::out_of_range ("Index greater than address list size");

  mp_addr_lst_host[idx] = mp_addr_layout + ofs;
}

uint64_t
ConflictProber::repeat_n_addr_exp (std::ofstream *file, int modifier)
{
  /* Copy the addresses to GPU usable memory */
  cudaMemcpy (mp_addr_lst_device, mp_addr_lst_host,
              m_n * sizeof (uint8_t *), cudaMemcpyHostToDevice);

  /* Run experiment EXP_IT times to avoid noise */
  for (uint64_t i = 0; i < m_it; i++)
      n_address_conflict_kernel<<<1, m_n>>> (mp_addr_lst_device,
                                             mp_time_arr_device + i, modifier);
  cudaDeviceSynchronize ();

  /* Copy the time values from GPU to HOST usable memory */
  cudaMemcpy (mp_time_arr_host, mp_time_arr_device, sizeof (uint64_t) * m_it,
              cudaMemcpyDeviceToHost);

  /* The true delay is consistent and noise will only cause the delay to go
     up, thus we take the minimum. Convert it to NS for better understanding.
  */
  // std::cout << *std::min_element (mp_time_arr_host, mp_time_arr_host + m_it) << '\n';
  uint64_t min
      = toNS (*std::min_element (mp_time_arr_host, mp_time_arr_host + m_it));

  if (file)
    *file << min << '\n';

  return min;
}

/**
 * @brief Stores the time of uncached access of addr_access in time_arr.
 * This function requires synchronized access with __syncthreads, please
 * make sure no divergence happends on places where this function is called.
 *
 * @param addr_access address top access
 * @param time_arr place to store timing valueW
 */
__forceinline__ __device__ void
uncached_access_timing_device(uint8_t *addr_access, uint64_t *time_arr, int modifier)
{
  uint64_t temp __attribute__((unused)), clock_start, clock_end;
  asm volatile("{\n\t"
               "discard.global.L2 [%0], 128;\n\t"
               "}" ::"l"(addr_access));
  switch (modifier)
  {
    case 0:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
    case 1:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global.ca %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
    case 2:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global.cg %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
    case 3:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global.cs %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
    case 4:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global.cv %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
    case 5:
      clock_start = clock64();
      asm volatile("{\n\t"
                  "ld.u8.global.volatile %0, [%1];\n\t"
                  "}"
                  : "=l"(temp)
                  : "l"(addr_access));
      clock_end = clock64();
      break;
  }

  *time_arr = clock_end - clock_start;
}

__global__ void n_address_conflict_kernel(uint8_t **addr_arr,
                                          uint64_t *time_arr,
                                          int modifier)
{
  uncached_access_timing_device(*(addr_arr + threadIdx.x),
                                time_arr + threadIdx.x,
                                modifier);
}

} // namespace re_gddr
