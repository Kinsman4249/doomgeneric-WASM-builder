# Contributing to doomgeneric-WASM-builder

Thanks for considering a contribution! This is a small project and the process is intentionally lightweight.

## How to report a bug

Open an issue using the **Bug report** template. Please include:

- The version of this project you are running (commit SHA or release tag)
- The exact command or workflow that triggered the issue
- The full error output (redact any secrets, credentials, or personal data)
- Relevant log excerpts
- Your runtime environment (OS, browser, deployment target, and so on)

## How to propose a feature

Open an issue using the **Feature request** template. Describe the use case before the implementation. Knowing why is more useful than what in early discussion.

## How to submit a change

1. **Fork** the repo and create a feature branch (`git checkout -b feat/short-description`).
2. **Make your change.** Keep changes focused, one logical change per PR.
3. **Test it.** Because the build tooling and the generated `index.html` both live in `install.sh`, run `./install.sh` inside the Fedora Distrobox container described in the README, then open the produced `index.html` and confirm the game loads, keys work (including E for Use and F for Fire), and the display scaling and filter presets behave.
4. **Lint it.** Keep the shell script clean. If you have `shellcheck` available, run it against `install.sh`.
5. **Update documentation.** If your change alters user-visible behavior, update `README.md`.
6. **Open a PR** against `main`. Fill in the PR template.

## Coding conventions

- Follow the style of the surrounding code. Match formatting, naming, and structure of existing files.
- Comment generously. This project aims to be readable by someone new to the language, so explain what each part is doing and why.
- **No new dependencies** without strong justification. The appeal of a small project is the small, predictable surface area.
- **No telemetry, ever.** This project must not phone home.

## Commit messages

Conventional Commits style is preferred but not required:

```
feat: add support for X
fix: handle empty response from Y
docs: clarify setup for Z
```

Keep the subject under 72 characters. Add a body if the change is not obvious from the diff.

## Releases

Maintainers cut releases by tagging `vX.Y.Z` on `main`. Pre-1.0 versioning rules:

- `0.X.0` for any user-visible change
- `0.X.Y` for bug-fix-only patch releases

After 1.0, standard SemVer applies.
