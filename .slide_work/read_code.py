from pathlib import Path
import re, sys
root=Path(r'C:\Users\ADMIN\Documents\GitHub\KLTN')
groups={
 'pipeline':['RV32IMA.v','decode_stage.v','Main_Decoder.v','Control_Unit.v','ALU_Decoder.v','ALU.v','execute_stage.v','fetch_stage.v','PC_module.v','PC_Adder.v','Register_File.v','Sign_Extend.v','Mux_3_by_1.v','mux.v','if_id_registers.v','id_ex_registers.v','ex_mem_registers.v','mem_wb_registers.v','writeback_stage.v','load_unit.v','store_unit.v'],
 'cache':['l1_icache.v','l1_dcache.v','l2_cache.v','coherence_manager.v'],
 'system':['csr_trap_unit.v','sys_decoder.v','mmu_core_wrapper.v','mmu_ip_wrapper.v','ahb_lite_l1_adapter.v','ahb_lite_l1_slave_adapter.v','quad_core_soc_ahb.v','quad_core_axi_wrapper_ahb.v','quad_core_axi_wrapper.v','quad_core_axi_wrapper_ahb_bootable.v','quad_core_axi_wrapper_bootable.v','boot_ctrl.v']}
for name in groups[sys.argv[1]]:
 p=root/'Risc_V_new/Risc_V/rtl'/name
 raw=p.read_text(encoding='utf-8-sig')
 code=re.sub(r'/\*.*?\*/','',raw,flags=re.S)
 code=re.sub(r'//[^\n]*','',code)
 code=re.sub(r'^\s*\(\*.*?\*\)','',code,flags=re.M)
 lines=[s.strip() for s in code.splitlines() if s.strip()]
 # Port declarations and repeated connectivity are inspected in the original files.
 # Focus this reading pass on datapath operations and sequential/combinational logic.
 out=[]; in_block=False
 for s in lines:
  if re.match(r'(always|assign|localparam|parameter|function|endfunction|module|endmodule)\b',s): in_block=True
  if re.match(r'(input|output|inout|wire|reg|integer)\b',s) and not '=' in s: continue
  if re.match(r'\.[\w]+\s*\(',s): continue
  out.append(s)
 print('\nFILE',name,'original lines',len(raw.splitlines()))
 print('\n'.join(out))
