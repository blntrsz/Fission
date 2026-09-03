'use agent';
import {
  GeneralSubagent,
  useModel,
  useSandbox,
  useSubagent,
  useTool,
} from '@flue/runtime';
import { local } from '@flue/runtime/node';
import * as v from 'valibot';

export function PullRequestReviewer() {
  useModel('opencode-go/deepseek-v4-pro', { thinkingLevel: 'high' });
  useSubagent(GeneralSubagent);
  useSandbox(
    local({
      cwd: '..',
      // Keep model credentials in the Flue runtime. The sandbox only needs
      // read-only GitHub CLI access for PR and issue discovery.
      env: {
        GH_TOKEN: process.env.GH_TOKEN,
      },
    }),
  );

  useTool({
    name: 'review_pull_request',
    description:
      'Review one checked-out GitHub pull request and return the complete Markdown report for its sticky PR comment.',
    input: v.object({
      prNumber: v.pipe(v.number(), v.integer(), v.minValue(1)),
      fixedPoint: v.pipe(
        v.string(),
        v.regex(/^[0-9a-f]{40}$/i, 'The fixed point must be a full commit SHA.'),
      ),
    }),
    harness: true,
    async run({ harness, data }) {
      const { data: report } = await harness.prompt(
        `Review GitHub pull request #${data.prNumber} against fixed point ${data.fixedPoint}.

Activate and follow the \`code-review\` skill. Use the structured command from \`docs/agents/issue-tracker.md\` and read-only git/gh commands to gather the PR title, body, commits, linked issues, standards, and diff. Do not read existing PR review comments, modify the checkout, or modify GitHub. When the skill calls for parallel sub-agents, delegate both axes in one tool-call batch to \`flue-general\`.

After the two-axis review, activate the \`show-me\` skill and add a concise \"Change summary\" that visually explains the important change using a small file tree, call tree, pseudocode, diff sketch, or Mermaid diagram as appropriate. Return only the report body, beginning with the spec source. Do not include the \`<!-- flue-pr-review -->\` marker, a \`Flue code review\` heading, or loading/completion status; the workflow adds that wrapper.`,
        { result: v.string() },
      );

      return { output: report };
    },
  });

  return 'For every request, call `review_pull_request` exactly once, then return its Markdown report unchanged and without additional preamble.';
}
