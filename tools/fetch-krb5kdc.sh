#!/bin/sh
# Unpack Debian's MIT Kerberos KDC (krb5-kdc and its libraries) under .deps/krb5kdc/root for
# the offline Kerberos tests (tests/security/kerberos). Nothing is installed system-wide and
# no /etc/krb5.conf is created. Needs apt-get (Debian/LMDE).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)/.deps/krb5kdc
mkdir -p "$root/debs" && cd "$root/debs"
apt-get download krb5-kdc krb5-admin-server krb5-user libkadm5srv-mit12 libkadm5clnt-mit12 \
    libkdb5-10t64 libgssrpc4t64 libverto1t64 libverto-libev1t64 libev4t64
for d in *.deb; do dpkg -x "$d" ../root; done
echo "MIT KDC unpacked under $root/root"
