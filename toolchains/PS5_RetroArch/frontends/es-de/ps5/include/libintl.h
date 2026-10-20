/* PS5 RetroArch - gettext for EmulationStation on the PS5: English, untranslated.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ES-DE translates through libintl (es-core's LocalizationUtil), and the console
 * has no libintl. The port is built without its message catalogs
 * (COMPILE_LOCALIZATIONS=OFF), so every lookup is the identity: the message ids
 * are ES-DE's English text, which is what it shows. Its own context lookups
 * (pgettextBuiltin) already fall back to the id when nothing is translated.
 */
#ifndef PS5_RETROARCH_ESDE_LIBINTL_H
#define PS5_RETROARCH_ESDE_LIBINTL_H

#include <locale.h>

#ifndef LC_MESSAGES
#define LC_MESSAGES 6
#endif

#ifdef __cplusplus
extern "C" {
#endif

static inline char *gettext(const char *msgid)
{
    return (char *)msgid;
}

static inline char *dgettext(const char *domain, const char *msgid)
{
    (void)domain;
    return (char *)msgid;
}

static inline char *ngettext(const char *msgid, const char *msgid_plural, unsigned long n)
{
    return (char *)(n == 1 ? msgid : msgid_plural);
}

static inline char *textdomain(const char *domain)
{
    return (char *)(domain ? domain : "messages");
}

static inline char *bindtextdomain(const char *domain, const char *directory)
{
    (void)domain;
    return (char *)directory;
}

static inline char *bind_textdomain_codeset(const char *domain, const char *codeset)
{
    (void)domain;
    return (char *)codeset;
}

#ifdef __cplusplus
}
#endif

#endif
