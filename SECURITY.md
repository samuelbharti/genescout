# Security Policy

## Supported versions

Fixes land on `main` and go out with the next release. Older tags are not
patched.

## Reporting a problem

Please do not open a public issue for a security problem. Email
<samuelbharti.io@gmail.com> instead, describing what you found and, where you
can, the steps to reproduce it. You will get an acknowledgement within a few
days, along with what happens next.

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
