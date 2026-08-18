# Command: link notes

**Invoked by the user. Never runs on its own.**

Scan this workspace's files for connections to other notes and concepts, then
add Obsidian `[[wikilinks]]` where they carry meaning.

Run it when: a run has finished and its output should join the vault; notes have
accumulated and the connections between them have gone stale; or the user asks
for links, backlinks, or "connect these notes".

## Inputs

| File | Layer | Why |
|---|---|---|
| `/_system/obsidian.md` | 3 | the linking rules — the authority, read it first |
| `bin/icm obsidian scan --workspace quiet-restaurant-finder` | 4 | the candidate report |

## Process

1. **Check linking is available:**
   ```
   bin/icm obsidian status
   ```
   If no vault is detected, stop and say so. ICM works fine without one; this
   command simply has nothing to do.

2. **Read `/_system/obsidian.md`.** It governs when to link, when not to, and
   what syntax to use. Do not proceed from memory of a previous run.

3. **Run the scan:**
   ```
   bin/icm obsidian scan --workspace quiet-restaurant-finder
   ```
   It reports candidates and changes nothing.

4. **Triage every candidate.** Keep the ones where the passage is genuinely
   about the target. Discard lexical coincidences — that is most of them, and
   discarding them is the job. Prefer the candidates marked cross-workspace:
   those are the links the folder structure does not already imply.

5. **Apply the kept links**, editing only the link text. First meaningful
   occurrence per file. Nothing else about the file changes.

6. **Consider the backlink gaps** the scan reports. Add a return link only
   where the reverse direction means something on its own.

7. **Report** what you changed, per file, and what you skipped and why.

## Outputs

| File | Goes to |
|---|---|
| edited markdown, links only | in place |
| `link-report.md` | `commands/output/` |

## Review gate

Show the user the diff. Links are cheap to add and tedious to remove, so it is
worth their glance before it becomes part of the vault's shape.
