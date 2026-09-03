# flue

A [Flue](https://flueframework.com) agent project.

## Setup

```sh
npm install
```

Then set `OPENCODE_API_KEY` in `.env` to an OpenCode API key.

## Review a pull request

Run this from the `flue/` directory while the repository is checked out and GitHub CLI authentication is available:

```sh
npx flue run src/agents/pr-review.ts \
  --message "Review PR #42 with fixed point <base-commit-sha>."
```

In GitHub Actions, `.github/workflows/flue-pr-review.yml` runs this agent for every non-draft PR and maintains one sticky progress/result comment.

## Learn more

- [Flue docs](https://flueframework.com/docs/) — or `npx flue docs` from the terminal.
