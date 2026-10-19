// Macros for the Gowin build of the Tang Nano 20K port.  Listed first so they
// apply to every later file: the project compiles as a single unit
// (Multiple_File_Compilation_Unit).
`define SYNTHESIS
`define GW2A
`define RAM48                  // upper 32K of RAM fitted: a 48K Spectrum
`define PS2_KBD                // PS/2 keyboard on pins 73 (CLK), 74 (DATA)
