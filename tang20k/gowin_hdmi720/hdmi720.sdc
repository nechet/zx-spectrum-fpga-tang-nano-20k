// The 27 MHz crystal; Gowin derives the PLL (371.25 MHz) and CLKDIV
// (74.25 MHz pixel clock) outputs itself.
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]
