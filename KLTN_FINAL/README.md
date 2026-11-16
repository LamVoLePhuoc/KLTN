# Quad-Core RISC-V RV32IMA with MESI Cache Coherence

Mã nguồn khóa luận thiết kế và kiểm chứng một hệ thống xử lý RISC-V RV32IMA
bốn lõi trên FPGA. Phiên bản active sử dụng địa chỉ vật lý trực tiếp, private
L1 instruction/data cache cho từng core, shared L2 cache, MESI cache coherence,
AHB-Lite trong CPU subsystem và AXI4 ở system boundary.

Thiết kế được kiểm tra với Xilinx Vivado/XSIM 2022.2 và target part của VCU129:

```text
xcvu29p-fsga2577-2L-e
```

Synthesis top của cấu hình active:

```text
quad_core_axi_wrapper_ahb
```

MESI là cấu hình mặc định (`MESI_ENABLE=1`). MSI (`MESI_ENABLE=0`) được giữ làm
baseline để so sánh protocol traffic, timing và tài nguyên.

## 1. Phạm vi kiến trúc hiện tại

### CPU subsystem

- Bốn core RV32IMA, pipeline 5 stage.
- Hỗ trợ integer, multiply/divide và atomic/LR-SC datapath.
- CSR, trap và các privilege mode M/S/U ở mức RTL hiện tại.
- Active hierarchy sử dụng physical address trực tiếp.
- Không instantiate TLB, PTW hoặc Sv32 address translation trong active top.
- Các output page-fault được giữ để tương thích interface nhưng không đại diện
  cho một Sv32 implementation active.

### Memory hierarchy

- Private L1 instruction cache cho mỗi core.
- Private L1 data cache cho mỗi core.
- Cache line 32 byte.
- Shared L2 cache.
- Write-back, refill, dirty-line forwarding và cache maintenance.
- Eight-beat cache-line transfer trên AHB/AXI burst path.

### Coherence và interconnect

- MESI coherence là cấu hình chính.
- MSI được dùng làm baseline verification.
- Bốn I-cache và bốn D-cache tạo tám AHB-Lite master sources.
- Shared cache/coherence controller và shared L2 nằm sau AHB arbitration.
- AXI4 master boundary dùng để kết nối external memory subsystem.
- MESI hỗ trợ `E -> M` silent upgrade khi một core là sole reader của cache line.

### Ngoài phạm vi active source manifest

- DMA không nằm trong `rtl/files.f` và không thuộc kết quả full-SoC timing dưới
  đây.
- Legacy Sv32 TLB/PTW/MMU không nằm trong active hierarchy.
- Board-level DDR, Clocking Wizard, pin assignment và bitstream bring-up chưa
  được sign off trong source-only bundle này.

File `rtl/mmu/cache_controller_mmu.v` giữ tên lịch sử, nhưng trong active
hierarchy nó thực hiện cache/coherence/memory control; nó không biến active
system thành một Sv32 virtual-memory design.

## 2. Cấu trúc repository

```text
KLTN_FINAL/
├── rtl/
│   ├── files.f                  Active RTL manifest
│   ├── core/                    RV32IMA pipeline, CSR và trap
│   ├── cache/                   Private L1, shared L2 và maintenance
│   ├── coherence/               MSI/MESI compatibility logic
│   ├── interconnect/ahb/        AHB-Lite adapters và 8M1S arbiter
│   ├── soc/                     Quad-core SoC và AXI wrappers
│   ├── common/                  Reset synchronizer
│   ├── boot/                    Optional boot controller source
│   ├── debug/                   Optional debug buffer
│   └── mmu/                     Active cache/memory controller (historical name)
├── sim/                         Self-checking Verilog testbenches
├── sw/
│   ├── arch_test_smoke.S
│   └── workloads/               Compiled four-hart cache workload
├── scripts/                     XSIM, workload, ACT4 và PPA runners
├── verification/arch_test/      ACT4 configuration and DUT macros
├── constraint/
│   └── soc_internal_250mhz.xdc  Internal 4.000 ns clock constraint
├── .gitignore
└── README.md
```

`rtl/files.f` là source of truth cho active RTL. Không compile mù toàn bộ các
file RTL bên ngoài manifest khi tái tạo kết quả.

## 3. Yêu cầu công cụ

### Cơ bản

- Xilinx Vivado/XSIM 2022.2.
- Windows PowerShell cho các `.ps1` runner.
- Target part `xcvu29p-fsga2577-2L-e` hoặc VCU129 board part tương ứng.

### Compiled workload

Script mặc định tìm xPack RISC-V GCC tại:

```text
.tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin
```

Thư mục `.tools` không được commit. Có thể truyền một toolchain path khác cho
`scripts/build_quad_cache_workload.ps1` qua tham số `-ToolchainBin`.

### ACT4 architectural tests

Xem hướng dẫn và phiên bản dependency tại:

```text
verification/arch_test/README.md
```

ACT4 source được pin tại commit:

```text
792e55702c6ffff5c8432670086f126f40b88c9e
```

## 4. Tạo Vivado project từ source

Tạo project RTL mới, chọn part `xcvu29p-fsga2577-2L-e`, rồi mở Tcl Console tại
repository root. Thay `<repo-root>` bằng đường dẫn local của `KLTN_FINAL`:

```tcl
set root_dir [file normalize "<repo-root>"]
set rtl_dir  [file join $root_dir rtl]
set list_fd  [open [file join $rtl_dir files.f] r]

while {[gets $list_fd line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {
        continue
    }

    set rtl_file [file normalize [file join $rtl_dir $line]]
    if {![file exists $rtl_file]} {
        error "Missing active RTL: $rtl_file"
    }
    add_files -fileset sources_1 -norecurse $rtl_file
}
close $list_fd

add_files -fileset constrs_1 -norecurse \
    [file join $root_dir constraint soc_internal_250mhz.xdc]

set_property top quad_core_axi_wrapper_ahb [get_filesets sources_1]
set_property generic {MESI_ENABLE=1} [get_filesets sources_1]
set_property verilog_define {PPA_NO_MARK_DEBUG} [get_filesets sources_1]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

update_compile_order -fileset sources_1
```

Không add `sim/*.v` vào `sources_1`. Testbench phải được add vào `sim_1` và mỗi
lần chỉ chọn một simulation top.

Ví dụ chạy D-cache 1000-request test bằng GUI project:

```tcl
add_files -fileset sim_1 -norecurse \
    [file join $root_dir sim tb_dcache_1000_cpu_requests.v]
set_property SOURCE_SET sources_1 [get_filesets sim_1]
set_property top tb_dcache_1000_cpu_requests [get_filesets sim_1]
update_compile_order -fileset sim_1

catch {close_sim -force}
catch {reset_simulation}
launch_simulation -simset sim_1 -mode behavioral
run all
```

Kết quả đúng phải kết thúc bằng:

```text
DCACHE_1000_CPU_REQUESTS_TB: PASS
```

## 5. Chạy regression

Mở Vivado Tcl Console, chuyển current directory tới repository root, sau đó chạy:

### Active cache, coherence, CSR và protocol regression

```tcl
source scripts/run_active_cache_xsim.tcl
```

Expected result của baseline đã kiểm chứng:

```text
25/25 PASS
```

### Verification từ core tới full four-core AXI boundary

```tcl
source scripts/run_behavior_hierarchy_xsim.tcl
```

Expected result:

```text
5/5 PASS
```

Các level gồm core, core+L1, cache/AHB, four-core SoC và board-facing AXI RTL
boundary.

### Compiled MSI–MESI workload

```tcl
source scripts/run_quad_workload_xsim.tcl
```

Runner tự build chương trình RV32IMA, sinh `.mem`, chạy bốn hart trong MSI và
MESI mode, rồi ghi report dưới `reports/`.

Expected result:

```text
MSI   PASS
MESI  PASS
=== RESULT: 2/2 workload runs PASS ===
```

### Official ACT4 unprivileged subset

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_act4_tests.ps1
vivado -mode batch -source scripts/run_riscv_arch_tests_xsim.tcl `
    -tclargs build/act4/work/kltn-rv32ima/elfs
```

Baseline đã kiểm chứng `65/65 PASS` cho RV32 `I`, `M`, `Zaamo`, `Zalrsc`,
`Zicsr` và `Zifencei`. Đây là official ACT4 unprivileged-subset result với
pinned source/configuration, không phải tuyên bố RISC-V certification và không
thay thế verification bổ sung.

## 6. Kết quả verification đã đo

### D-cache 1000 sequential CPU requests

Một RV32IMA core phát đúng 1000 cached 32-bit load requests trên dữ liệu tuần
tự. Với cache line 32 byte, mỗi line chứa tám word:

| Metric | Result |
|---|---:|
| CPU accesses | 1000 |
| L1 hits | 875 |
| L1 misses | 125 |
| Hit rate | 87.50% |
| Miss rate | 12.50% |
| Read misses | 125 |
| Write misses | 0 |
| Uncached accesses | 0 |
| Execution cycles | 33,269 |

Kết quả khớp với 125 compulsory line fills và bảy hit còn lại trên mỗi line.

### MESI `E -> M` silent upgrade

Mỗi hart cold-load một private 32-byte line khác nhau, ghi lại line đó rồi đọc
kiểm tra dữ liệu. Counter được lấy tại accepted coherence-controller
transactions và installed response state:

| Metric | MSI | MESI |
|---|---:|---:|
| Target cold reads | 4 | 4 |
| Target S grants | 4 | 0 |
| Target E grants | 0 | 4 |
| Target RFOs | 4 | 0 |
| Complete-workload RFOs | 407 | 403 |
| L1 misses | 850 | 846 |
| Controller busy cycles | 45,018 | 44,874 |
| Total cycles | 67,238 | 67,082 |
| Retired instructions | 22,191 | 22,191 |
| Aggregate IPC (rounded) | 0.330 | 0.330 |

MESI loại bỏ đúng bốn RFO nhờ bốn silent upgrades và giảm 156 cycles, tương
đương khoảng 0.23%. Lợi ích là có thật nhưng nhỏ trong workload này; không nên
diễn giải thành một mức tăng IPC lớn hoặc một kết luận về power.

## 7. Synthesis và implementation

### GUI flow

Trước synthesis/implementation, kiểm tra:

```tcl
get_property top [get_filesets sources_1]
get_property generic [get_filesets sources_1]
get_property verilog_define [get_filesets sources_1]
```

Expected configuration:

```text
quad_core_axi_wrapper_ahb
MESI_ENABLE=1
PPA_NO_MARK_DEBUG
```

Sau đó có thể dùng `Run Synthesis` và `Run Implementation` trên GUI. Với full
four-core flat implementation, nên bắt đầu bằng một Vivado job để tránh vượt
host-memory envelope.

Sau route, kiểm tra ít nhất:

```tcl
report_timing_summary -delay_type min_max -report_unconstrained
report_route_status
report_utilization
report_methodology
```

Chỉ coi constraint 250 MHz đạt khi setup/hold slack không âm và không có
unrouted/partially-routed net.

### Hierarchical PPA scripts

Các script sau được giữ để tái tạo bottom-up full-SoC route:

```text
scripts/run_hierarchical_soc_ppa.ps1
scripts/run_hierarchical_soc_ppa.tcl
scripts/synth_hier_core_l1.tcl
scripts/ppa/core_l1_wrapper_blackbox.v
```

Ở trạng thái source bundle hiện tại, các Tcl script PPA vẫn đọc part từ file
`Risc_V.xpr` ở repository root. Repository này chưa kèm một portable `.xpr` hay
project-recreation script. Vì vậy hierarchical runner chưa phải turnkey trên
máy mới: trước khi chạy, cần tạo `Risc_V.xpr` với đúng part hoặc cập nhật script
để lấy part `xcvu29p-fsga2577-2L-e` từ một portable configuration. Không được
báo hierarchical flow là reproducible nếu prerequisite này chưa được xử lý.

## 8. Routed PPA baseline

Hai protocol được route bằng cùng Vivado 2022.2 hierarchical flow, cùng part và
cùng constraint 4.000 ns:

| Protocol | Setup WNS | Hold | CLB LUT | CLB FF | BRAM tiles | DSP | Routing errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| MSI | +0.066 ns | +0.039 ns | 43,463 | 39,421 | 242.5 | 16 | 0 |
| MESI | +0.158 ns | +0.040 ns | 43,470 | 39,419 | 242.5 | 16 | 0 |

MESI đạt internal routed 250 MHz với area gần như tương đương MSI. Giá trị
timing-derived estimate cao hơn 250 MHz không được xem là một operating
frequency đã route hoặc đã chạy trên board.

### Giới hạn của kết quả timing

Đây là internal RTL route với `-no_iobuf`, không phải VCU129 board signoff:

- ACLK chưa đi qua board Clocking Wizard/BUFG path trong phép đo này.
- External AXI input/output delays chưa được constrain ở board boundary.
- Chưa có verified PACKAGE_PIN/IOSTANDARD release cho bitstream.
- Chưa có hardware DDR/board bring-up evidence trong source bundle.

Do đó kết luận hợp lệ là: **current internal RTL meets the 250 MHz routed
constraint on the selected part**. Không được mở rộng kết luận này thành
"VCU129 đã chạy ổn định ở 250 MHz" khi chưa có board-level signoff.

## 9. Những điều chưa được kết luận

- Chưa có full-SoC post-route SAIF đủ tin cậy để kết luận MESI giảm dynamic
  power.
- Privileged RISC-V certification không nằm trong ACT4 result hiện tại.
- DMA không thuộc active RTL manifest hoặc full-SoC timing result.
- Legacy Sv32 không thuộc active hierarchy.
- FPGA hardware validation và external memory bring-up vẫn là bước riêng.

## 10. Quản lý source và generated products

Chỉ commit source, scripts, constraints và documentation. Không commit:

```text
.Xil/
*.cache/
*.gen/
*.hw/
*.ip_user_files/
*.runs/
*.sim/
xsim.dir/
build/
reports/
*.dcp
*.jou
*.log
*.wdb
*.saif
*.bit
*.bin
*.ltx
```

Trước khi commit:

```powershell
git status --short
git diff --cached --check
git diff --cached --stat
```

Không dùng generated Vivado project products làm source of truth. Active design
source of truth là `rtl/files.f` cùng các file RTL được liệt kê trong manifest.
