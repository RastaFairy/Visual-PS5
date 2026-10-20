/* PS5 RetroArch - smb:// paths in RetroArch's VFS (src/ps5_smb_vfs.c, patches/series 0136).
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PS5_SMB_VFS_H
#define PS5_SMB_VFS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /* A file of the saved server, read-only, its size in *size; NULL otherwise. */
    void *ps5_smb_open(const char *url, unsigned mode, int64_t *size);
    int64_t ps5_smb_read(void *file, void *buffer, uint64_t length);
    int64_t ps5_smb_seek(void *file, int64_t offset, int whence); /* 0, or -1 */
    int64_t ps5_smb_tell(void *file);
    void ps5_smb_close(void *file);
    /* RETRO_VFS_STAT_* flags, 0 when the path is not there. */
    int ps5_smb_stat(const char *url, int64_t *size);
    void *ps5_smb_opendir(const char *url);
    bool ps5_smb_readdir(void *dir);
    const char *ps5_smb_dirent_name(void *dir);
    bool ps5_smb_dirent_is_dir(void *dir);
    void ps5_smb_closedir(void *dir);
    /* A local copy of url in directory, for a core that opens paths itself: its path. */
    bool ps5_smb_stage(const char *url, const char *directory, char *path, size_t size);

#ifdef __cplusplus
}
#endif

#endif
