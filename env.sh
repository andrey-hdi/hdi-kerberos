# Source this file: points the Kerberos libraries (kinit, klist, kvno, curl)
# at krb5-hdi.conf first, then the system config.
#   . ~/work/hdi-kerberos/env.sh
_hdi_krb_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
export KRB5_CONFIG="$_hdi_krb_dir/krb5-hdi.conf:/etc/krb5.conf"
unset _hdi_krb_dir
