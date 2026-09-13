cmake_minimum_required(VERSION 3.22 FATAL_ERROR)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

set(CMAKE_CUDA_ARCHITECTURES 80)

project(GPURowhammer LANGUAGES CXX CUDA)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --generate-line-info -O3 -Xcicc -O0 -Xptxas -O3 -gencode=arch=compute_80,code=sm_80")
find_package(CUDA 12.8 REQUIRED)

include_directories(../../include)
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)


# Hammer
add_library(hammer_lib ../../include/rh_kernels.cu ../../include/rh_utils.cu ../../include/rh_impls.cu ../../include/gpubreach_util.cu ../../include/ini.cpp ../../include/INIReader.cpp)
target_link_libraries(hammer_lib PUBLIC Threads::Threads)
target_link_libraries(hammer_lib PRIVATE cuda)

# Reverse Engineering
add_library(re_lib ./re_gddr/drama_conflict_prober.cu)
target_link_libraries(re_lib PUBLIC hammer_lib)

# Get Conflict Set
add_executable(conf_set ./re_gddr/conf_set_main.cu)
target_link_libraries(conf_set PUBLIC re_lib)

# Get Row Set
add_executable(row_set ./re_gddr/row_set_main.cu)
target_link_libraries(row_set PUBLIC re_lib)

# Get Bank Set
add_executable(bank_set ./re_gddr/bank_set_main.cu)
target_link_libraries(bank_set PUBLIC re_lib)

# Get Timing values
add_executable(gen_time ./re_gddr/gen_time_main.cu)
target_link_libraries(gen_time PUBLIC re_lib)

# Get Timing values
add_executable(gen_time_same ./re_gddr/gen_time_same_main.cu)
target_link_libraries(gen_time_same PUBLIC re_lib)

add_executable(load_modifiers ./re_gddr/load_modifiers_main.cu)
target_link_libraries(load_modifiers PUBLIC re_lib)

## Simple hammer
add_executable(simple_hammer ./hammer/simple_hammer.cu )
target_link_libraries(simple_hammer PRIVATE hammer_lib)
target_link_libraries(simple_hammer PRIVATE Threads::Threads)

add_executable(sync_delay ./hammer/synchronization.cu)
target_link_libraries(sync_delay PUBLIC hammer_lib)
target_link_libraries(sync_delay PRIVATE Threads::Threads)

add_executable(mt_sync_delay ./hammer/synchronization_multi_thread.cu)
target_link_libraries(mt_sync_delay PUBLIC hammer_lib)
target_link_libraries(mt_sync_delay PRIVATE Threads::Threads)

add_executable(st_sync_delay ./hammer/synchronization_single_thread.cu)
target_link_libraries(st_sync_delay PUBLIC hammer_lib)
target_link_libraries(st_sync_delay PRIVATE Threads::Threads)

add_executable(gpu_hammer ./hammer/gpu_hammer.cu)
target_link_libraries(gpu_hammer PUBLIC hammer_lib)
target_link_libraries(gpu_hammer PRIVATE Threads::Threads)

add_executable(trr_sampler ./hammer/trr_sampler_size.cu)
target_link_libraries(trr_sampler PUBLIC hammer_lib)
target_link_libraries(trr_sampler PRIVATE Threads::Threads)

add_executable(trh ./hammer/trh.cu)
target_link_libraries(trh PUBLIC hammer_lib)
target_link_libraries(trh PRIVATE Threads::Threads)
