## Generated SDC file "computert.sdc"

## Copyright (C) 1991-2013 Altera Corporation
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, Altera MegaCore Function License 
## Agreement, or other applicable license agreement, including, 
## without limitation, that your use is for the sole purpose of 
## programming logic devices manufactured by Altera and sold by 
## Altera or its authorized distributors.  Please refer to the 
## applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 13.0.1 Build 232 06/12/2013 Service Pack 1 SJ Web Edition"

## DATE    "Thu May 22 16:49:13 2025"

##
## DEVICE  "EP4CE6E22C8"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk50M} -period 20.000 -waveform { 0.000 10.000 } [get_ports {clk50M}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {clk25M} -source [get_ports {clk50M}] -divide_by 2 -master_clock {clk50M} [get_ports {clk25M}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {clk50M}] -rise_to [get_clocks {clk50M}]  0.040  
set_clock_uncertainty -rise_from [get_clocks {clk50M}] -fall_to [get_clocks {clk50M}]  0.040  
set_clock_uncertainty -fall_from [get_clocks {clk50M}] -rise_to [get_clocks {clk50M}]  0.040  
set_clock_uncertainty -fall_from [get_clocks {clk50M}] -fall_to [get_clocks {clk50M}]  0.040  
set_clock_uncertainty -rise_from [get_clocks {clk25M}] -rise_to [get_clocks {clk25M}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {clk25M}] -fall_to [get_clocks {clk25M}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {clk25M}] -rise_to [get_clocks {clk50M}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk25M}] -fall_to [get_clocks {clk50M}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk25M}] -rise_to [get_clocks {clk25M}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {clk25M}] -fall_to [get_clocks {clk25M}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {clk25M}] -rise_to [get_clocks {clk50M}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk25M}] -fall_to [get_clocks {clk50M}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk50M}] -rise_to [get_clocks {clk25M}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk50M}] -fall_to [get_clocks {clk25M}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk50M}] -rise_to [get_clocks {clk25M}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk50M}] -fall_to [get_clocks {clk25M}]  0.030  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

