<!--
  Chapter authoring template + style guide for the Gentoo Post-Install Handbook.
  This file is NOT published as a chapter. Every chapter under docs/handbook/
  MUST follow the structure and rules below so the handbook reads as one voice.
  The gold-standard example to mirror is 03-make-conf.md.
-->

# Handbook chapter template & style guide

## Voice and rules

- **Audience:** someone learning Gentoo who wants to understand *why*, not copy-paste blindly.
- **Language:** English. US spelling.
- **Tense/person:** second person, present tense ("you set", "you verify"). Imperative in steps.
- **Every command must be explained.** Never drop a command block without saying what it does and why it is the right choice. Explain the *reasoning*, not just the syntax.
- **Ground everything in the script.** Each chapter mirrors exactly one `step_NN_*` function (or a named feature) of `gentoo-post-install.sh`. The manual steps must produce the same end state the script produces. If the script writes a file, show the same file. Do not invent packages, flags, or paths the script does not use.
- **Both init systems.** When behavior differs between OpenRC and systemd, show both (the script abstracts this with `service_enable_start`, etc. - expand it).
- **Safety first.** Call out anything that can lock the user out (SSH, firewall, USBGuard, lockdown, root disable) with a clear warning *before* the command.
- **No em dashes** in prose. Use commas, parentheses, or a period. Hyphens in flags/paths are fine.
- **No invented benchmarks or claims.** If a value is a heuristic (e.g. MAKEOPTS from RAM), say so.
- **Cross-link** with the Prev/Next footer and inline links to related chapters.
- Keep code blocks runnable and minimal; use `# root` or `$ ` prompts consistently (root for privileged steps, since post-install is usually done as root or via sudo).

## Required section structure

Every chapter is a single `NN-slug.md` file with exactly these H2 sections, in order:

```markdown
# <Chapter title>

> One-sentence summary of what this chapter sets up and the matching `--flag`.

## What the script automates
Short paragraph: which `step_NN_*` / flag this maps to, and the end state in one or two sentences.

## Concepts
The background a learner needs: what the subsystem is, the vocabulary, the trade-offs.
This is the "why". A few short paragraphs or a bullet list.

## Do it by hand
Numbered steps. Each step: a sentence of intent, the command block, then the explanation.
Mirror the script's actual actions and the files it writes.

## Verify
Commands to confirm it worked, with the expected output described.

## Pitfalls and rollback
What breaks, how to recover, how `--rollback` (or a manual revert) undoes it.

## Script reference
- **Step:** `NN` - `step_NN_name`
- **Flags:** `--foo`, `--no-foo`
- **Managed files:** the exact paths the script creates/edits (so the reader can diff).

---
<nav footer>
```

## Nav footer format

End every chapter with:

```markdown
---
[← Previous: <title>](NN-prev.md) · [Handbook index](README.md) · [Next: <title> →](NN-next.md)
```
