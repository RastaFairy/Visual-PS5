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

extern DLVARFIXUP libmod_misc_globals_fixup[];
extern DLVARFIXUP libmod_misc_locals_fixup[];
extern DLSYSFUNCS libmod_misc_functions_exports[];
extern void libmod_misc_module_initialize();
extern void libmod_misc_module_finalize();
extern void libmod_misc_process_exec_hook( INSTANCE * );
extern HOOK libmod_misc_handler_hooks[];

/* First real-module boot test: only libmod_misc is registered, since the
 * test .prg only calls STRLEN() (IMPORT "libmod_misc"). Everything else
 * this table would normally carry (libbggfx, libsdlhandler, ...) isn't
 * needed for this DCB and stays out. */
__FAKE_DL __fake_dl[2];

void fake_dl_init() {
    __fake_dl[0].dlname               = "libmod_misc";
    __fake_dl[0].constants_def        = NULL;
    __fake_dl[0].types_def            = NULL;
    __fake_dl[0].globals_def          = NULL;
    __fake_dl[0].locals_def           = NULL;
    __fake_dl[0].globals_fixup        = libmod_misc_globals_fixup;
    __fake_dl[0].locals_fixup         = libmod_misc_locals_fixup;
    __fake_dl[0].functions_exports    = libmod_misc_functions_exports;
    __fake_dl[0].module_initialize    = libmod_misc_module_initialize;
    __fake_dl[0].module_finalize      = libmod_misc_module_finalize;
    __fake_dl[0].instance_create_hook = NULL;
    __fake_dl[0].instance_destroy_hook = NULL;
    __fake_dl[0].instance_pre_execute_hook = NULL;
    __fake_dl[0].instance_pos_execute_hook = NULL;
    __fake_dl[0].process_exec_hook    = libmod_misc_process_exec_hook;
    __fake_dl[0].handler_hooks        = libmod_misc_handler_hooks;
    __fake_dl[0].modules_dependency   = NULL;

    __fake_dl[1].dlname = NULL;
}

#endif
