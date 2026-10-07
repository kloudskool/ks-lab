// KloudSkool review bot — plays the senior engineer who reviews your pull request.
// Runs in GitHub Actions (workflow: review-bot.yml) on PRs from feature/PLAT-045-* and feature/PLAT-101-*.
'use strict';
const TOKEN = process.env.GITHUB_TOKEN;
const REPO = process.env.GITHUB_REPOSITORY;
const N = process.env.PR_NUMBER;
const REF = process.env.HEAD_REF || '';
const SHA = process.env.HEAD_SHA;
const MARK = '<!-- ks-review-status -->';

async function api(path, method = 'GET', body) {
  const r = await fetch(`https://api.github.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ks-review-bot' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) throw new Error(`${r.status} ${method} ${path}: ${await r.text()}`);
  return r.status === 204 ? null : r.json();
}
async function file(path) {
  try {
    const f = await api(`/repos/${REPO}/contents/${path}?ref=${SHA}`);
    return Buffer.from(f.content, 'base64').toString('utf8');
  } catch { return ''; }
}

const REVIEWS = {
  'PLAT-045': {
    intro: 'Thanks for this. Three things before it can merge:',
    points: async (pr) => {
      const s = await file('scripts/check-cpu.sh');
      return [
        ['Read the threshold from an environment variable with a default, e.g. `THRESHOLD="${CPU_THRESHOLD:-85}"`, so ops can change it without a code change.', /CPU_THRESHOLD:-/.test(s)],
        ['Add `set -euo pipefail` near the top of `check-cpu.sh`, like the other scripts. Without it, a failed command is silently ignored.', /set -euo pipefail/.test(s)],
        ['The PR description doesn\'t reference the ticket. Add PLAT-045 so this can be traced later.', /PLAT-045/.test(pr.body || '')],
      ];
    },
  },
  'PLAT-101': {
    intro: 'Good start. Two changes, please:',
    points: async () => {
      const s = await file('scripts/check-cert-expiry.sh');
      return [
        ['Don\'t hard-code 30 in the script. Read it from the environment so it matches the Terraform variable: `ALERT_DAYS="${CERT_EXPIRY_ALERT_DAYS:-30}"`, and compare against `$ALERT_DAYS`.', /CERT_EXPIRY_ALERT_DAYS:-30/.test(s) && !/-lt 30\b/.test(s)],
        ['Add usage text to the header comment (a line starting `# Usage:`) so on-call knows how to run it.', /Usage:/.test(s)],
      ];
    },
  },
};

(async () => {
  const ticket = /^feature\/(PLAT-045|PLAT-101)-/.exec(REF);
  if (!ticket) return;
  const cfg = REVIEWS[ticket[1]];
  const pr = await api(`/repos/${REPO}/pulls/${N}`);
  const points = await cfg.points(pr);

  // 1. One review, left once, when the PR first appears.
  const reviews = await api(`/repos/${REPO}/pulls/${N}/reviews`);
  if (!reviews.some((r) => r.user.login === 'github-actions[bot]')) {
    const body = [cfg.intro, '', ...points.map(([text], i) => `${i + 1}. ${text}`), '',
      'Push the fixes to this same branch: the pull request updates itself. Then reply here saying what you changed.'].join('\n');
    await api(`/repos/${REPO}/pulls/${N}/reviews`, 'POST', { event: 'COMMENT', body });
  }

  // 2. A status comment that updates on every push.
  const done = points.filter(([, ok]) => ok).length;
  const status = [MARK, `**Review points: ${done} of ${points.length} done**`, '',
    '| Point | Status |', '| --- | --- |',
    ...points.map(([, ok], i) => `| ${i + 1} | ${ok ? 'DONE' : 'NOT YET'} |`), '',
    done === points.length ? 'All review points are addressed. Reply on this PR saying what you changed, then merge.'
                           : 'This updates each time you push or edit the description.'].join('\n');
  const comments = await api(`/repos/${REPO}/issues/${N}/comments?per_page=100`);
  const mine = comments.find((c) => c.user.login === 'github-actions[bot]' && c.body.includes(MARK));
  if (mine) await api(`/repos/${REPO}/issues/comments/${mine.id}`, 'PATCH', { body: status });
  else await api(`/repos/${REPO}/issues/${N}/comments`, 'POST', { body: status });
})().catch((e) => { console.error(e.message); process.exitCode = 1; });
