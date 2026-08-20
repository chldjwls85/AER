`ifndef AER_CONFIG_VH
`define AER_CONFIG_VH

// AER-Compiler v0 reference configuration.
`define AER_SENSOR_W              16
`define AER_SENSOR_H              16
`define AER_NUM_PIXELS            256

`define AER_TILE_W                4
`define AER_TILE_H                4
`define AER_PIXELS_PER_TILE       16
`define AER_NUM_TILES             16

`define AER_BANK_TILES_X          2
`define AER_BANK_TILES_Y          2
`define AER_TILES_PER_BANK        4
`define AER_NUM_BANKS             4
`define AER_BANK_PIXEL_W          8
`define AER_BANK_PIXEL_H          8

`define AER_PACKET_W              32
`define AER_COORD_W               10
`define AER_TIME_W                8

`define AER_TILE_FIFO_DEPTH       8
`define AER_TILE_FIFO_ADDR_W      3
`define AER_TILE_FIFO_LEVEL_W     4
`define AER_ALL_TILE_LEVEL_W      64

`endif
