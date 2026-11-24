# CodeBar project site

Static site for GitHub Pages. English is the default, with `zh/` and `ja/` language paths.

## Build

From the repository root:

```bash
python3 site/build.py --base /code_bar/
```

Output goes to `site/dist/`. Asset and language URLs are prefixed with `/code_bar/`, which is the project-site path on GitHub Pages.

## Local preview

The built files expect to be served under `/code_bar/`, not from the dist folder root:

```bash
mkdir -p /tmp/codebar-pages-preview/code_bar
cp -R site/dist/. /tmp/codebar-pages-preview/code_bar/
python3 -m http.server 8765 --directory /tmp/codebar-pages-preview
```

Then open http://127.0.0.1:8765/code_bar/ (and `/code_bar/zh/`, `/code_bar/ja/`).

## CI

`.github/workflows/pages.yml` builds the site on pull requests. It deploys only on a push to `main` or a manual `workflow_dispatch`. The site is not live until that deploy has succeeded and GitHub Pages is set to the GitHub Actions source.
