<!-- markdownlint-disable-file MD041 -->
<!--
Thanks for contributing to CANDID!
PR TITLE must follow Conventional Commits, e.g.:
  feat: add Open Targets client
  fix: handle empty candidate list
  docs: update data_sources
The pr-title workflow enforces this.
-->

## Summary

<!-- What does this PR do and why? Link related issues, e.g. "Closes #123". -->

## Type of change

- [ ] feat - new feature
- [ ] fix - bug fix
- [ ] docs - documentation
- [ ] chore / refactor / test / build / ci

## Checklist

- [ ] Branch is named `<type>/<short-desc>` and is not `main`.
- [ ] App runs locally (`shiny::runApp()`); tests pass (`testthat::test_dir("tests/testthat")`).
- [ ] Code is formatted (`air format .`) and lints clean (`lintr::lint_dir(".")`).
- [ ] Every new biological claim is grounded in a tool result (no ungrounded output).
- [ ] No secrets committed; only public/synthetic example data.
- [ ] `docs/data_sources.md` updated if a data source was added or changed.

## Notes for reviewers

<!-- Anything reviewers should focus on, screenshots, etc. -->
