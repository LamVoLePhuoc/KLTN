#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: prepare_act4_tests_wsl.sh <project-dir> <checkout> <work-dir>" >&2
    exit 2
fi

project_dir=$(realpath "$1")
checkout=$(realpath "$2")
work_dir=$(realpath -m "$3")
pinned_commit=792e55702c6ffff5c8432670086f126f40b88c9e

export PATH="$HOME/.local/bin:$HOME/.local/sail-riscv-0.16/bin:$HOME/.local/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH"

for command_name in make git mise riscv-none-elf-gcc riscv-none-elf-objdump sail_riscv_sim; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing ACT4 dependency in WSL: $command_name" >&2
        exit 3
    fi
done

actual_commit=$(git -C "$checkout" rev-parse HEAD)
if [[ "$actual_commit" != "$pinned_commit" ]]; then
    echo "ACT4 checkout must be pinned to $pinned_commit; found $actual_commit" >&2
    exit 4
fi

gcc_version=$(riscv-none-elf-gcc -dumpfullversion)
sail_version=$(sail_riscv_sim --version | head -n 1)
if [[ "$gcc_version" != 15.2.0 ]]; then
    echo "ACT4 requires GCC 15.2.0; found $gcc_version" >&2
    exit 5
fi
if [[ "$sail_version" != 0.16 ]]; then
    echo "ACT4 requires Sail RISC-V 0.16; found $sail_version" >&2
    exit 6
fi

config_dir="$work_dir/config/kltn-rv32ima"
elf_root="$work_dir/work"
mkdir -p "$config_dir" "$elf_root"

official_config="$checkout/config/sail/sail-RVI20U32"
cp "$project_dir/verification/arch_test/act4/kltn-rv32ima.yaml" "$config_dir/kltn-rv32ima.yaml"
cp "$official_config/sail.json" "$config_dir/sail.json"
cp "$project_dir/verification/arch_test/act4/rvmodel_macros.h" "$config_dir/rvmodel_macros.h"
cp "$project_dir/verification/arch_test/act4/link.ld" "$config_dir/link.ld"

# The stock Sail RVI20U32 model places executable RAM at 0x8000_0000,
# whereas this core and the architectural-test harness boot from 0x0000_1000
# and expose 1 MiB of physical memory.  Turn the stock 4 KiB ROM region into
# the DUT's 0x1000..0xFFFFF main-memory window; retain all other Sail settings.
sed -i '/\/\/ ROM/,/"include_in_device_tree"/ {
  /"size": {/,/}/ s/"value": "0x1000"/"value": "0x000FF000"/
  s/"mem_type": "IOMemory"/"mem_type": "MainMemory"/
  s/"executable": false/"executable": true/
  s/"writable": false/"writable": true/
  s/"atomic_support": "AMONone"/"atomic_support": "AMOCASQ"/
  s/"reservability": "RsrvNone"/"reservability": "RsrvEventual"/
}' "$config_dir/sail.json"
# Keep the Sail reference model on the same privileged architecture revision
# declared by the RTL's UDB configuration.
sed -i 's/"privileged_isa_version": "Privileged_ISA_1_12"/"privileged_isa_version": "Privileged_ISA_1_11"/' \
    "$config_dir/sail.json"
# The stock RVI20U32 Sail profile also enables compressed and floating-point
# subextensions that are not present in the DUT UDB file.  In particular,
# leaving Zca enabled changes IALIGN to 16 and makes mepc[1] observable in the
# reference model, while this RV32IMA core has fixed IALIGN=32.  Keep the Sail
# architectural state aligned with the implemented RTL rather than weakening
# the RTL's xEPC alignment semantics to match an unrelated stock profile.
sed -i \
    -e '/"M": {/,/}/ s/"mutable_misa": true/"mutable_misa": false/' \
    -e '/"A": {/,/}/ s/"mutable_misa": true/"mutable_misa": false/' \
    -e '/"F": {/,/}/ s/"supported": true/"supported": false/' \
    -e '/"D": {/,/}/ s/"supported": true/"supported": false/' \
    -e '/"C": {/,/}/ s/"mutable_misa": true/"mutable_misa": false/' \
    -e '/"Zca": {/,/}/ s/"supported": true/"supported": false/' \
    -e '/"Zcf": {/,/}/ s/"supported": true/"supported": false/' \
    -e '/"Zcd": {/,/}/ s/"supported": true/"supported": false/' \
    -e 's/"fs_legal_states": "ExtContext_FourState"/"fs_legal_states": "ExtContext_Off"/' \
    "$config_dir/sail.json"
rom_block=$(sed -n '/\/\/ ROM/,/"include_in_device_tree"/p' "$config_dir/sail.json")
for expected in \
    '"value": "0x000FF000"' \
    '"mem_type": "MainMemory"' \
    '"executable": true' \
    '"writable": true' \
    '"atomic_support": "AMOCASQ"' \
    '"reservability": "RsrvEventual"'; do
    if ! grep -Fq "$expected" <<<"$rom_block"; then
        echo "failed to specialize Sail memory map: missing $expected" >&2
        exit 9
    fi
done
if ! grep -Fq '"privileged_isa_version": "Privileged_ISA_1_11"' "$config_dir/sail.json"; then
    echo "failed to select Sail Privileged ISA 1.11" >&2
    exit 10
fi
for extension_name in F D Zca Zcf Zcd; do
    extension_block=$(sed -n "/\"$extension_name\": {/,/}/p" "$config_dir/sail.json")
    if ! grep -Fq '"supported": false' <<<"$extension_block"; then
        echo "failed to disable unsupported Sail extension $extension_name" >&2
        exit 11
    fi
done
for extension_name in M A C; do
    extension_block=$(sed -n "/\"$extension_name\": {/,/}/p" "$config_dir/sail.json")
    if ! grep -Fq '"mutable_misa": false' <<<"$extension_block"; then
        echo "failed to fix immutable Sail misa.$extension_name" >&2
        exit 12
    fi
done
if ! grep -Fq '"fs_legal_states": "ExtContext_Off"' "$config_dir/sail.json"; then
    echo "failed to make mstatus.FS read-only zero for the non-F DUT" >&2
    exit 13
fi
test_config="$config_dir/test_config.yaml"
printf '%s\n' \
    'name: kltn-rv32ima' \
    "compiler_exe: $(command -v riscv-none-elf-gcc)" \
    "objdump_exe: $(command -v riscv-none-elf-objdump)" \
    "ref_model_exe: $(command -v sail_riscv_sim)" \
    'udb_config: kltn-rv32ima.yaml' \
    'linker_script: link.ld' \
    'dut_include_dir: .' \
    'include_priv_tests: False' > "$test_config"

cd "$checkout"
export UV_LINK_MODE=copy
mise exec -- make \
    "CONFIG_FILES=$test_config" \
    "WORKDIR=$elf_root" \
    'EXTENSIONS=I,M,Zaamo,Zalrsc,Zicsr,Zifencei' \
    'JOBS=1'

elf_dir="$elf_root/kltn-rv32ima/elfs"
if [[ ! -d "$elf_dir" ]]; then
    echo "ACT4 did not produce $elf_dir" >&2
    exit 7
fi

elf_count=$(find "$elf_dir" -type f -name '*.elf' -printf '.' | wc -c)
if [[ "$elf_count" -eq 0 ]]; then
    echo "ACT4 produced no self-checking ELFs" >&2
    exit 8
fi

manifest="$work_dir/act4-manifest.txt"
printf '%s\n' \
    "ACT4_COMMIT=$actual_commit" \
    "ACT4_GCC_VERSION=$gcc_version" \
    "ACT4_SAIL_VERSION=$sail_version" \
    "ACT4_ELF_DIR=$elf_dir" \
    "ACT4_ELF_COUNT=$elf_count" > "$manifest"
cat "$manifest"
