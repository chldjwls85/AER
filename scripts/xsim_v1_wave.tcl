set top_path /tb_aer_v1_top_128
set core_path ${top_path}/dut/parameterized_top_i

catch {add_wave -divider {Top-level stream}}
catch {add_wave ${top_path}/clk}
catch {add_wave ${top_path}/rst_n}
catch {add_wave -radix hex ${top_path}/out_data}
catch {add_wave ${top_path}/out_valid}
catch {add_wave ${top_path}/out_ready}
catch {add_wave ${top_path}/out_last}

catch {add_wave -divider {Global bank selector}}
catch {add_wave -radix unsigned ${core_path}/time_now}
catch {add_wave -radix hex ${core_path}/bank_valid}
catch {add_wave -radix hex ${core_path}/global_selector_i/selector_tree_i/level1_valid}
catch {add_wave -radix hex ${core_path}/global_selector_i/selector_tree_i/level1_ready}
catch {add_wave ${core_path}/global_selector_i/selector_tree_i/gen_level2/level2_valid}
catch {add_wave ${core_path}/global_selector_i/selector_tree_i/gen_level2/level2_ready}

catch {add_wave -divider {Selected bank 17}}
catch {add_wave -radix hex {sim:/tb_aer_v1_top_128/dut/parameterized_top_i/bank_data_flat[287:272]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/parameterized_top_i/bank_valid[17]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/parameterized_top_i/bank_ready[17]}}
catch {add_wave {sim:/tb_aer_v1_top_128/dut/parameterized_top_i/bank_last[17]}}

run all
wave zoom full
catch {save_wave_config aer_v1_top_128.wcfg}
