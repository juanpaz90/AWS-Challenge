# Contributing

## Setup

```bash
task setup   # installs the pre-commit and commit-msg git hooks
task lint    # runs every hook against the whole repository
```

Required tools are listed in the [README](README.md#prerequisites).

## Workflow — trunk-based development

- Commit directly to `main` in small, self-contained commits. `main` must always stay deployable: run `task lint` (the hooks do this on every commit) before pushing.
- For larger or riskier changes, use an optional **short-lived branch** (`<type>/<short-description>`, e.g. `feat/kind-cluster-module`) and merge it back quickly.
- Once CI exists (Phase 11), its checks run on every push to `main`; fix a red build before anything else.

## Commit messages — Conventional Commits

All commits follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). The `commit-msg` hook rejects anything else.

```
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Use for |
|---|---|
| `feat` | New capability (module, chart, endpoint, task) |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or changing tests |
| `ci` | GitHub Actions workflows |
| `build` | Dockerfile, image build, dependencies |
| `chore` | Tooling, config, housekeeping |
| `perf` | Performance improvement |
| `style` | Formatting only |
| `revert` | Reverting a previous commit |

### Scopes

Use the area being changed: `app`, `chart`, `cluster`, `platform`, `apps`, `aws`, `observability`, `gitops`, `ci`, `docs`, `adr`.

### Examples

```
feat(cluster): add kind-cluster module with registry mirror
fix(chart): drop all capabilities in migration job
docs(adr): add ADR-0010 for backup strategy
chore: pin pre-commit hook versions
feat(platform)!: replace metrics-server chart values

BREAKING CHANGE: requires re-applying 20-platform.
```

### AI-assisted changes

Per [`project-plan.md` §8.3](docs/project-plan.md#83-the-loop-for-each-slice), commit the raw AI output and your corrections **separately**, and reference the prompt log entry:

```
feat(eks): add eks module (raw AI output, P-007)
fix(eks): narrow IAM policy and pin addon versions (corrections to P-007)
```

## Definition of done

See [`project-plan.md` §9](docs/project-plan.md#9-definition-of-done-global). In short: `task lint` passes, docs are regenerated, the change is applied to kind and the relevant tests pass.
