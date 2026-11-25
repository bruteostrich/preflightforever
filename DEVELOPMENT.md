# Preflight Forever development

Notes for working on Preflight Forever. This file stays in the repository and is not packaged; players get `README.md`, `LICENSE.txt`, and `THIRD_PARTY_NOTICES.txt` alongside the addon code.

## Validation

The automated checks run the Lua code against mocked client APIs, covering queue decisions, coordinate conversion, event timing, UI construction, and failures. They also parse every Lua file as Lua 5.1. They **do not prove the addon has run successfully in the live game**. Follow [MANUAL_TESTS.md](MANUAL_TESTS.md) for the remaining in-game checks, especially Forever's coordinate projection and automatic `TakeTaxiNode` behavior.

```powershell
npm ci --ignore-scripts
npm test
.\scripts\Package.ps1
```

Node dependencies are development-only.

## Layout

The repository root is the addon folder: `PreflightForever.toc`, the Lua files, `README.md`, `LICENSE.txt` and `THIRD_PARTY_NOTICES.txt` ship to players. Development folders and files are excluded by the `ignore` list in `.pkgmeta`; dotfiles and git-ignored paths never ship. A new file at the root ships automatically, so add anything players shouldn't get to `.pkgmeta`.

## Releasing (CurseForge automatic packaging)

CurseForge packages the repository whenever a tag is pushed (project setting: package tagged commits). It names the folder from `package-as` in `.pkgmeta` and takes the release type from the tag: a tag containing `alpha` or `beta` is published as alpha or beta; any other tag is a release.

1. Update `## Version:` in `PreflightForever.toc`.
2. Run `npm test` and `.\scripts\Package.ps1`, and check the zip.
3. Commit, then tag with the same version and push the commit with its tag:

```bash
git tag 0.3.3
git push --follow-tags
```

After the first automatic build, check the file's game version on the CurseForge Files page.

## Local packaging

`scripts/Package.ps1` mirrors CurseForge's packager: it copies the repository root into a fresh `dist/package/PreflightForever`, skipping dotfiles, `.gitignore` entries and the top-level `.pkgmeta` ignore entries, then writes `dist/PreflightForever-<version>.zip` using the version in `PreflightForever.toc`. Only upload 0.3.2 or later: the 0.3.0 and 0.3.1 zips contain Polestar route data licensed under GPL-3.0.

## Route data

The reproducible importer is `scripts/ImportTaxiData.cjs`, and the source manifest is `research/sources/1.60.1.71091/manifest.json`. The Polestar license text that applied to the 0.3.0–0.3.1 route data is kept for reference in `research/licenses/LICENSE-ROUTES-Polestar.txt`.

## Art

The CurseForge logo source is `art/logo.svg`, with 400×400 and 1024×1024 PNG exports beside it.
