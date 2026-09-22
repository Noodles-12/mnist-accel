## Arty Z7-20 Rev.B -- constraints for fpga_top

## Clock signal: 125 MHz
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## Reset: BTN0, active high (inverted to rst_n inside fpga_top)
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## UART RX from an external 3.3V USB-serial adapter
##   adapter TX  -> Pmod JB pin 1  (W14)
##   adapter GND -> Pmod JB pin 5  (GND)
## PULLUP keeps the line idle-high when nothing is plugged in.
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33   PULLUP true } [get_ports { uart_rx_line }];

## Predicted digit on LD0..LD3
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { digit[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { digit[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { digit[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { digit[3] }];

## Inference-complete flag on Pmod JB pin 2
set_property -dict { PACKAGE_PIN Y14   IOSTANDARD LVCMOS33 } [get_ports { result_ready }];

## UART and the button are asynchronous to clk; the RX synchronizer handles them.
set_false_path -from [get_ports { uart_rx_line btn_rst }]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
