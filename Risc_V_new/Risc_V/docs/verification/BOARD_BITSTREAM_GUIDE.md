# Hướng dẫn tạo bitstream an toàn

## 1. Điều kiện hiện tại

Thiết kế `soc_4core_trial_wrapper` đã hoàn tất route ở 100 MHz. Tuy nhiên,
project đang chọn part generic `xc7z030fbv676-1` và chưa chọn `BoardPart`.
Hai cổng `sys_clk` và `ext_reset_in` vì vậy chưa có chân vật lý và I/O standard.

Không được hạ severity của `NSTD-1` hoặc `UCIO-1`. Hai DRC này bảo vệ board khỏi
việc dùng sai điện áp hoặc sai chân.

## 2. Lấy thông tin từ board thật

Cần đúng tên/model/revision của board và file master XDC hoặc schematic chính
thức tương ứng. Từ đó xác nhận bốn giá trị:

1. `PACKAGE_PIN` của clock 100 MHz.
2. `IOSTANDARD` của clock.
3. `PACKAGE_PIN` của nút/tín hiệu reset.
4. `IOSTANDARD` và polarity của reset.

Nếu board dùng clock vi sai hoặc clock không phải 100 MHz thì không điền trực
tiếp vào template hiện tại; top-level/Clocking Wizard phải được sửa phù hợp.

## 3. Điền XDC

Mở `constraints/riscv.xdc`, thay bốn trường `<...>` bằng giá trị từ master XDC
chính thức rồi bỏ dấu `#` ở đầu bốn dòng `set_property`.

Giữ nguyên:

```tcl
create_clock -name sys_clk_in -period 10.000 [get_ports sys_clk]
```

chỉ khi nguồn clock thật sự là 100 MHz.

## 4. Chạy trong Vivado Tcl Console

```tcl
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_mdu_pipeline_impl.tcl}
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_board_bitstream.tcl}
```

Script thứ hai tự kiểm tra pin, I/O standard, clock 100 MHz, WNS, WHS và DRC.
Nó chỉ gọi `write_bitstream` khi toàn bộ gate đều PASS.

## 5. Kết quả mong đợi

Vivado phải in:

```text
=== BOARD BITSTREAM: PASS ===
```

Bitstream và báo cáo được lưu trong thư mục timestamp:

```text
reports/board-bitstream-YYYYMMDD-HHMMSS/
```

Không nạp file `.bit` nếu model/revision board hoặc polarity reset chưa được
xác nhận từ tài liệu chính thức.
