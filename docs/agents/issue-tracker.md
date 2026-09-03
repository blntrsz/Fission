# GitHub issue tracker access

This repository uses GitHub issues and pull requests as its issue tracker. Automated review agents may use the pre-authenticated `gh` CLI for read-only discovery.

## Find the pull request specification

1. Read the PR metadata:
   ```sh
   gh pr view <number> --json number,title,body,url,baseRefName,headRefName,commits,closingIssuesReferences
   ```
2. Treat the PR title and body as the immediate specification.
3. Follow `closingIssuesReferences` and issue references in commit messages (`#123`, `Closes #123`, and similar):
   ```sh
   gh issue view <number> --json number,title,body,url,labels
   ```
4. If no issue is linked, continue with the PR title and body as the available spec and clearly identify that source in the Spec report.

Review agents must not edit issues, pull requests, labels, comments, or repository contents while gathering specification context.
