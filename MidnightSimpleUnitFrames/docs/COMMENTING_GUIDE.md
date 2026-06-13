# MSUF Commenting Guide

MSUF comments should explain ownership, boundaries, and risk. Prefer comments
that help a new maintainer answer: "where does this belong?", "why is this
safe?", and "what must not call this?"

## What To Comment

- Module headers: owner, runtime cost class, public globals, and nearby modules.
- Section boundaries: profile import/export, DB migration, config compilation,
  frame factory work, hot dispatch, runtime queues, assistant parsing.
- Non-obvious safety rules: combat lockdown, secure frames, secret values,
  cached table references, delayed aura scans, and load-order assumptions.
- Compatibility adapters: old profile fields, UUF imports, legacy global APIs.
- Performance decisions: why work is coalesced, deferred, cached, or split into
  hot/warm/cold paths.

## What Not To Comment

- Do not restate the code line by line.
- Do not add comments inside tight loops unless the comment explains a hidden
  invariant or a safety rule.
- Do not document guesses. If behavior is inferred, say so in docs or verify it
  before baking it into a source comment.
- Do not use comments to excuse unclear code when a small rename or split would
  make the code obvious.

## Style

- Use English in source comments to match the existing codebase.
- Keep comments close to the code they protect.
- Write in plain language. A future maintainer should understand the comment
  without knowing the history of the rewrite.
- Prefer "why/when/who owns this" over "what this line does".
- Comments are safe for runtime behavior, but they still increase source size
  and load-time parsing, so make them useful rather than decorative.
