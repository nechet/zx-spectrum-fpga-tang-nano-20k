# TV80 — vendored source

| | |
|---|---|
| Upstream | https://github.com/hutch31/tv80 |
| Author | Guy Hutchison — a Verilog port of Daniel Wallner's VHDL T80 core |
| Licence | MIT (see `LICENSE`) |
| Commit | `66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65` (2026-05-11) |
| Retrieved | 2026-09-13 |
| Modified | **no** — unmodified copies |

Only the five core RTL files are vendored; the upstream repo also carries a
Chisel version, testbenches, a UART and example SoCs that are not needed here.
Upstream paths are `rtl/core/`.

## Verifying this copy

Each file's git blob hash matches the upstream tree at that commit:

```
$ git hash-object tv80n.v tv80_core.v tv80_alu.v tv80_mcode.v tv80_reg.v LICENSE
284c7ef9be4d6ba9d3c1d1983736905b4bd815de   tv80n.v
14f4a6f38d252bb7072bfb950dbf218d9235028b   tv80_core.v
f088d6ea819827e3a101e79f18b80f0e2ced53c5   tv80_alu.v
ed56402db6014495922a8f922a5d5d0ae94f2fd9   tv80_mcode.v
8ceaebbd7d13b4ba0f684558f5349fd101c10320   tv80_reg.v
bfe34d739ffc75f29f80bda213b7b789072c18f2   LICENSE
```

Compare against upstream with:

```
curl -s "https://api.github.com/repos/hutch31/tv80/git/trees/66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65?recursive=1" \
  | grep -E 'rtl/core/tv80|LICENSE'
```

## Re-fetching

```
C=66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65
for f in LICENSE rtl/core/tv80n.v rtl/core/tv80_core.v rtl/core/tv80_alu.v \
         rtl/core/tv80_mcode.v rtl/core/tv80_reg.v; do
  curl -sSO "https://raw.githubusercontent.com/hutch31/tv80/$C/$f"
done
```

## Which top level

`tv80n` is used here — the wrapper with the real Z80 bus interface (separate
`/MREQ`, `/IORQ`, `/RD`, `/WR`). Upstream also provides `tv80s`, a synchronous
wrapper where everything moves on the rising clock edge.
