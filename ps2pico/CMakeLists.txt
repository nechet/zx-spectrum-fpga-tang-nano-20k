cmake_minimum_required(VERSION 3.13...3.27)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PICO_BOARD pico CACHE STRING "Board type")
#set(PICO_PLATFORM rp2350 CACHE STRING "rp2350")
#set(PICO_BOARD pico2 CACHE STRING "Board type")

# Pull in Raspberry Pi Pico SDK
include(pico_sdk_import.cmake)

if (PICO_SDK_VERSION_STRING VERSION_LESS "2.1.1")
  message(FATAL_ERROR "Raspberry Pi Pico SDK version 2.1.1 (or later) required. Your version is ${PICO_SDK_VERSION_STRING}")
endif()

set(target_name ps2pico)
set(target_version 3.0)
project(${target_name} C CXX ASM)

# Initialise the Raspberry Pi Pico SDK
pico_sdk_init()

add_executable(${target_name} src/ps2pico.c src/ps2kbd.c)

# print memory usage, enable all warnings
target_link_options(${target_name} PRIVATE -Xlinker --print-memory-usage)
target_compile_options(${target_name} PRIVATE -Wall -Wextra)

add_compile_definitions(PICO_PANIC_FUNCTION=reset)
add_compile_definitions(PICO_XOSC_STARTUP_DELAY_MULTIPLIER=64)

# Pins chosen for the Waveshare RP2040-Zero, which only brings out GP0-GP15
# and GP26-GP29.  The upstream defaults (14/15/16/17) are unusable there: GP16
# is the onboard WS2812 and is not on a pad, and GP17 is not exposed either.
#
# CLOCKOUT and DATAOUT must stay adjacent and in that order -- the ps2read
# program drives them as one 2-bit SET group.
add_compile_definitions(CLOCKIN=10)
add_compile_definitions(CLOCKOUT=11)
add_compile_definitions(DATAOUT=12)
add_compile_definitions(DATAIN=13)

# Inverted copies of CLOCKOUT and DATAOUT, driven by a third state machine.
# These are the ones to wire straight to a 3.3 V host such as a Tang Nano:
# the originals are active-high into a transistor base, so they are inverted
# relative to the real PS/2 line, and these put that right.  Must be adjacent
# and in this order.
add_compile_definitions(INVCLOCK=14)
add_compile_definitions(INVDATA=15)

# Onboard WS2812 on the RP2040-Zero.  Not a pad -- it is the RGB LED.
add_compile_definitions(STATUSLED=16)

pico_generate_pio_header(${target_name} ${CMAKE_CURRENT_LIST_DIR}/src/ps2phy.pio)
pico_generate_pio_header(${target_name} ${CMAKE_CURRENT_LIST_DIR}/src/status.pio)

pico_set_program_name(${target_name} ${target_name})
pico_set_program_version(${target_name} ${target_version})

pico_enable_stdio_uart(${target_name} 1)
pico_enable_stdio_usb(${target_name} 0)

target_include_directories(${target_name} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/src)
target_link_libraries(${target_name} pico_stdlib hardware_pio tinyusb_host tinyusb_board)

pico_add_extra_outputs(${target_name})
