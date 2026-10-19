// Macros for the Gowin build of the Tang Nano 20K port.  Listed first so they
// apply to every later file: the project compiles as a single unit
// (Multiple_File_Compilation_Unit).
`define SYNTHESIS
`define GW2A
`define RAM48                  // upper 32K of RAM fitted: a 48K Spectrum
`define PS2_KBD                // PS/2 keyboard on pins 73 (CLK), 74 (DATA)
`define SD_LOADER              // microSD games loader: 8255 bridge, NMI menu (F12 / S2)
`define ROM_BANKS              // 32K ROM: the stock ROM and the SD ROM, paged by the 8255 PC5
`define HDMI_AUDIO             // beeper over HDMI: data islands with 48 kHz audio
