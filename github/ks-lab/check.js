// KloudSkool lab check — runs in GitHub Actions (workflow: ks-lab-check.yml).
// Checks the GitHub side of labs 12, 13 and the final assessment, and prints a completion code.
// Node 20+, no dependencies.
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const { execSync } = require('child_process');

const LAB = (process.argv[2] || '').toLowerCase();
const TOKEN = process.env.GITHUB_TOKEN || '';
const [OWNER, REPO] = (process.env.GITHUB_REPOSITORY || '/').split('/');
const ORG = process.env.KS_ORG || 'kloudskool';
const BOT = 'github-actions[bot]';
const MOCK = process.env.KS_MOCK ? JSON.parse(fs.readFileSync(process.env.KS_MOCK, 'utf8')) : null;

// ---------- helpers ----------
const sha1blob = (s) => crypto.createHash('sha1').update(`blob ${Buffer.byteLength(s)}\0${s}`).digest('hex');
const ksCode = (lab) => `KS-${lab.toUpperCase()}-${sha1blob(`kloudskool:${lab}:v1`).slice(0, 6).toUpperCase()}`;
const lc = (s) => String(s || '').toLowerCase();
const git = (cmd) => { try { return execSync(`git ${cmd}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };
const gitOk = (cmd) => { try { execSync(`git ${cmd}`, { stdio: 'ignore' }); return true; } catch { return false; } };
const time = (s) => new Date(s).getTime();

async function api(path) {
  if (MOCK) {
    if (!(path in MOCK)) { const e = new Error(`404 ${path}`); e.status = 404; throw e; }
    return MOCK[path];
  }
  const r = await fetch(`https://api.github.com${path}`, {
    headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ks-lab-check' },
  });
  if (!r.ok) { const e = new Error(`${r.status} ${path}`); e.status = r.status; throw e; }
  return r.status === 204 ? null : r.json();
}
async function apiOr(path, fallback) { try { return await api(path); } catch { return fallback; } }
async function list(path, maxPages = 5) {
  const out = [];
  for (let p = 1; p <= maxPages; p++) {
    const sep = path.includes('?') ? '&' : '?';
    const page = await apiOr(`${path}${sep}per_page=100&page=${p}`, []);
    out.push(...page);
    if (page.length < 100) break;
  }
  return out;
}
async function fileAt(repo, path, ref) {
  const f = await apiOr(`/repos/${repo}/contents/${path}?ref=${encodeURIComponent(ref)}`, null);
  return f && f.content ? Buffer.from(f.content, 'base64').toString('utf8') : null;
}
const localFile = (ref, path) => git(`show ${ref}:${path}`);

// ---------- result collection ----------
const results = [];
function check(desc, ok, nudge, points = 0, area = '') {
  results.push({ desc, ok: !!ok, nudge, points, area });
}
function report(title, { scored = false, passMark = 0, strongMark = 0, autoFail = [] } = {}) {
  const lines = [];
  lines.push(`## ${title}`, '');
  lines.push(scored ? '| Result | Check | Points | If not yet |' : '| Result | Check | If not yet |');
  lines.push(scored ? '| --- | --- | --- | --- |' : '| --- | --- | --- |');
  let got = 0, max = 0;
  for (const r of results) {
    const res = r.ok ? '**PASS**' : '**NOT YET**';
    if (scored) { max += r.points; if (r.ok) got += r.points; }
    lines.push(scored ? `| ${res} | ${r.desc} | ${r.ok ? r.points : 0} / ${r.points} | ${r.ok ? '' : r.nudge || ''} |`
                      : `| ${res} | ${r.desc} | ${r.ok ? '' : r.nudge || ''} |`);
    console.log(`${r.ok ? 'PASS    ' : 'NOT YET '} ${r.desc}${r.ok || !r.nudge ? '' : `  -> ${r.nudge}`}`);
  }
  lines.push('');
  let passed;
  if (scored) {
    const failedAuto = autoFail.filter((a) => !a.ok);
    const band = got >= strongMark ? 'Strong' : got >= passMark ? 'Competent (pass)' : 'Not yet';
    passed = got >= passMark && failedAuto.length === 0;
    lines.push(`### Score: ${got} / ${max} (automated part)`, '');
    if (failedAuto.length) {
      lines.push(`**Result: Not yet.** These cause an automatic "Not yet" whatever the score:`, '');
      for (const a of failedAuto) lines.push(`- ${a.desc}`);
    } else {
      lines.push(`**Band: ${band}.** Pass mark ${passMark}, strong ${strongMark}.`);
    }
    console.log(`\nScore: ${got} / ${max}  ${failedAuto.length ? 'Automatic NOT YET' : band}`);
  } else {
    passed = results.every((r) => r.ok);
    const n = results.filter((r) => r.ok).length;
    lines.push(`**${n} of ${results.length} checks pass.**`);
  }
  lines.push('');
  if (passed) {
    const code = ksCode(LAB);
    lines.push(`### Your completion code: \`${code}\``, '', 'Choose it in the check-in quiz on the learning platform.');
    console.log(`\nYour completion code: ${code}`);
  } else {
    lines.push('Fix the items marked **NOT YET**, then run this check again (Actions > KloudSkool lab check > Run workflow).');
  }
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n');
  process.exitCode = passed ? 0 : 1;
}

async function mainProtected(repo) {
  const rules = await apiOr(`/repos/${repo}/rules/branches/main`, []);
  if (Array.isArray(rules) && rules.some((r) => r.type === 'pull_request')) return true;
  const br = await apiOr(`/repos/${repo}/branches/main`, {});
  return !!br.protected;
}
async function botReview(repo, n) {
  const reviews = await apiOr(`/repos/${repo}/pulls/${n}/reviews`, []);
  return reviews.find((r) => r.user && r.user.login === BOT) || null;
}
async function commitsAfter(repo, n, t) {
  const commits = await apiOr(`/repos/${repo}/pulls/${n}/commits?per_page=100`, []);
  return commits.filter((c) => time(c.commit.committer.date) > t).length;
}
async function authorRepliedAfter(repo, pr, t) {
  const issueComments = await apiOr(`/repos/${repo}/issues/${pr.number}/comments?per_page=100`, []);
  const reviewComments = await apiOr(`/repos/${repo}/pulls/${pr.number}/comments?per_page=100`, []);
  return [...issueComments, ...reviewComments].some((c) => c.user && lc(c.user.login) === lc(pr.user.login) && time(c.created_at) > t);
}

// =====================================================================
// Lab 12 — first PR and the review that follows
// =====================================================================
async function lab12() {
  const repo = `${OWNER}/${REPO}`;
  const pulls = await list(`/repos/${repo}/pulls?state=all`);
  check('main is protected: changes need a pull request', await mainProtected(repo),
    'Settings > Rules > Rulesets > New branch ruleset > Require a pull request before merging');
  const hot = pulls.filter((p) => p.head.ref.startsWith('hotfix/PLAT-046-'));
  check('The PLAT-046 hotfix was merged through a pull request', hot.some((p) => p.merged_at), 'open a PR from your hotfix branch and merge it');
  const feat = pulls.filter((p) => p.head.ref.startsWith('feature/PLAT-045-'));
  check('Exactly one pull request for PLAT-045', feat.length === 1,
    feat.length > 1 ? 'you opened more than one. Review fixes go into the same PR' : 'open a PR from feature/PLAT-045-alerts');
  const pr = feat.find((p) => p.merged_at) || feat[0];
  if (!pr) { report('Lab 12: first PR and the review that follows'); return; }
  check('The PLAT-045 pull request is merged', !!pr.merged_at, 'merge it once every review point is done');
  check('Its description references PLAT-045', /PLAT-045/.test(pr.body || '') || /PLAT-045/.test(pr.title || ''), 'edit the PR description');
  const rv = await botReview(repo, pr.number);
  check('The reviewer left a review', !!rv, 'the review bot runs when the PR opens. Check the Actions tab for the Review bot run');
  const t = rv ? time(rv.submitted_at) : Infinity;
  check('You pushed fixes to the same PR after the review', rv && (await commitsAfter(repo, pr.number, t)) > 0, 'commit the fixes on the same branch and git push');
  check('You replied on the PR after the review', rv && (await authorRepliedAfter(repo, pr, t)), 'add a comment saying what you changed');
  const cpu = localFile('origin/main', 'scripts/check-cpu.sh') || localFile('HEAD', 'scripts/check-cpu.sh');
  check('check-cpu.sh on main uses set -euo pipefail', /set -euo pipefail/.test(cpu), 'review point 2');
  check('check-cpu.sh on main reads CPU_THRESHOLD with a default', /CPU_THRESHOLD:-/.test(cpu), 'review point 1');
  const branches = await list(`/repos/${repo}/branches`);
  check('Merged branches are deleted on GitHub', !branches.some((b) => /^(feature\/PLAT-045|hotfix\/PLAT-046)/.test(b.name)), 'delete them from the PR page or the Branches page');
  report('Lab 12: first PR and the review that follows');
}

// =====================================================================
// Lab 13 — contribute to a repo you don't own
// =====================================================================
async function lab13() {
  const upstream = `${ORG}/cloud-runbooks`;
  const fork = await apiOr(`/repos/${OWNER}/cloud-runbooks`, null);
  check(`You have a fork: ${OWNER}/cloud-runbooks`, fork && fork.fork && lc(fork.parent && fork.parent.full_name) === lc(upstream),
    `fork https://github.com/${upstream} (Fork button, top right)`);
  const pulls = (await list(`/repos/${upstream}/pulls?state=all&sort=created&direction=desc`, 10))
    .filter((p) => lc(p.user.login) === lc(OWNER));
  check(`Exactly one pull request from you to ${upstream}`, pulls.length === 1,
    pulls.length > 1 ? 'fixes go into the same PR: push to its branch' : 'open a PR from your fork');
  const pr = pulls[0];
  if (!pr) { report('Lab 13: contribute to a repo you do not own'); return; }
  check('It targets the develop branch', pr.base.ref === 'develop', 'CONTRIBUTING.md says PRs go to develop. Edit the PR and change its base');
  check('It comes from your fork', pr.head.repo && lc(pr.head.repo.full_name) === lc(`${OWNER}/cloud-runbooks`), 'push to your fork, then open the PR from it');
  const headRepo = pr.head.repo ? pr.head.repo.full_name : `${OWNER}/cloud-runbooks`;
  const name = `runbooks/${lc(OWNER)}-vm-wont-start.md`;
  const body = (await fileAt(headRepo, name, pr.head.sha)) || (await fileAt(headRepo, `runbooks/${OWNER}-vm-wont-start.md`, pr.head.sha));
  check(`Your runbook is at ${name}`, !!body, 'name it after your GitHub username, lower case');
  const tpl = (await fileAt(upstream, 'runbooks/TEMPLATE.md', 'develop')) || '';
  const headings = tpl.split('\n').filter((l) => /^## /.test(l)).map((l) => l.trim());
  const missing = headings.filter((h) => !(body || '').split('\n').map((l) => l.trim()).includes(h));
  check('It has every heading in the current template (develop)', body && headings.length && missing.length === 0,
    missing.length ? `missing: ${missing.join(', ')}. Your fork's copy of the template is out of date` : 'use runbooks/TEMPLATE.md from develop');
  check('Every section is filled in', body && body.length > tpl.length + 150, 'write a line or more under each heading');
  const cmp = await apiOr(`/repos/${upstream}/compare/develop...${pr.head.sha}`, null);
  check('Your branch is up to date with upstream develop', cmp && cmp.behind_by === 0, 'git fetch upstream, git merge upstream/develop, git push');
  report('Lab 13: contribute to a repo you do not own');
}

// =====================================================================
// Final assessment — your first week at NovaTech
// =====================================================================
const FINAL_KEY = 'ks-FAKE-predecessor-7731-not-real';
function finalVersion(owner) {
  const seed = parseInt(sha1blob(`kloudskool:seed:${lc(owner)}`)[0], 16) % 3;
  return ['v2.3.0', 'v2.4.0', 'v3.1.0'][seed];
}
async function finalLab() {
  const repo = `${OWNER}/${REPO}`;
  const version = finalVersion(OWNER);
  const start = git('rev-parse -q --verify assessment-start^{commit}');
  const main = git('rev-parse origin/main') || git('rev-parse HEAD');
  const pulls = await list(`/repos/${repo}/pulls?state=all`);
  const merged = pulls.filter((p) => p.merged_at);
  const byRef = (re) => merged.find((p) => re.test(p.head.ref));
  const prRevert = merged.find((p) => /^revert\/PLAT-102-/.test(p.head.ref) || /PLAT-102/.test(`${p.title} ${p.body || ''}`));
  const pr101 = byRef(/^feature\/PLAT-101-/);
  const pr098 = byRef(/^feature\/PLAT-098-/);

  // Auto-fail conditions
  const histOk = !!start && gitOk(`merge-base --is-ancestor ${start} ${main}`);
  const secretOk = git(`log --all -S"${FINAL_KEY}" --format=%H -- . ":(exclude).github"`) === '';
  // Priya's work counts as kept if her commits, a squash of them, or her files are on main
  const priyaOnMain = git(`log ${main} --author="Priya Shah" --format=%s`).split('\n').filter((s) => /^PLAT-098: /.test(s)).length >= 2
    || git(`log ${main} --format=%B`).includes('PLAT-098: Add tag audit script')
    || (!!localFile(main, 'scripts/tag-audit.sh') && /variable "required_tags"/.test(localFile(main, 'terraform/variables.tf')));
  const autoFail = [
    { desc: 'Shared history was rewritten (assessment-start is no longer in main)', ok: histOk },
    { desc: "The predecessor's secret is in a pushed commit", ok: secretOk },
    { desc: "Priya's commits were lost (force push)", ok: priyaOnMain },
  ];

  // Workflow discipline (20)
  check('main is protected: every change needs a pull request', await mainProtected(repo), 'Settings > Rules > Rulesets', 5, 'Workflow');
  let allViaPr = !!start;
  if (start) {
    const fp = git(`rev-list --first-parent ${start}..${main}`).split('\n').filter(Boolean);
    for (const sha of fp) {
      const prs = await apiOr(`/repos/${repo}/commits/${sha}/pulls`, []);
      if (!prs.some((p) => p.merged_at)) { allViaPr = false; break; }
    }
  }
  check('Every change to main arrived through a merged pull request', allViaPr, 'no direct commits to main', 10, 'Workflow');
  const refsOk = merged.length > 0 && merged.every((p) => /^(feature|hotfix|revert)\/PLAT-\d+-[a-z0-9-]+$/.test(p.head.ref));
  const msgs = start ? git(`log --no-merges --format=%an%x09%s ${start}..${main}`).split('\n').filter(Boolean) : [];
  const msgsOk = msgs.filter((l) => !l.startsWith('Priya Shah\t')).every((l) => /\t(PLAT-\d+: |Revert ")/.test(l));
  check('Branch names and commit messages follow CONTRIBUTING.md', refsOk && msgsOk, 'feature/PLAT-101-..., commit messages start with the ticket id', 3, 'Workflow');
  const branches = await list(`/repos/${repo}/branches`);
  check('Merged branches are deleted on GitHub', branches.every((b) => b.name === 'main'), 'delete merged branches', 2, 'Workflow');

  // Incident handling (20)
  const badLines = start ? git(`log ${start} --format=%H%x09%an -S Standard_D64s_v5 -- terraform/environments/prod.tfvars`).split('\n').filter(Boolean) : [];
  const [bad, badAuthor] = (badLines[badLines.length - 1] || '\t').split('\t');
  const reverted = !!bad && git(`log ${main} --format=%B`).includes(`This reverts commit ${bad}`);
  const fixedByHand = /Standard_B2s/.test(localFile(main, 'terraform/environments/prod.tfvars'));
  check('The bad VM size change was reverted on main', reverted, 'find it with git log -S, undo it with git revert on a branch', 10, 'Incident');
  if (!reverted) check('Production VM size is back to Standard_B2s (fixed, but not by a revert)', fixedByHand, 'a revert keeps the link to the bad commit', 0, 'Incident');
  const t = (p) => (p ? time(p.merged_at) : Infinity);
  check('The P1 revert was merged before PLAT-101 and PLAT-098', prRevert && t(prRevert) < Math.min(t(pr101), t(pr098)), 'P1 first', 5, 'Incident');
  const short = (bad || 'xxxxxxx').slice(0, 7);
  check('The revert PR names the bad commit and its author', prRevert && (prRevert.body || '').includes(short) && (prRevert.body || '').includes(badAuthor || 'xx'),
    'add the short hash and the author to the PR description', 5, 'Incident');

  // Feature delivery (15)
  const cert = localFile(main, 'scripts/check-cert-expiry.sh');
  const readme = localFile(main, 'README.md');
  const vars = localFile(main, 'terraform/variables.tf');
  check('check-cert-expiry.sh is on main', !!cert, 'PLAT-101 step 1', 5, 'Feature');
  check('README lists check-cert-expiry.sh', /check-cert-expiry\.sh/.test(readme), 'PLAT-101 step 2', 5, 'Feature');
  check('cert_expiry_alert_days is in variables.tf', /variable "cert_expiry_alert_days"/.test(vars), 'PLAT-101 step 3', 5, 'Feature');

  // Conflict resolution (15)
  check("Priya's PLAT-098 commits are in main", priyaOnMain, 'merge her branch through a PR', 7, 'Conflict');
  const bothSides = /tag-audit\.sh/.test(readme) && /check-cert-expiry\.sh/.test(readme) && /variable "required_tags"/.test(vars) && /variable "cert_expiry_alert_days"/.test(vars);
  const markers = git(`grep -nE "^(<<<<<<<|=======$|>>>>>>>)" ${main}`) !== '';
  check('Both sides of the conflict kept, no markers left', bothSides && !markers, 'README and variables.tf need Priya\'s lines and yours', 8, 'Conflict');

  // Review response (10)
  const rv = pr101 ? await botReview(repo, pr101.number) : null;
  const rt = rv ? time(rv.submitted_at) : Infinity;
  check('Review fixes pushed to the same PLAT-101 pull request', rv && (await commitsAfter(repo, pr101.number, rt)) > 0, 'push fixes to the same branch', 4, 'Review');
  check('Both review points are done', /CERT_EXPIRY_ALERT_DAYS:-30/.test(cert) && /Usage:/.test(cert) && !/-lt 30\b/.test(cert), 'read the review again', 3, 'Review');
  check('You replied on the PR after the review', rv && (await authorRepliedAfter(repo, pr101, rt)), 'say what you changed', 3, 'Review');

  // Release (5)
  const tagType = git(`cat-file -t ${version}`);
  const tagCommit = git(`rev-parse -q --verify ${version}^{commit}`);
  const tagHasAll = tagCommit && /check-cert-expiry\.sh/.test(localFile(tagCommit, 'README.md')) && /tag-audit\.sh/.test(localFile(tagCommit, 'README.md'))
    && /Standard_B2s/.test(localFile(tagCommit, 'terraform/environments/prod.tfvars'));
  check(`${version} is an annotated tag on main with all three tickets in it`, tagType === 'tag' && tagHasAll && gitOk(`merge-base --is-ancestor ${tagCommit} ${main}`),
    `git tag -a ${version} on the final main, then push the tag`, 3, 'Release');
  const rel = await apiOr(`/repos/${repo}/releases/tags/${version}`, null);
  check(`Release ${version} notes name PLAT-102, PLAT-098 and PLAT-101`, rel && ['PLAT-102', 'PLAT-098', 'PLAT-101'].every((k) => (rel.body || '').includes(k)), 'edit the release notes', 2, 'Release');

  // Hygiene (5)
  const debugOk = git('log --all -S"DEBUG: predecessor" --format=%H -- . ":(exclude).github"') === '';
  check("The predecessor's debug line and secret were never pushed", secretOk && debugOk, 'check git status before your first commit', 5, 'Hygiene');

  report('Final practical assessment: your first week at NovaTech', { scored: true, passMark: 59, strongMark: 72, autoFail });
}

(async () => {
  if (LAB === '12') await lab12();
  else if (LAB === '13') await lab13();
  else if (LAB === 'final') await finalLab();
  else { console.log(`Unknown lab "${LAB}". Choose 12, 13 or final.`); process.exitCode = 1; }
})().catch((e) => { console.error(`The check itself failed: ${e.message}`); process.exitCode = 1; });
