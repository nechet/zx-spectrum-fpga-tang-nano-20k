# tmds_channel.v — vendored

| | |
|---|---|
| Upstream | https://github.com/YosysHQ/apicula — `examples/DVI/tmds-channel.v` |
| Original author | Sameer Puri (https://github.com/sameer/hdmi), credited in the file header |
| Licence | MIT (see `LICENSE`, apicula) |
| Commit | `e3eb31c6aa057dec56e8a90589508d194d0409e5` |
| Retrieved | 2026-09-20 |
| Modified | no — renamed from `tmds-channel.v` only |

It implements HDMI 1.4a §5.4 TMDS encoding. Taken from apicula rather than
written fresh because apicula's DVI example is a supported build target for
this exact board and toolchain, so the encoder is known to place and route.
