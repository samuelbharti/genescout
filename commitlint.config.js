// Conventional Commits rules for CANDID (used by the commitlint hook and CI).
// See https://www.conventionalcommits.org and @commitlint/config-conventional.
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "type-enum": [
      2,
      "always",
      [
        "feat",
        "fix",
        "docs",
        "chore",
        "refactor",
        "test",
        "build",
        "ci",
        "perf",
        "style",
        "revert",
      ],
    ],
  },
};
