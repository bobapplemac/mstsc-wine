# Source this to use the rootless build sysroot (.deps/sysroot) for building Wine.
_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYSROOT=$_root/.deps/sysroot
export PATH=$SYSROOT/usr/bin:$PATH
export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$SYSROOT
export CPPFLAGS="-I$SYSROOT/usr/include -I$SYSROOT/usr/include/x86_64-linux-gnu"
export LDFLAGS="-L$SYSROOT/usr/lib/x86_64-linux-gnu -Wl,-rpath-link,/usr/lib/x86_64-linux-gnu"
export BISON_PKGDATADIR=$SYSROOT/usr/share/bison
export M4=/usr/bin/m4
export autom4te_perllibdir=$SYSROOT/usr/share/autoconf
export AUTOM4TE_CFG=$SYSROOT/usr/share/autoconf/autom4te.cfg
export AUTOM4TE=$SYSROOT/usr/bin/autom4te
export AC_MACRODIR=$SYSROOT/usr/share/autoconf
