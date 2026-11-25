# hdi-kerberos

Kerberos sign-in to the HDI domain from a Linux machine that is not joined to
it, and REST calls to devops.hdi.at with the ticket instead of a PAT. Sign in
with your VPN password once; a systemd timer keeps the ticket alive for up to
7 days. Needs the VPN and `krb5-workstation` (Fedora).

| File | Purpose |
|---|---|
| `krb5-hdi.conf` | Realm `HDI.CO.AT`; maps `hdi.at` hosts to it. KDCs come from DNS. |
| `env.sh` | `. env.sh` sets `KRB5_CONFIG` to that file plus `/etc/krb5.conf`. |
| `kinit-hdi.sh` | Renews the ticket, or gets a new one with your VPN login. `--renew-only` never prompts (used by the timer). |
| `systemd/hdi-krb-renew.timer` | Runs the service every 2 hours, and at once after sleep or boot if a run was missed. |
| `systemd/hdi-krb-renew.service` | Runs `kinit-hdi.sh --renew-only`. |
| `azdo.sh` | `curl --negotiate` against `https://devops.hdi.at/HdiCollection/`. |

## Setup (once)

```sh
mkdir -p ~/.config/systemd/user
ln -sf ~/work/hdi-kerberos/systemd/hdi-krb-renew.* ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now hdi-krb-renew.timer
~/work/hdi-kerberos/kinit-hdi.sh user@hdi.at        # asks for the VPN password
```

The units are symlinks, so a `git pull` updates them (run
`systemctl --user daemon-reload` after one). Set `HDI_UPN` to skip the argument
to `kinit-hdi.sh`.

## Use

```sh
~/work/hdi-kerberos/azdo.sh DevOps/_apis/git/repositories | jq -r '.value[].name'
AZDO_API_VERSION= ~/work/hdi-kerberos/azdo.sh _apis/connectionData | jq .authenticatedUser.providerDisplayName
```

Extra arguments go to curl, e.g. `-X POST -d @body.json` or `-D headers.txt`.
A 2xx response goes to stdout; any other prints `HTTP <code>: <message>` to
stderr and exits 1, so `| jq` never sees an error page. For plain
`klist`/`kvno`/`curl`, source `env.sh` first.

## Automatic renewal

A ticket lasts 10 hours and can be renewed without a password for 7 days from
the sign-in, but only while it is still valid: once it has expired, renewing
fails and only the password helps. So the timer renews every 2 hours, well
inside each 10-hour window.

The renewal never prompts. With no ticket, past the 7-day limit, with the VPN
down or the laptop asleep through an expiry, it logs one line, exits 0 and
leaves it to the next `kinit-hdi.sh`, which asks for the password.

```sh
journalctl --user -u hdi-krb-renew.service -n 5          # what the last runs did
systemctl --user list-timers hdi-krb-renew.timer         # when the next one runs
systemctl --user start hdi-krb-renew.service             # renew now
systemctl --user disable --now hdi-krb-renew.timer       # stop renewing
```

## How it works

- The VPN login `user@hdi.at` is a UPN in the AD domain `hdi.co.at`; there is
  no `HDI.AT` realm. `kinit -E` sends it as an enterprise principal and the
  domain controller resolves it to the account (`klist` shows `<sam>@HDI.CO.AT`).
- The server ticket is `HTTP/devops.hdi.at@HDI.CO.AT`. Without the
  `[domain_realm]` mapping the libraries would look for a realm `HDI.AT`.
- The ticket sits in the KCM cache, so every shell and user service of the
  user sees it, the timer included. `kdestroy` removes it.

## Compared with a PAT

Nothing is stored on disk. The `IdentityPicker` API (AD people search), which
answers 401 to any PAT, works. CI and headless boxes still need a PAT.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Client not found in Kerberos database` | UPN wrong; try `kinit <sam>@HDI.CO.AT`. |
| `Server not found in Kerberos database` | `KRB5_CONFIG` not set (source `env.sh`) or the host is not in AD. |
| `Cannot find KDC for realm` | VPN down; check `dig _kerberos._tcp.hdi.co.at SRV`. |
| HTTP 401 | No ticket in the cache: `klist`. |
| HTTP 400 "under preview" | Endpoint needs e.g. `AZDO_API_VERSION=6.0-preview`. |
| Password asked before the 7 days are up | A renewal was missed past an expiry (asleep, VPN down); see the journal. |
| Journal: `Renewal skipped: … Cannot contact any KDC` | VPN was down at that run; the next run retries. |
