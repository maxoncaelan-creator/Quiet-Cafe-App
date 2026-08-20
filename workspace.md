---
name: quiet-restaurant-finder
title: Quiet Restaurant Finder
status: active
kind: content
purpose: Research, design, and build a mobile app that ranks restaurants across Greater Sydney and beyond by how quiet they are.
inputs: Confirmed product decisions from Caelan; research on restaurant and noise data sources.
outputs: A research brief, a PRD, a ranking spec and data schema, and the running Flutter app + data pipeline + Supabase backend, with a build log of what's verified and what's open.
triggers:
  - quiet restaurant finder
  - quiet cafe app
  - the restaurant noise app
  - continue the restaurant app build
  - quietness score
keywords:
  - restaurant
  - quiet
  - noise
  - decibel
  - flutter
  - supabase
  - ranking
related:
stages:
  - 01_research
  - 02_ranking-design
  - 03_build
---

A single-project workspace, not a repeatable template: one app, taken from
research through ranking design to a live build. Re-entering this workspace
almost always means continuing stage 03 (build) — see `build-log.md` there
for exactly where the last session left off.

Deliberately not covered: general research synthesis or document writing
unrelated to this app (those are `research-synthesis` / `document-production`);
future code changes to the app once it is fully handed off to
[github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App)
as its primary repo — this workspace stays the record of the decisions behind
the code, not necessarily every future commit.
