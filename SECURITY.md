# Security Policy

## Supported versions

I maintain this project on my own. I fix security problems on `main` and in the
next release. I do not backport fixes to older tags.

## Reporting a problem

**Please do not open a public issue for a security problem.**

Email me at <samuelbharti.io@gmail.com>. Tell me what you found and, if you
can, how to reproduce it. I will acknowledge your report within a few days and
tell you what I plan to do about it.

## Worth knowing before you report

- The deterministic core needs no key. Every source it queries is public and
  read-only.
- The optional agent layer needs an LLM provider key. It comes either from
  `.Renviron` (git-ignored) or from a key a user pastes, which is held for that
  browser session only.
- The repository holds no secrets, and only public or synthetic example data. A
  `Secret scan` workflow runs gitleaks over the full history on every push.
- If you deploy the app yourself, the keys and the environment you deploy into
  are yours to secure. Serve it over HTTPS, since a pasted key travels from the
  browser to the server.

## Not a security problem

GeneScout is for research use only. A wrong, incomplete, or over-confident
ranking is a correctness bug, not a vulnerability. Please open a normal issue
for that.
