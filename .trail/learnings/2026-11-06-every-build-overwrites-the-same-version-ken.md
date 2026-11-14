---
title: "Every build overwrites the same version tag, so one TimescaleDB version ends up with several different images"
author: Ken
date: 2026-11-06
branch: main
cost: { minutes: 3, tokens: 27241 }
id: l-f1edc7d2
scope: repo
status: active
src: agent
touches:
  - build.yaml
  - ".github/workflows/build.yaml"
---

## Decided
Treat a published tag like 2.30.1-18-trixie as mutable: consumers must pin by digest, and the digest must change whenever the image is rebuilt. Each rebuild of the same version produces a new digest and silently replaces the tag.

## Tried and ruled out
Relying on the tag alone failed. Nodes kept an older cached image under IfNotPresent, so pods ran different builds of the "same" version (Oct 1 incident). Digest pinning fixed that but exposed the next problem: the k8s Renovate regex didn't capture the digest, so tag bumps kept pulling the old build.

## Watch out
- Any push to main that touches Dockerfile, build.yaml or the workflow rebuilds and re-pushes the current version's tag. That includes Renovate's GitHub Actions bumps (e.g. a login-action update) and the floating 18-minimal-trixie base image. Example: 2.30.1 was pushed on Sep 30, then again on Oct 1 03:19 (sha256:3892e5..., the one k8s pinned) and Oct 1 13:09 (sha256:9815f07...).
- The image carries only the previous release's libraries. If a deployment skips a release, the database's installed version has no library left, and connections to it fail until ALTER EXTENSION runs. Step through each release, or widen the window.

In the code:
- .github/workflows/build.yaml: tags only `${version}-${pg_major}-${debian}`, paths filter includes the workflow file itself
- Dockerfile: PREV_EXT_VERSION defaults to the single newest release below EXT_VERSION
- k8s repo renovate.json now captures currentDigest (commit 99db19d67)
