# ks-lab

Hands-on labs for the KloudSkool **Version Control for Cloud Engineers** module.

`ks-lab` sets up realistic Git situations on your own machine (a platform team's repo,
teammates who push while you work, broken repos to fix) and checks your work.

## Install

macOS (Terminal) or Windows (Git Bash):

```bash
curl -fsSL https://raw.githubusercontent.com/kloudskool/ks-lab/main/install.sh | bash
```

Close the terminal, open a new one, then:

```bash
ks-lab version
```

## Use

```bash
ks-lab start 04      # set up lab 04
ks-lab check 04      # check your work and get your completion code
ks-lab hint 04       # one hint at a time
ks-lab solution 04   # walkthrough, unlocked after two checks
ks-lab list          # every lab
ks-lab update        # get the latest version
```

Your lab folders are in `~/kloudskool-labs`. Running `start` again gives you a clean
starting point: your previous copy is moved to `~/kloudskool-labs/.backup`.

## What's in here

| Path | What it is |
| --- | --- |
| `bin/ks-lab` | The command |
| `lib/` | Shared helpers and the NovaTech repo's files |
| `labs/` | One function set per lab: start, check, hints, solution |
| `github/` | Files copied into your GitHub repos: the lab check and the review bot |
