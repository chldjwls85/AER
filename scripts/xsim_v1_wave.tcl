set top_path /tb_aer_v1_top_128

catch {add_wave -divider {Top-level stream}}
catch {add_wave ${top_path}/clk}
catch {add_wave ${top_path}/rst_n}
catch {add_wave -radix hex ${top_path}/out_data}
catch {add_wave ${top_path}/out_valid}
catch {add_wave ${top_path}/out_ready}
catch {add_wave ${top_path}/out_last}

catch {add_wave -divider {Global bank selector}}
catch {add_wave -radix unsigned ${top_path}/dut/time_now}
catch {add_wave -radix hex ${top_path}/dut/bank_valid}
catch {add_wave -radix unsigned ${top_path}/dut/global_selector_i/grant_index}
catch {add_wave ${top_path}/dut/global_selector_i/grant_valid}
catch {add_wave ${top_path}/dut/global_selector_i/advance}

catch {add_wave -divider {Selected bank 17}}
catch {add_wave -radix hex {sim:/tb_aer_v1_top_128/dut/bank_data_flat[287:272]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/bank_valid[17]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/bank_ready[17]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/bank_last[17]}}

run all
wave zoom full
catch {save_wave_config aer_v1_top_128.wcfg}
