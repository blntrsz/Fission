# Domain Docs

How engineering skills should consume this repository's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`, when present.

If a file or directory does not exist, proceed silently. Domain-modeling skills create them lazily when terminology or decisions are resolved.

## File structure

This repository uses a single-context layout:

```
/
├── CONTEXT.md
├── docs/adr/
└── Apps, Packages, and supporting directories
```

## Use the glossary's vocabulary

Use terms as defined in `CONTEXT.md`. Avoid synonyms the glossary explicitly rejects.

If a needed concept is absent, reconsider whether it belongs to the domain vocabulary or note the gap for domain modeling.

## Flag ADR conflicts

Explicitly identify output that contradicts an existing ADR rather than silently overriding it.
