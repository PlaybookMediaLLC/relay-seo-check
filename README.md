# Relay SEO check

A GitHub Action that compares a pull request's preview deployment with your production site before merge, and ranks each SEO regression by the page's real Search Console traffic.

It finds what usually ships by accident in an ordinary pull request: a stray `noindex`, a changed or removed canonical tag, a removed title or meta description, a page that now redirects or fails, invalid structured data, a `robots.txt` rule that blocks a page, and a shrunk sitemap. Warnings cover changed titles and H1s, dropped internal links, new broken links, changed hreflang, removed social tags and shrunk content.

The check reads rendered HTML, so it works with any framework.

## Usage

1. In [Relay](https://relay.playbookmedia.io), open **Project settings → SEO checks** and create a CI token.
2. Store it in your repository as the secret `RELAY_CI_TOKEN`.
3. Add the step after the step that deploys your preview:

```yaml
on: pull_request

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      # ... deploy the preview, with an output named url ...
      - uses: PlaybookMediaLLC/relay-seo-check@v1
        with:
          token: ${{ secrets.RELAY_CI_TOKEN }}
          preview-url: ${{ steps.deploy.outputs.url }}
          fail-on: blocking
```

`fetch-depth: 0` lets the action list the files your pull request changed, so Relay checks the pages they render.

## Inputs

| Input             | Required | Default                          | Description                                              |
| ----------------- | -------- | -------------------------------- | -------------------------------------------------------- |
| `token`           | Yes      |                                  | The project's Relay CI token.                            |
| `preview-url`     | Yes      |                                  | The URL of the deployed preview.                         |
| `fail-on`         | No       | `blocking`                       | `blocking`, `warning` or `never`.                        |
| `relay-url`       | No       | `https://relay.playbookmedia.io` | The Relay origin.                                        |
| `timeout-minutes` | No       | `10`                             | How long to wait for the check.                          |

## Behavior

- The job summary lists each finding with its page, rule, before and after values, clicks and impressions, the highest-traffic page first.
- The label `relay-seo-override` on the pull request lets blocking findings pass. Relay records the override in the project's Activity log.
- If Relay cannot finish the check, or the project used its checks for the month, the action prints the reason and passes, unless `fail-on` is `warning`.
- The action needs no repository write permission. It uses only `curl` and `jq`, which GitHub's runners include.

## Pinning

For a fixed version, pin the action to a release commit instead of `@v1`:

```yaml
- uses: PlaybookMediaLLC/relay-seo-check@<commit-sha> # v1.0.0
```

## Preview hosts

Relay checks previews on your project's domain and its subdomains, and on `*.vercel.app`, `*.netlify.app`, `*.pages.dev` and `*.workers.dev`. Add other hosts in Relay. Protected previews can use a bypass header, such as Vercel's `x-vercel-protection-bypass`, or a Cloudflare Access service token. Relay sends it only to the preview host.

Full documentation: <https://relay.playbookmedia.io/docs/seo-checks>

## License

MIT
