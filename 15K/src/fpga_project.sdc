//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.12.02_SP2 (64-bit) 
//Created Time: 2026-05-21 16:04:14
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
create_clock -name cphy_rx_pcs_clk -period 12.8 -waveform {0 6.4} [get_nets {cphy_rx_pcs_clk}]
create_clock -name cphy_tx_pcs_clk -period 12.8 -waveform {0 6.4} [get_nets {cphy_tx_pcs_clk}]
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {cphy_rx_pcs_clk}] -group [get_clocks {cphy_tx_pcs_clk}]
