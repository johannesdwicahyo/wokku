# Contributing to Wokku

Thanks for your interest. Wokku is an open-core project: the core PaaS is open source under AGPLv3, and a hosted commercial version (Wokku Cloud) is built on top. This document explains how to contribute and what you're agreeing to when you do.

## How development works

The public `wokku` repository is a **published view** of an upstream private repository (`wokku-cloud`) at each release. The release process strips files marked as commercial-only (billing, payment integrations, etc.) and publishes the remainder as a single squash commit per release on the **1st of every month** (or sooner for security patches).

Practically, this means:

- Pull requests are reviewed on this repo.
- When accepted, the maintainer ports the patch into the upstream repo, **preserving your authorship**. Your name and email stay on the commit.
- Your contribution appears in the next release with full attribution in the `CHANGELOG.md` for that release.
- The original PR is closed (not merged) once the patch is upstream — this is normal, your contribution is not lost.

Per-commit history in the public repo resets at each release. If line-by-line `git blame` matters to you, the CHANGELOG is your map back to attributions.

## Contributor License Agreement (CLA)

Before any pull request can be accepted, you must sign the CLA. This is automated: when you open your first PR, the **CLA Assistant** bot will ask you to confirm the agreement by replying to the PR. You sign once, ever, across all your future PRs.

**What the CLA says**, in plain language:

- You retain copyright over your contribution.
- You grant Wokku (specifically Johannes Dwi Cahyo) a perpetual, worldwide, irrevocable license to use, modify, sublicense, and distribute your contribution, including under different license terms (e.g., the commercial Wokku Cloud edition).
- You represent that you actually wrote the contribution, or have rights to grant the above license over it.
- You don't get money or warranties.

The full text is in [`CLA.md`](./CLA.md). It is closely modeled on the Apache Individual Contributor License Agreement (ICLA). If you contribute on behalf of an employer, your employer must sign the corporate variant — open an issue and we'll send the form.

## What's in scope for contributions

Anything in this repository is fair game. Common high-value contributions:

- **Templates** (`app/views/dashboard/templates/`, related migrations): adding one-click deploy templates for new apps
- **Translations** (`config/locales/`): adding or improving non-English locales
- **Provisioning scripts** (`scripts/`): improvements to Dokku host provisioning, backups, cleanup
- **Documentation** (`docs/`, `README.md`)
- **Bug fixes** anywhere
- **OSS-only features** that don't depend on commercial billing

Things that probably won't be accepted upstream:

- Hooks specifically meant to integrate with paid SaaS providers (talk to us first)
- Architectural refactors of areas under heavy active work — open an issue first to avoid wasted effort

## Workflow

1. Fork the `wokku` repository on GitHub
2. Create a topic branch from `main`
3. Make your change with clear commit messages
4. Run any relevant tests (see `README.md` if scripts are present)
5. Open a pull request describing what and why
6. Sign the CLA when prompted by the bot
7. Maintainer reviews; iterate as needed
8. Once approved, your patch is ported upstream. The PR will be closed shortly after — this is the expected outcome, your work shipped.

## Code of conduct

Be civil. Don't ship malicious code. Don't spam. Don't include other people's work without proper licensing.

## Reporting security issues

**Do not file public GitHub issues for security vulnerabilities.** Email `security@wokku.cloud` with details. We respond within 48 hours and credit reporters publicly once a fix has shipped.

## License

This project is licensed under [AGPL-3.0](./LICENSE). By contributing, you agree your contribution will be licensed under AGPL-3.0 in this repository, and additionally licensed to Wokku per the CLA above.
