<p align="center">
  <a href="https://hexsign.io">
    <img src="https://hexsign.io/logo.png" alt="HexSign" height="64" />
  </a>
</p>

<h1 align="center">HexSign — Fetch Signing Material (Bitrise Step)</h1>

<p align="center">
  Download Apple signing certificates and provisioning profiles from
  <a href="https://hexsign.io">HexSign</a> in your Bitrise workflows.
</p>

---

## What it does

Fetches the certificate (`.p12` + password) and/or provisioning profile (`.mobileprovision`)
you've stored in HexSign, places them on disk, and exposes the paths as env vars for
downstream steps (`certificate-and-profile-installer`, `xcode-archive`, `fastlane`, etc.).

Either of `certificate_id` and `profile_id` can be omitted — the step handles
fetch-cert-only, fetch-profile-only, and fetch-both flows in a single configuration.

## Usage

```yaml
steps:
  - hexsign-fetch-signing-material@0:
      inputs:
        - certificate_id: $HEXSIGN_CERT_ID
        - profile_id:     $HEXSIGN_PROFILE_ID
        - client_id:      $HEXSIGN_CLIENT_ID
        - client_secret:  $HEXSIGN_CLIENT_SECRET
  - certificate-and-profile-installer@1:
      inputs:
        - certificate_url:     file://$HEXSIGN_CERTIFICATE_PATH
        - certificate_passphrase: # read the .password file in a script step first
        - provisioning_profile_url: file://$HEXSIGN_PROFILE_PATH
  - xcode-archive@5: {}
```

Add `HEXSIGN_CLIENT_ID` and `HEXSIGN_CLIENT_SECRET` as **secret env vars** in your
Bitrise workflow editor — never put them in `bitrise.yml`.

## Inputs

| Key | Required | Default | Description |
|---|---|---|---|
| `certificate_id` | one of cert/profile | — | HexSign certificate ID. Omit to skip cert download. |
| `profile_id`     | one of cert/profile | — | HexSign provisioning profile ID. Omit to skip profile download. |
| `client_id`      | yes | `$HEXSIGN_CLIENT_ID` | OAuth2 client ID (sensitive). |
| `client_secret`  | yes | `$HEXSIGN_CLIENT_SECRET` | OAuth2 client secret (sensitive). |
| `scopes`         | no  | (CLI default) | Space-separated OAuth scopes. |
| `output_dir`     | yes | `$BITRISE_DEPLOY_DIR` | Where to write downloaded files. |
| `cli_version`    | yes | `latest` | `hexsign-cli` release tag (e.g. `v0.2.1`) or `latest`. |

## Outputs

| Env var | Description |
|---|---|
| `HEXSIGN_CERTIFICATE_PATH` | Absolute path to the `.p12` (empty if no cert fetched). |
| `HEXSIGN_CERTIFICATE_PASSWORD_PATH` | Absolute path to the `.password` file. |
| `HEXSIGN_PROFILE_PATH` | Absolute path to the `.mobileprovision` (empty if no profile fetched). |

## How auth works

The step exports `HEXSIGN_CLIENT_ID` / `HEXSIGN_CLIENT_SECRET` before invoking the CLI,
which puts the CLI in **machine mode** — it exchanges them for an access token against
`identity.hexsign.net/oauth2/token` and uses it for the download requests.

Provision a service credential under **Settings → CLI Tokens** in the
[HexSign dashboard](https://dashboard.hexsign.net). The secret is shown exactly once.

## CLI version & breaking changes

Default `cli_version: latest` resolves to the latest [`hexsign-cli`](https://github.com/hexsign/hexsign-cli/releases)
release at run time, with SHA-256 verification against the release's signed
`checksums.txt`. Pin to a tag (e.g. `cli_version: v0.2.1`) if you want hermetic builds.

## Local testing

```sh
# Populate .bitrise.secrets.yml with HEXSIGN_CLIENT_ID, HEXSIGN_CLIENT_SECRET,
# TEST_CERTIFICATE_ID, TEST_PROFILE_ID, then:
bitrise run test
```

## Publishing to the Bitrise Step Library

1. Fork [`bitrise-io/bitrise-steplib`](https://github.com/bitrise-io/bitrise-steplib).
2. `export MY_STEPLIB_REPO_FORK_GIT_URL=<your fork's HTTPS clone URL>`
3. Tag this repo: `git tag 0.1.0 && git push --tags`
4. `bitrise run share-this-step` — runs `stepman share start/create/finish`,
   which opens a PR to the steplib. The Bitrise team reviews and merges.

## License

[MIT](LICENSE).
