# third_party/hdmi

Taken from **hdl-util/hdmi**, https://github.com/hdl-util/hdmi,
commit `83b1c9543a91b776671a44e68e130f81cae437b7`.
Licence: MIT or Apache-2.0, at your option (`LICENSE-MIT`, `LICENSE-APACHE`).

Files used, from upstream `src/`:

| file | what it does |
|------|--------------|
| `tmds_channel.sv` | TMDS 8b/10b video, TERC4 data-island and control coding, one lane |
| `packet_picker.sv` | chooses which packet to send in each island slot |
| `packet_assembler.sv` | spreads a packet over 32 pixels and adds the BCH ECC |
| `audio_clock_regeneration_packet.sv` | N and CTS (CTS measured against the pixel clock) |
| `audio_sample_packet.sv` | IEC 60958 audio samples |
| `auxiliary_video_information_info_frame.sv` | AVI InfoFrame |
| `source_product_description_info_frame.sv` | SPD InfoFrame |
| `audio_info_frame.sv` | audio InfoFrame |

Upstream's top level, `hdmi.sv`, is not used. `../../hdmi_audio_out.sv` takes
its place and is driven by the scan doubler's counters.

## Local changes

Every change is marked with an `// iverilog:` comment. They exist only because
Icarus Verilog rejects some SystemVerilog array operations. They don't change
any behaviour.

- `packet_picker.sv`
  - The 2-D `headers`/`subs` table indexed by packet type is replaced with one
    array per packet type (`h_acr`/`s_acr`, `h_asp`, `h_avi`, `h_spd`,
    `h_aif`) and an `always_comb case (packet_type)`. The default case is the
    NULL packet (all zeros), so the `MODEL_TECH` NULL entries were removed.
  - The copies into `audio_sample_word_transfer`, the transfer mux and the
    load into `audio_sample_word_packet` are written element by element.
- `packet_assembler.sv`
  - `parity[3:0] <= parity_next_next` and the `'{...}` resets are written
    element by element.

Simulation also needs `-DMODEL_TECH`, which makes upstream's don't-care bytes
0 instead of X (see `../../tb_hdmi_audio.sh`).

Upstream's top level has one bug, which is fixed in `hdmi_audio_out.sv`
rather than here: lane 0 bit 3 must be 0 on the first pixel of a data island
(HDMI 1.4 Section 5.2.3.4). Upstream sends `cx != 0`, which is 1 throughout.
