#ifndef __FAKE_DL_H
#define __FAKE_DL_H

#include <bgddl.h>

typedef struct __FAKE_DL {
    char            * dlname;
    DLCONSTANT      * constants_def;
    char            ** types_def;
    char            ** globals_def;
    char            ** locals_def;
    DLVARFIXUP      * globals_fixup;
    DLVARFIXUP      * locals_fixup;
    DLSYSFUNCS      * functions_exports;
    void            (* module_initialize)();
    void            (* module_finalize)();
    void            (* instance_create_hook)(INSTANCE *);
    void            (* instance_destroy_hook)(INSTANCE *);
    void            (* instance_pre_execute_hook)(INSTANCE *);
    void            (* instance_pos_execute_hook)(INSTANCE *);
    void            (* process_exec_hook)(INSTANCE *);
    HOOK            * handler_hooks;
    char           ** modules_dependency;
} __FAKE_DL;

/* Minimal boot test: the compiled .prg has zero module imports (confirmed by
 * inspecting the .dcb - NImports == 0 for a trivial RETURN-only program), so
 * dlibopen() is never actually called and this table never needs a real
 * entry. Just the empty terminator sentinel loadlib.h's dlibopen() scans for. */
__FAKE_DL __fake_dl[1];

void fake_dl_init() {
    __fake_dl[0].dlname = NULL;
}

#endif
