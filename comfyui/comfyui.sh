#!/bin/sh
# copyleft 2025-2026 Efenstor

# Run with -h or -? to display help

# To use with Zluda (https://github.com/vosen/ZLUDA) put the Zluda files to
# <script_dir>/lib

# The defaults should be almost crash-safe
# (use anything for True or nothing for False)
dynamic_vram=
reserve_vram=1.0    # default = 1.0
vram_headroom=0.5   # default = 0.5
gc_threshold=0.6    # default = 0.6
max_split_size=256  # default = 256
preview_method=auto
auto_launch=1
garbage_collector=
attention=0
profile_path="/sys/class/drm/card0/device/pp_power_profile_mode"
profile_compute=5  # cat /sys/class/drm/card0/device/pp_power_profile_mode
profile_default=0
cache_classic=
interactive=
lowvram=
dsm=
custom=
caffeinate=
firejail=
fj_net_none=
fj_whitelist=
tempdir_arg=
tempdir=
fast_disk=
high_ram=
offline=

get_current_profile() {
  echo $(cat "$1" | sed -n "s/ *\([0-9]*\).*\*.*/\1/p")
}

get_current_profile_name() {
  echo $(cat "$1" | sed -n "s/.* \(.*\)\*.*/\1/p")
}

uninitialize() {
  if [ "$new_profile" ]; then
    echo "Restoring the old amdgpu profile: $prev_profile ($prev_profile_name)"
    echo $prev_profile > "$profile_path"
  fi
  rm -f "$launcher"
  rm -f "$fjprofile"
  if [ -d "$tempdir" ]; then rm -rf "$tempdir"; fi
}

catchbreak() {
  uninitialize
  exit 1
}

# Change dir
script_dir="$(realpath $(dirname $0))"
cd "$script_dir"

# Parse the named parameters
optstr="?hac:dfgijklmnop:q:r:s:t:vw:y"
while getopts $optstr opt
do
  case "$opt" in
    h|\?) help=1 ;;
    a) auto_launch= ;;
    c) custom="$OPTARG" ;;
    d) dsm="--disable-smart-memory" ;;
    f) caffeinate=1 ;;
    g) garbage_collector=1 ;;
    i) interactive=1 ;;
    j) firejail=1 ;;
    k) fast_disk="--fast-disk" ;;
    l) lowvram="--lowvram" ;;
    m) high_ram="--high-ram" ;;
    n) fj_net_none=1 ;;
    o) switch_profile=1 ;;
    p) preview_method="$OPTARG" ;;
    q) attention="$OPTARG" ;;
    r) reserve_vram="$OPTARG" ;;
    s) max_split_size="$OPTARG" ;;
    t) gc_threshold="$OPTARG" ;;
    v) cache_classic="--cache-classic" ;;
    w) fj_whitelist="$OPTARG" ;;
    y) dynamic_vram=1 ;;
    :) echo "Missing argument for -$OPTARG" >&2
       exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

# Help
if [ "$help" ]; then
  echo
  echo "Usage: $0 [arguments]"
  echo
  echo "Arguments:"
  echo "-h or -?: show this help"
  echo "-a: don't auto-launch browser"
  echo "-c: custom parameters to be added to the ComfyUI command line"
  echo "-d: disable smart memory (same as -l but different strategy)"
  echo "-f: prevent sleep (requires the caffeine tool)"
  echo "-g: use garbage collector"
  echo "-i: interactive mode"
  echo "-j: run ComfyUI in firejail"
  echo "-k: use --fast-disk (recommended for NVMEs)"
  echo "-l: use --lowvram (makes everything very slow but fights OOM errors)"
  echo "-m: use --high-ram (recommended for >=32 GB of RAM)"
  echo "-n: restrict network in firejail (also adds --offline)"
  echo "-o: switch the amdgpu profile to COMPUTE, see NOTE 1 below (default=$profile_compute)"
  echo "-p: preview method (default=$preview_method)"
  echo "-q: specify attention method:"
  echo "    0 = split-cross-attention (default)"
  echo "    1 = quad-cross-attention"
  echo "    2 = sage-attention"
  echo "    3 = pytorch-cross-attention"
  echo "    4 = flash-attention"
  echo "    5 = ck-attention"
  echo "-r: reserve_vram size (GB, default=$reserve_vram)"
  echo "-s: garbage collector max_split_size size (MB, default=$max_split_size)"
  echo "-t: garbage collector threshold (0..1 VRAM, default=$gc_threshold)"
  echo "-v: use classic (aggressive) caching"
  echo "-w: whitelist a directory in firejail"
  echo "-y: use Dynamic VRAM"
  echo "
NOTE 1: For this option to work the profile file must be user-writable.
  You can acheive this by making a startup script with the following command:
  chmod a+w $profile_path"
  echo
  exit
fi

# Add the local lib path (for Zluda)
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:""$script_dir"/lib

# Replace bool with actual parameters
if [ "$garbage_collector" ]; then
  garbage_collector="PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:$gc_threshold,max_split_size_mb:$max_split_size,expandable_segments:True"
fi
if [ "$auto_launch" ]; then
  auto_launch="--auto-launch"
fi
if [ "$dynamic_vram" ]; then
  dynamic_vram="--enable-dynamic-vram"
fi
if [ "$reserve_vram" ]; then
  reserve_vram="--reserve-vram $reserve_vram"
fi
if [ "$vram_headroom" ]; then
  vram_headroom="--vram-headroom $vram_headroom"
fi

# Replace attention number with the actual parameter
case "$attention" in
  0) attention="--use-split-cross-attention" ;;
  1) attention="--use-quad-cross-attention" ;;
  2) attention="--use-sage-attention" ;;
  3) attention="--use-pytorch-cross-attention" ;;
  4) attention="--use-flash-attention" ;;
  5) attention="--use-ck-attention" ;;
esac

# Interactive questions
if [ "$interactive" ]; then
  read -p "Use --lowvram? (very slow but helps against OOM errors) y/N " a
  if [ "$a" = 'y' ]; then
    lowvram="--lowvram"
  else
    lowvram=
  fi
fi

# Try to get the current profile
if [ "$switch_profile" ]; then
  echo "Using amdgpu profile path: $profile_path"
  prev_profile=$(get_current_profile "$profile_path")
  if [ "$prev_profile" ]; then
    prev_profile_name=$(get_current_profile_name "$profile_path")
    echo "Current amdgpu profile: $prev_profile ($prev_profile_name)"
    echo "Setting amdgpu profile: $profile_compute (COMPUTE)"
    echo $profile_compute > "$profile_path"
    new_profile=$(get_current_profile "$profile_path")
    if [ $new_profile -eq $profile_compute ]; then
      echo "COMPUTE profile was set successfully"
    else
      echo "COMPUTE profile cannot be set"
      new_profile=
    fi
  fi
fi

# Create the firejail profile
if [ $firejail ]; then
  fjprofile=$(mktemp)
  tempdir=$(mktemp -d)
  tempdir_arg="--temp-directory \"$tempdir\""
  echo "
    include /etc/firejail/default.profile
    blacklist ${HOME}/.ssh
    blacklist ${HOME}/.gnupg
    whitelist $script_dir
    whitelist /opt/rocm
    read-write $script_dir/ComfyUI
    tmpfs $tempdir
    ignore private-dev
  " > "$fjprofile"
  if [ "$fj_whitelist" ]; then
    echo "whitelist $fj_whitelist" >> "$fjprofile"
  fi
  if [ $fj_net_none ]; then
    echo "net lo" >> "$fjprofile"
    offline="--offline"
  fi
  echo "
    nonewprivs
    dbus-user none
    dbus-system none
    caps.drop all
    noroot
    seccomp
    seccomp.drop @privileged
    restrict-namespaces
  " >> "$fjprofile"
fi

# Create the launcher file
launcher=$(mktemp)
echo '#!/bin/sh' > "$launcher"
if [ $garbage_collector ]; then
  echo "export $garbage_collector" >> "$launcher"
fi
echo "export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE" >> "$launcher"
echo "export MIOPEN_FIND_MODE=2" >> "$launcher"
if [ $firejail ]; then
  printf "firejail --profile=$fjprofile " >> "$launcher"
fi
echo "\"$script_dir\"/bin/python ComfyUI/main.py \
$tempdir_arg \
$lowvram \
$dsm \
$reserve_vram \
$vram_headroom \
--preview-method $preview_method \
--fast \
$dynamic_vram \
$cache_classic \
$attention \
$fast_disk \
$high_ram \
$custom \
$offline \
$auto_launch" >> "$launcher"
chmod +x "$launcher"

# excluded options
#export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
#--normalvram \
#--disable-triton-backend \
#--fp32-vae \
#--disable-nvml-pressure \

# Execute
trap "catchbreak" INT
if [ "$caffeinate" ]; then
  caffeinate "$launcher"
else
  "$launcher"
fi
uninitialize

