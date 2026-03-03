+++
title = "Announcing the release of litep2p v0.13.2"
description = "Release v0.13.2 of litep2p"
date = 2026-03-02
slug = "2026-03-02-litep2p-0.13.2"

[taxonomies]
tags = ["litep2p"]

[extra]
author = "dmitry-markin"
version = "v0.13.2"
implementation = "litep2p"
breaking = false
security = false
github_release = "https://github.com/paritytech/litep2p/releases/tag/v0.13.2"
+++
## [0.13.2] - 2026-03-02

This is a hotfix release fixing ping protocol panic in debug builds. The release also includes WebRTC fixes.

## Fixed

- webrtc/fix: Ensure delay future is awaited ([#548](https://github.com/paritytech/litep2p/pull/548))
- ping: Fix panic in debug builds ([#551](https://github.com/paritytech/litep2p/pull/551))
- webrtc: Ensure nonstun packets cannot panic transport layer ([#550](https://github.com/paritytech/litep2p/pull/550))
- webrtc: Avoid memory leaks by cleaning stale hashmap entries ([#549](https://github.com/paritytech/litep2p/pull/549))
