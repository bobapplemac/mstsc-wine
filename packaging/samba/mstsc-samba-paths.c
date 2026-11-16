/* mstsc-wine: preloaded into the bundled ntlm_auth only (ADR-0042).
 *
 * Samba compiles its module directory in (dyn_MODULESDIR, e.g.
 * /usr/lib/x86_64-linux-gnu/samba) and scans <dir>/gensec at start-up, so a private
 * ntlm_auth would load the host's Samba modules if the host has Samba installed.
 * This constructor points the module directory at <directory of this file>/modules
 * inside the bundle before main() runs. No other behaviour changes.
 *
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <string.h>

__attribute__((constructor)) static void mstsc_samba_paths(void)
{
    static char dir[PATH_MAX];
    const char *(*set_modulesdir)(const char *);
    Dl_info info;
    char *slash;

    if (!dladdr((void *)mstsc_samba_paths, &info) || !info.dli_fname) return;
    if (strlen(info.dli_fname) + sizeof("/modules") >= sizeof(dir)) return;
    strcpy(dir, info.dli_fname);
    if (!(slash = strrchr(dir, '/'))) return;
    strcpy(slash, "/modules");
    set_modulesdir = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "set_dyn_MODULESDIR");
    if (set_modulesdir) set_modulesdir(dir);
}
