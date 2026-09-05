# Issue tracker: GitHub

Issues and specifications for this repository live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments with `jq` and also fetching labels when needed.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close an issue**: `gh issue close <number> --comment "..."`

Infer the repository from `git remote -v`; `gh` does this automatically when run inside this clone.

## Find a pull request specification

Automated review agents may use the pre-authenticated `gh` CLI for read-only discovery.

1. Read the PR metadata:
   ```sh
   gh pr view <number> --json number,title,body,url,baseRefName,headRefName,commits,closingIssuesReferences
   ```
2. Treat the PR title and body as the immediate specification.
3. Follow `closingIssuesReferences` and issue references in commit messages (`#123`, `Closes #123`, and similar):
   ```sh
   gh issue view <number> --json number,title,body,url,labels
   ```
4. If no issue is linked, continue with the PR title and body as the available specification and clearly identify that source in the Spec report.

Review agents must not edit issues, pull requests, labels, comments, or repository contents while gathering specification context.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repository treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`, then keep only `authorAssociation` values of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE`.
- **Comment, label, or close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, and `gh pr close`.

GitHub shares one number space across issues and PRs. Resolve a bare `#42` with `gh pr view 42`, falling back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. Create it with `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue using `gh api`. Where sub-issues are unavailable, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Apply a `wayfinder:<type>` label (`research`, `prototype`, `grilling`, or `task`). Once claimed, assign the ticket to the driving developer.
- **Blocking**: use GitHub's native issue dependencies. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric database ID from `gh api repos/<owner>/<repo>/issues/<n> --jq .id`. Where dependencies are unavailable, use a `Blocked by: #<n>, #<n>` line at the top of the child body.
- **Frontier query**: list the map's open children, dropping any with an open blocker or assignee; the first child in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`; this is the session's first write.
- **Resolve**: comment with the answer, close the issue, then append a context pointer to the map's Decisions-so-far.
