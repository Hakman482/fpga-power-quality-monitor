######################################################################
# Nexys A7-100T constraints
######################################################################


######################################################################
# 100 MHz clock
######################################################################

set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } \
    [get_ports { CLK100MHZ }]

create_clock -add \
    -name sys_clk_pin \
    -period 10.000 \
    -waveform {0.000 5.000} \
    [get_ports { CLK100MHZ }]


######################################################################
# Reset pushbutton: BTNC
######################################################################

set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } \
    [get_ports { RESET }]


######################################################################
# PMOD JA - ADC interface
######################################################################

# JA1 : FPGA -> PCB ADC chip select
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } \
    [get_ports { ADC_CS_N }]

# JA2 : FPGA -> PCB ADC serial clock
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } \
    [get_ports { ADC_DCLOCK }]

# JA3 : Voltage ADC data -> FPGA
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } \
    [get_ports { ADC_DOUT_V }]

# JA4 : Current ADC data -> FPGA
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } \
    [get_ports { ADC_DOUT_I }]


######################################################################
# Onboard USB-UART
# FPGA -> PC
######################################################################

set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } \
    [get_ports { UART_TX }]