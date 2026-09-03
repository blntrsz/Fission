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
	useModel('opencode-go/glm-5.2');
	useSubagent(GeneralSubagent);
	useSandbox(
		local({
			cwd: '..',
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
			prNumber: v.number(),
			fixedPoint: v.string(),
		}),
		harness: true,
		async run({ harness, data }) {
			const { data: report } = await harness.prompt(
				`Review GitHub pull request #${data.prNumber} against fixed point ${data.fixedPoint}.

Activate and follow the \`code-review\` skill. Use \`gh pr view ${data.prNumber}\` and read-only git/gh commands to gather the PR title, body, commits, linked issues, standards, and diff. When the skill calls for parallel sub-agents, delegate both axes in one tool-call batch to \`flue-general\`. Do not modify the checkout or GitHub.

After the two-axis review, activate the \`show-me\` skill and add a concise \"Change summary\" that visually explains the important change using a small file tree, call tree, pseudocode, diff sketch, or Mermaid diagram as appropriate. Return one self-contained Markdown report suitable for a GitHub PR comment.`,
				{ result: v.string() },
			);

			return { output: report };
		},
	});

	return 'For every request, call `review_pull_request` exactly once, then return its Markdown report unchanged and without additional preamble.';
}
