# AGENTS.project.md

# Coloring Project Guide for Agents

## Product intent
Describe what this app is for in plain language.
Suggested structure:
- Who the app serves
- The main problem it solves
- The success criteria

## Current product phase (scaffold)
This file is expected to evolve over time.
Update this section as soon as implementation starts.

Starter checklist:
1) Define MVP scope
2) Define architecture boundaries
3) Define reliability and UX goals
4) Define testing priorities

## Architecture snapshot (current)
Capture the current technical shape as it becomes real:
- app entry and navigation model
- core view models/services
- data flow and persistence

## Concurrency rules (important)
Keep rules explicit for this project as they become known.
- keep UI state on the main actor
- keep IO/network work off the main actor
- avoid broad isolation as a shortcut

## Behavior invariants (do not regress)
List critical product contracts once identified.
Examples:
- setup flows
- creation/sync pipelines
- data safety guarantees

## UX rules
Document UX guarantees (copy tone, interactions, failure handling, keyboard flows).

## Coding conventions
Project-specific style or patterns that go beyond AGENTS.md.

## Build/run notes
- target platforms
- warning policy
- local run/test setup notes

## Near-term priorities
Keep this list short and current.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion