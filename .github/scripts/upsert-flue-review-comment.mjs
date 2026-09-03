import { readFile } from 'node:fs/promises';

const marker = '<!-- flue-pr-review -->';
const [bodyPath] = process.argv.slice(2);
const {
	EXPECTED_BODY_TOKEN,
	GITHUB_API_URL = 'https://api.github.com',
	GITHUB_REPOSITORY,
	GITHUB_TOKEN,
	PR_NUMBER,
} = process.env;

if (!bodyPath || !GITHUB_REPOSITORY || !GITHUB_TOKEN || !PR_NUMBER) {
	throw new Error(
		'Usage: upsert-flue-review-comment.mjs <body-file>; GITHUB_REPOSITORY, GITHUB_TOKEN, and PR_NUMBER are required.',
	);
}

const body = `${marker}\n${await readFile(bodyPath, 'utf8')}`.trim();
const headers = {
	Accept: 'application/vnd.github+json',
	Authorization: `Bearer ${GITHUB_TOKEN}`,
	'Content-Type': 'application/json',
	'X-GitHub-Api-Version': '2022-11-28',
};

async function request(path, options = {}) {
	const response = await fetch(`${GITHUB_API_URL}${path}`, { ...options, headers });
	if (!response.ok) {
		throw new Error(`GitHub API ${response.status}: ${await response.text()}`);
	}
	return response.status === 204 ? undefined : response.json();
}

let existing;
for (let page = 1; !existing; page += 1) {
	const comments = await request(
		`/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments?per_page=100&page=${page}`,
	);
	existing = comments.find(
		(comment) => comment.user?.login === 'github-actions[bot]' && comment.body?.includes(marker),
	);
	if (comments.length < 100) break;
}

if (existing && EXPECTED_BODY_TOKEN && !existing.body?.includes(EXPECTED_BODY_TOKEN)) {
	console.log('A newer run already owns the sticky comment; skipping this update.');
	process.exit(0);
}

if (existing) {
	await request(`/repos/${GITHUB_REPOSITORY}/issues/comments/${existing.id}`, {
		method: 'PATCH',
		body: JSON.stringify({ body }),
	});
} else {
	await request(`/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments`, {
		method: 'POST',
		body: JSON.stringify({ body }),
	});
}
