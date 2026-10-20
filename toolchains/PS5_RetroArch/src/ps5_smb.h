/* PS5 RetroArch - the SMB server the WebUI's SMB page saves and the file browser's SMB
 * entry opens (libsmb2, tools/build-libsmb2.sh).
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One server and one share, saved on the console in <title>/config/smb.cfg as
 * smb_server, smb_share, smb_folder, smb_user, smb_password and smb_workgroup. The
 * password is only ever read here, to sign in: no answer, log or URL carries it.
 */
#ifndef PS5_SMB_H
#define PS5_SMB_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct smb2_context;

    typedef struct ps5_smb_config
    {
        char server[256]; /* a name or address, with :port when it is not 445 */
        char share[256];
        char folder[512]; /* inside the share, '/'-separated, no leading slash */
        char user[128];   /* empty: guest */
        char password[256];
        char workgroup[128];
    } ps5_smb_config;

    /* The saved server, from the file at path; false when it names no server and share. */
    bool ps5_smb_config_load(const char *path, ps5_smb_config *config);

    /* A signed-in connection to share (NULL: IPC$, for the share list), or NULL with a
     * sentence for the user in why. Free it with ps5_smb_disconnect. */
    struct smb2_context *ps5_smb_connect(const ps5_smb_config *config, const char *share, char *why,
                                         size_t why_size);
    void ps5_smb_disconnect(struct smb2_context *context);
    /* libsmb2's own words for this thread's last failed connection, for logs. */
    const char *ps5_smb_last_detail(void);
    /* libsmb2 keeps its contexts on one list without a lock: these take ours. */
    bool ps5_smb_alive(struct smb2_context *context);

    /* The server's visible disk shares, each given to each(); their count, or -1 and why. */
    int ps5_smb_shares(const ps5_smb_config *config, void (*each)(const char *name, void *data),
                       void *data, char *why, size_t why_size);

    /* Whether the share opens and the folder is a folder in it. */
    bool ps5_smb_check(const ps5_smb_config *config, char *why, size_t why_size);

    /* The file browser's path for the saved server: smb://server/share[/folder]. */
    bool ps5_smb_root(const ps5_smb_config *config, char *path, size_t size);

#ifdef __cplusplus
}
#endif

#endif
