#!/usr/bin/env bash
# Get or renew a Kerberos ticket for the HDI.CO.AT domain.
#
#   kinit-hdi.sh [user@hdi.at]
#
# Renews the current ticket without a password while it is still renewable;
# otherwise asks for the password and gets a new one. The user is the VPN login
# (UPN), from the argument or $HDI_UPN.
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
. "$dir/env.sh"

upn=${1:-${HDI_UPN:-}}

if klist -s 2>/dev/null && kinit -R 2>/dev/null; then
  echo "Ticket renewed."
else
  if [[ -z $upn ]]; then
    echo "No renewable ticket. Pass your VPN login: $0 user@hdi.at (or set HDI_UPN)" >&2
    exit 1
  fi
  # -E: the UPN is an enterprise principal, resolved inside HDI.CO.AT
  # -C: let the KDC rewrite it to the real account name
  kinit -E -C "$upn"
fi
klist | sed -n '2p;/krbtgt/,+1p'
