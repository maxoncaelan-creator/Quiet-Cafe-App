# Stage 03 — Build

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]

## Inputs
- Layer 4 (working): ../02_ranking-design/output/prd.md
- Layer 4 (working): ../02_ranking-design/output/ranking-spec.md
- Layer 4 (working): ../02_ranking-design/output/data-schema.md

## Process
Build the app: data pipeline, ranking engine, and interface.
Platform: iOS and Android (mobile). Confirmed with Caelan — see [[quiet-restaurant-finder/stages/01_research/output/research-brief|research brief]]. Driven by the in-app microphone decibel signal, which needs a native app on the device doing the measuring.
Tech stack is not yet decided. A cross-platform framework (Flutter or React Native) is worth considering, since decibel-metering packages exist for both covering iOS and Android from one codebase. Confirm with Caelan before you start.

## Outputs
- Working app source -> output/
