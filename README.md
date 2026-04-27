# PyTorch for Radeon RX 5600/5700 (gfx1010) building instructions for Debian 13 (trixie)

**IMPORTANT**: For the detailed explanation on what is this and how to use it see the instructions for building the older version: https://github.com/Efenstor/PyTorch-ROCm-gfx1010

**Prebuilt wheels** (2026-03-15): see the *prebuilt* directory.

These instructions are for building Torch 2.10, TorchVision 0.25 and TorchAudio 2.10 for Python 3.13 and ROCm 7.2 in Debian 13 (trixie) specifically for the *gfx101x* (RDNA 1) arch (e.g. Radeon RX 5600/5700). RDNA 2 & 3 will probably work out of the box from the [official wheel](https://pytorch.org/get-started/locally).

Note about kernel panics
--

If you experience occasional kernel panics when using PyTorch (for example, in ComfyUI those may occur during switching nodes), first of all try to increase the **reserved VRAM limit**. For example, I had to increase it to the absurd value of 10 GB for the kernel panics to disappear, and amazingly enough it didn't affect performance at all.

It also seems that more recent kernels from the backports (6.17 and later) are causing occasional freezes with PyTorch no matter the reserved VRAM limit, so I recommend to stick with the stable 6.12 kernels. 

Also try adding the following parameters to the kernel mode line:

    amd_iommu=off amdgpu.cwsr_enable=0 amdgpu.gttsize=8192 ttm.pages_limit=32768000 ttm.page_pool_size=32768000 amdttm.pages_limit=32768000 amdttm.page_pool_size=32768000
    
Add it to the *GRUB_CMDLINE_LINUX_DEFAULT* line in `/etc/default/grub`, execute update-grub and reboot.

Requirements
--

    ROCm 7.2 (see the section below)
    build-essential
    clang
    cmake
    python3
    git

ROCm 7.2
--

**IMPORTANT**: The version of ROCm included with Debian 13 is both incomplete and outdated. You have to install ROCm 7.2.0 from the AMD's official Linux repositories.

The easiest way is to download and install *amdgpu-install* as described [here](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html). Then execute `apt install rocm` as root. **Do not** install the AMDGPU driver, the one included with Debian is totally enough. Another way is to [do it manually](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/detailed-install.html).

Download and unpack the missing RocBLAS libraries into */opt/rocm/lib/rocblas/library* (as root):

```
wget https://github.com/Efenstor/PyTorch-ROCm-gfx1010-Debian13/raw/refs/heads/main/files/rocblas_library_gfx1010.tar.gz
tar xv -f rocblas_library_gfx1010.tar.gz -C /opt/rocm/lib/rocblas/library
```

**IMPORTANT**: After any upgrade of ROCm you will likely lose those additional libraries so keep them at hand in case you'll have to add them again. Theoretically you can disable upgrading ROCm completely by using the `apt-mark hold rocm` command. Anyway I recommend to stick to the 7.2 branch of ROCm, so make sure that in /etc/apt/sources.list.d/rocm.list you have the version 7.2 specified directly like this:

```
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
```

After that install all the rest of the requirements using the usual `apt install`.

Torch
--

    python -m venv pytorch-2.10
    cd pytorch-2.10
    source bin/activate
    git clone https://github.com/pytorch/pytorch.git --branch=release/2.10 --recurse-submodules pytorch-release-2.10-git
    cd pytorch-release-2.10-git
    wget -P third_party/composable_kernel/include/ck https://github.com/Efenstor/PyTorch-ROCm-gfx1010-Debian13/raw/refs/heads/main/files/ck.hpp
    wget -P third_party/composable_kernel/include/ck_tile/core https://github.com/Efenstor/PyTorch-ROCm-gfx1010-Debian13/raw/refs/heads/main/files/config.hpp
    pip install -r requirements.txt
    python tools/amd_build/build_amd.py
    MAX_JOBS=$(nproc --all) USE_STATIC_MKL=1 USE_ROCM_CK_GEMM=1 USE_ROCM_CK_SDPA=1 USE_FLASH_ATTENTION=OFF USE_MEM_EFF_ATTENTION=OFF PYTORCH_ROCM_ARCH=gfx1010 python3 setup.py bdist_wheel
    pip install dist/torch-2.10.0a0+git911aa98-cp313-cp313-linux_x86_64.whl

The resulting wheel file will be in the `dist` directory.

**NOTE 1:** `USE_FLASH_ATTENTION=OFF` and `USE_MEM_EFF_ATTENTION=OFF` are needed because both *flash_attention* and *mem_eff_attention* use *aotriton*, and *aotriton* does not support the gfx101x arch. Without these options compilation fails. A possible alternative is to change the value in *cmake/External/aotriton.cmake* from `-DAOTRITON_TARGET_ARCH:STRING=${PYTORCH_ROCM_ARCH}` to `-DAOTRITON_TARGET_ARCH:STRING=gfx1100` but the consequences of forcing a partially-compatible architecture are unknown and I didn't try it.

**NOTE 2:** Instead of the `wget` commands you can clone this repository and use the files from the `files` directory. Those files were taken from the *develop* branch of [composable_kernel](https://github.com/ROCm/composable_kernel) and include the needed support for the gfx10xx arch while the original files don't. Although it's trivial to make the patches it's even easier to replace the whole files.

TorchVision
--

Execute from the same venv as was used for building *torch* (or any other with the *torch* wheel installed).

    git clone https://github.com/pytorch/vision.git --branch=release/0.25 --recurse-submodules vision-release-0.25-git
    cd vision-release-0.25-git
    pip install setuptools==81.0.0
    MAX_JOBS=$(nproc --all) python3 setup.py bdist_wheel

The resulting wheel file will be in the `dist` directory.

TorchAudio
--

    git clone https://github.com/pytorch/audio.git --branch=release/2.10 --recurse-submodules audio-release-2.10-git
    cd audio-release-2.10-git
    pip install -r requirements.txt
    MAX_JOBS=$(nproc --all) python3 setup.py bdist_wheel

bitsandbytes
--

No building required, version 0.49.2 supports ROCm 7.2.0 out of the box:

    pip install -U bitsandbytes

ONNX
--

No build for ROCm 7.2.0 + Python 3.12 is available officially from AMD (see [here](https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/)) and I didn't try yet to compile it from the sources.

For now you may try the official wheel:

    pip install -U onnxruntime
    
I cannot prove definitely that it utilizes the GPU but judging by the GPU load graph and the noises my graphics card makes it does, probably that's because I have *migraphx* installed, which goes together with ROCm 7.2. 

Triton
--

Probably won't work for gfx10xx (see the *NOTE 1* in the *Torch* compilation instructions above for explaination) but still worth a try.

    pip install -U https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton-3.6.0%2Brocm7.2.0.gitba5c1517-cp313-cp313-linux_x86_64.whl

