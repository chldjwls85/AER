# Copy only the source-safe setup commands from the existing V3 server flow:
#   - init_lib_search_path / slow_vdd1v0_basicCells.lib
#   - slow_vdd1v0 operating condition (0.9V / 125C)
#   - exact V3 syn_generic/syn_map/syn_opt effort and optimization options
#   - any HDL/search-path settings required before read_hdl
#
# Do not put read_hdl, elaborate, synthesis, reports, or exit in this fragment.
# Replace this error only on the competition server using verified V3 commands.
error "COPY_EXACT_EXISTING_V3_SERVER_SETUP_HERE"
