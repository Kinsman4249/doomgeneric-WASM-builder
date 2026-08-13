[Back to README](../README.md)

# Deploying

## Deploying into an existing web server

If this machine already runs Apache or Nginx, the installer can place the
build inside one of its existing sites. Answer yes to the deploy prompt
(or set `WEBEXPORT=1`) and it will:

1. Detect installed servers (Debian: `apache2`, Fedora: `httpd`, and
   `nginx` on both), then read their enabled site configs
   (`sites-enabled` on Debian, `conf.d` on Fedora) for document roots and
   server names.
2. Show a numbered menu of discovered sites, plus "enter a path manually"
   and "skip".
3. Copy `index.html`, `doomgeneric.js`, and the freeware pack (if
   downloaded) into a `doomgeneric-WASM/` subfolder of the chosen site
   root. Nothing else in the site root is touched, and re-running
   replaces that subfolder cleanly.
4. Set least-privilege static-site permissions (directories 755, files
   644) owned by the account the server runs as (`www-data` on Debian,
   `apache` or `nginx` on Fedora), and on Fedora restore the SELinux
   context so the server may read the files.

The server's own configuration is never modified and nothing is
reloaded: whatever address already serves that site root simply gains a
`/doomgeneric-WASM/` path. DNS and vhosts remain your business.

## Deploying to Cloudflare Pages

Every tagged release (`git tag vX.Y.Z && git push --tags`) can also deploy
the playable site straight to Cloudflare Pages. The `deploy-cloudflare-pages`
job in `.github/workflows/release.yml` downloads the freeware pack fresh on
the GitHub Actions runner and uploads it straight to Cloudflare's API - the
WAD files are never committed to this repo, never a release asset, and never
stored in git history anywhere. If the secrets below are not set, the job
prints a warning and skips itself; it does not fail the release.

This is a one-time setup. Cloudflare's dashboard reorganizes itself
periodically, so if a menu below has moved, search the dashboard for the
same words (e.g. "API Tokens", "Pages").

### 1. Create the Pages project

1. Go to <https://dash.cloudflare.com>, log in, and pick your account if
   asked.
2. Left sidebar: **Workers & Pages**.
3. Click **Create** (top right), then the **Pages** tab.
4. Click **Upload assets** (NOT "Connect to Git" - the GitHub Actions job
   uploads directly, so Cloudflare does not need its own copy of this repo
   or a build step on Cloudflare's side).
5. Give it a project name, e.g. `doomgeneric-wasm`. Write this down; it is
   the `CLOUDFLARE_PAGES_PROJECT` secret in step 4.
6. On the upload screen, drag in any single file (e.g. this README) just to
   get past the wizard and create the project - the real deploy comes from
   GitHub Actions afterward and will replace it.
7. Click **Deploy site**.

Pitfall: the **Create** button's default tab is often **Workers**, not
**Pages** - if you land on a project whose URL is
`<random-words>.<subdomain>.workers.dev` instead of
`<project-name>.pages.dev`, you made a Worker by mistake (it also has a
lower free-tier request cap: 100,000/day account-wide, versus Pages'
unmetered requests). Delete it and redo step 3-4, making sure the **Pages**
tab is selected before clicking **Upload assets**. A project at
`<name>.pages.dev` (e.g. `doom-8j2.pages.dev`) is a correctly-created Pages
project - use that `.pages.dev` prefix (`doom-8j2` in that example) as the
`CLOUDFLARE_PAGES_PROJECT` secret value.

### 2. Create an API token

1. Click your profile icon (top right) > **My Profile**.
2. Left sidebar: **API Tokens**.
3. Click **Create Token**.
4. Find the **"Edit Cloudflare Workers"** template and click **Use
   template**. (Despite the name, this template's permissions also cover
   Pages. If you would rather scope it tighter: use **Custom token** and
   add the permission **Account > Cloudflare Pages > Edit**.)
5. Under **Account Resources**, restrict it to your specific account rather
   than "All accounts" if given the choice.
6. Click **Continue to summary**, then **Create Token**.
7. Copy the token now - Cloudflare shows it exactly once. If you lose it,
   delete the token and make a new one.

### 3. Find your Account ID

1. Still in the Cloudflare dashboard, go to **Workers & Pages** (left
   sidebar).
2. The **Account ID** is shown in the right-hand sidebar of that page (also
   visible on most other dashboard pages in the same spot). Copy it.

### 4. Add the three GitHub secrets

1. Open this repo on GitHub.
2. **Settings** (top tab) > **Secrets and variables** (left sidebar) >
   **Actions**.
3. Click **New repository secret** three times, once per row:

   | Secret name                | Value                                   |
   |-----------------------------|------------------------------------------|
   | `CLOUDFLARE_API_TOKEN`      | the token from step 2                    |
   | `CLOUDFLARE_ACCOUNT_ID`     | the account ID from step 3               |
   | `CLOUDFLARE_PAGES_PROJECT`  | the project name from step 1 (e.g. `doomgeneric-wasm`) |

4. Push a version tag (or re-run the `Release` workflow from the Actions
   tab against an existing tag). The `Deploy (Cloudflare Pages)` job runs
   alongside the installer builds, and the site goes live at
   `https://<project-name>.pages.dev` (a custom domain can be attached
   under the Pages project's **Custom domains** tab afterward).

## Cleanup after deploying

Offered only when a web deploy actually completed. After verifying the
deployed copy really exists and is non-empty, it deletes the local build
artifacts (`doomgeneric.js`, `index.html`, the object directory, and the
downloaded freeware pack) and prints the exact list of what was removed.
Two things are never deleted without their own separate confirmation: the
packaged `site/` folder and tarball from the packaging step, and the
cloned source repo (removing the source means re-cloning before you can
rebuild). Declining cleanup leaves everything in place.
