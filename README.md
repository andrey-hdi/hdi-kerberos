# hdi-kerberos

Kerberos sign-in to the HDI domain from a Linux machine that is not joined to
it, and REST calls to devops.hdi.at with the ticket instead of a PAT. Needs the
VPN and `krb5-workstation` (Fedora).

| File | Purpose |
|---|---|
| `krb5-hdi.conf` | Realm `HDI.CO.AT`; maps `hdi.at` hosts to it. KDCs come from DNS. |
| `env.sh` | `. env.sh` sets `KRB5_CONFIG` to that file plus `/etc/krb5.conf`. |
| `kinit-hdi.sh` | Renews the ticket, or gets a new one with your VPN login. |
| `azdo.sh` | `curl --negotiate` against `https://devops.hdi.at/HdiCollection/`. |

## Use

```sh
~/work/hdi-kerberos/kinit-hdi.sh user@hdi.at        # asks for the VPN password
~/work/hdi-kerberos/azdo.sh DevOps/_apis/git/repositories | jq -r '.value[].name'
AZDO_API_VERSION= ~/work/hdi-kerberos/azdo.sh _apis/connectionData | jq .authenticatedUser.providerDisplayName
```

Extra arguments go to curl, e.g. `-X POST -d @body.json`. A 2xx response
goes to stdout; any other prints `HTTP <code>: <message>` to stderr and exits 1,
so `| jq` never sees an error page. Set `HDI_UPN` to
skip the argument to `kinit-hdi.sh`. For plain `klist`/`kvno`/`curl`, source
`env.sh` first.

## How it works

- The VPN login `user@hdi.at` is a UPN in the AD domain `hdi.co.at`; there is
  no `HDI.AT` realm. `kinit -E` sends it as an enterprise principal and the
  domain controller resolves it to the account (`klist` shows `<sam>@HDI.CO.AT`).
- The server ticket is `HTTP/devops.hdi.at@HDI.CO.AT`. Without the
  `[domain_realm]` mapping the libraries would look for a realm `HDI.AT`.
- The ticket lasts 10 hours and renews without a password for 7 days
  (`kinit-hdi.sh` does that); after that it asks for the password again.
- The ticket sits in the KCM cache, so every shell of the user sees it.
  `kdestroy` removes it.

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
