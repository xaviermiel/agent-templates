## What this repo is

A public showcase of Pinata agent templates across multiple engines (harnesses). Each template is a self-contained, deployable example — there is no root-level build, test, or lint. Work happens inside each template directory.

## Repo layout

```
<engine>/<category>/<template>/
```

- **engine** — the runtime powering the agent (e.g. `openclaw/`, `hermes/`). New engines get a new top-level folder.
- **category** — the role the agent plays (`basic`, `monitoring-and-alerts`, `actions-and-transactions`, `data-extraction-and-summarization`, `interaction-and-interfaces`, `orchestration-and-multi-agent`). Mirrored across engines.
- **template** — one deployable agent.

## Template anatomy

- `manifest.json` — deployment contract. Pinata reads this to provision the agent. Full schema: https://agents.pinata.cloud/schemas/manifest.v1.json
- `README.md` — human-facing docs.
- `workspace/` — the agent's cwd at runtime. Persona/runtime markdown files live here; conventions vary by engine.
- `setup.sh` (optional) — extra install steps invoked from `scripts.build`.

When editing persona or runtime behavior, edit files inside the relevant template's `workspace/`.

## Working in this repo

- Stay scoped to one template.
- Build/start commands belong in that template's `manifest.json` `scripts`, not at the root.
- Categories are mirrored across engines — if you add or rename one, check whether the other engine should follow.

## Recommended: Pinata CLI

The `pinata` CLI streamlines the dev loop — `templates validate <git-url>` checks a branch against the manifest schema before submitting, then `templates submit / update`, and `agents create -t <id>` + `chat` to test. See `pinata agents --help`.
