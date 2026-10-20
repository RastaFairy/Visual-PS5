/* PS5 RetroArch - smb:// paths in RetroArch's VFS (patches/series, 0136): the file
 * browser lists the share the WebUI saved, a core that reads through the VFS streams a
 * file from it, and one that opens paths itself gets a local copy (ps5_smb_stage).
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * After RetroArch's own SMB VFS (libretro-common/vfs/vfs_implementation_smb.c,
 * libretro/RetroArch@c68eea5598, GPL-3.0-or-later): reads looped past libsmb2's per-call
 * cap, a dropped connection mended in place. Read-only: nothing is written to a share.
 * A path is opened only on the saved server, so the saved password goes nowhere else.
 */
#include "ps5_smb_vfs.h"
#include "ps5_smb.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <smb2/smb2.h>
#include <smb2/libsmb2.h>

#include <libretro.h>

/* retroarch.log on the console (the title's stderr reaches no log); stderr on the host. */
#ifdef __PROSPERO__
void RARCH_LOG(const char *fmt, ...);
#define SMB_LOG RARCH_LOG
#else
#define SMB_LOG(...) fprintf(stderr, __VA_ARGS__)
#endif

#ifndef PS5_SMB_CONFIG
#define PS5_SMB_CONFIG "/app0/config/smb.cfg"
#endif

struct ps5_smb_file
{
    struct smb2_context *context;
    struct smb2fh *handle;
    ps5_smb_config config;
    char share[256];
    char path[1024];
    uint64_t position;
};

struct ps5_smb_dir
{
    struct smb2_context *context;
    struct smb2dir *dir;
    struct smb2dirent *entry;
    unsigned entries;
    char url[256];
};

/* The saved server, and the share and path a URL names on it: smb://server/share[/path]. */
static bool locate(const char *url, ps5_smb_config *config, char *share, size_t share_size,
                   char *path, size_t path_size)
{
    if (strncmp(url, "smb://", 6) != 0 || !ps5_smb_config_load(PS5_SMB_CONFIG, config))
    {
        SMB_LOG("[SMB] %s: no saved server (%s)\n", url, PS5_SMB_CONFIG);
        return false;
    }
    const char *server = url + 6, *slash = strchr(server, '/');
    const size_t server_length = slash ? (size_t)(slash - server) : strlen(server);
    if (server_length != strlen(config->server) ||
        strncmp(server, config->server, server_length) != 0 || !slash)
    {
        SMB_LOG("[SMB] %s: not a share of the saved server\n", url);
        return false;
    }
    const char *name = slash + 1, *rest = strchr(name, '/');
    const size_t name_length = rest ? (size_t)(rest - name) : strlen(name);
    if (!name_length || name_length >= share_size)
        return false;
    memcpy(share, name, name_length);
    share[name_length] = '\0';
    rest = rest ? rest + 1 : "";
    size_t length = strlen(rest);
    while (length && rest[length - 1] == '/')
        --length;
    if (length >= path_size)
        return false;
    memcpy(path, rest, length);
    path[length] = '\0';
    return true;
}

static struct smb2_context *connect_to(const ps5_smb_config *config, const char *share)
{
    char why[256];
    struct smb2_context *context = ps5_smb_connect(config, share, why, sizeof(why));
    if (!context)
        SMB_LOG("[SMB] %s: %s [%s]\n", share, why, ps5_smb_last_detail());
    return context;
}

static struct ps5_smb_file *open_file(const ps5_smb_config *config, const char *share,
                                      const char *path)
{
    struct ps5_smb_file *file = calloc(1, sizeof(*file));
    if (!file)
        return NULL;
    file->config = *config;
    snprintf(file->share, sizeof(file->share), "%s", share);
    snprintf(file->path, sizeof(file->path), "%s", path);
    if ((file->context = connect_to(config, share)) &&
        (file->handle = smb2_open(file->context, path, O_RDONLY)))
        return file;
    ps5_smb_disconnect(file->context);
    free(file);
    return NULL;
}

/* The connection went (the server restarted, or dropped an idle one): connect again and
 * open the file at the position the reader had reached. */
static bool mend(struct ps5_smb_file *file)
{
    ps5_smb_disconnect(file->context);
    file->handle = NULL;
    if (!(file->context = connect_to(&file->config, file->share)) ||
        !(file->handle = smb2_open(file->context, file->path, O_RDONLY)) ||
        smb2_lseek(file->context, file->handle, (int64_t)file->position, SEEK_SET, NULL) < 0)
        return false;
    SMB_LOG("[SMB] reconnected to %s\n", file->share);
    return true;
}

void *ps5_smb_open(const char *url, unsigned mode, int64_t *size)
{
    ps5_smb_config config;
    char share[256], path[1024];
    if ((mode & RETRO_VFS_FILE_ACCESS_WRITE) ||
        !locate(url, &config, share, sizeof(share), path, sizeof(path)) || !path[0])
        return NULL;
    struct ps5_smb_file *file = open_file(&config, share, path);
    struct smb2_stat_64 status;
    if (file && smb2_fstat(file->context, file->handle, &status) == 0)
    {
        *size = (int64_t)status.smb2_size;
        return file;
    }
    ps5_smb_close(file);
    return NULL;
}

int64_t ps5_smb_read(void *opened, void *buffer, uint64_t length)
{
    struct ps5_smb_file *file = opened;
    uint8_t *into = buffer;
    uint64_t done = 0;
    bool mended = false;
    /* libsmb2 caps each read at the server's maximum: a caller asking for more must
     * not take a short read for the end of the file. */
    while (done < length)
    {
        const uint64_t want = length - done > (1u << 30) ? (1u << 30) : length - done;
        const int got =
            file->handle ? smb2_read(file->context, file->handle, into + done, (uint32_t)want) : -1;
        if (got < 0 && !mended)
        {
            mended = true;
            if (mend(file))
                continue;
        }
        if (got <= 0)
            return done || got == 0 ? (int64_t)done : -1;
        done += (uint64_t)got;
        file->position += (uint64_t)got;
    }
    return (int64_t)done;
}

int64_t ps5_smb_seek(void *opened, int64_t offset, int whence)
{
    struct ps5_smb_file *file = opened;
    uint64_t now = 0;
    if (!file->handle && !mend(file))
        return -1;
    if (smb2_lseek(file->context, file->handle, offset, whence, &now) < 0)
        return -1;
    file->position = now;
    return 0;
}

int64_t ps5_smb_tell(void *opened)
{
    return (int64_t)((struct ps5_smb_file *)opened)->position;
}

void ps5_smb_close(void *opened)
{
    struct ps5_smb_file *file = opened;
    if (!file)
        return;
    if (file->handle && ps5_smb_alive(file->context))
        smb2_close(file->context, file->handle);
    ps5_smb_disconnect(file->context);
    free(file);
}

int ps5_smb_stat(const char *url, int64_t *size)
{
    ps5_smb_config config;
    char share[256], path[1024];
    if (!locate(url, &config, share, sizeof(share), path, sizeof(path)))
        return 0;
    /* shortcut: a connection for each stat (a few round trips on a LAN); keep one open
     * if browsing a large folder turns out slow. */
    struct smb2_context *context = connect_to(&config, share);
    struct smb2_stat_64 status;
    const bool found = context && smb2_stat(context, path, &status) == 0;
    if (context && !found)
        SMB_LOG("[SMB] %s: not there (NT status 0x%08X)\n", url,
                (unsigned)smb2_get_nterror(context));
    ps5_smb_disconnect(context);
    if (!found)
        return 0;
    if (size)
        *size = (int64_t)status.smb2_size;
    return RETRO_VFS_STAT_IS_VALID |
           (status.smb2_type == SMB2_TYPE_DIRECTORY ? RETRO_VFS_STAT_IS_DIRECTORY : 0);
}

void *ps5_smb_opendir(const char *url)
{
    ps5_smb_config config;
    char share[256], path[1024];
    if (!locate(url, &config, share, sizeof(share), path, sizeof(path)))
        return NULL;
    struct ps5_smb_dir *dir = calloc(1, sizeof(*dir));
    if (dir && (dir->context = connect_to(&config, share)) &&
        (dir->dir = smb2_opendir(dir->context, path)))
    {
        snprintf(dir->url, sizeof(dir->url), "%s", url);
        SMB_LOG("[SMB] %s: opened\n", url);
        return dir;
    }
    if (dir && dir->context)
        SMB_LOG("[SMB] %s: the folder did not open (NT status 0x%08X: %s)\n", url,
                (unsigned)smb2_get_nterror(dir->context), smb2_get_error(dir->context));
    if (dir)
        ps5_smb_disconnect(dir->context);
    free(dir);
    return NULL;
}

bool ps5_smb_readdir(void *opened)
{
    struct ps5_smb_dir *dir = opened;
    do
        dir->entry = smb2_readdir(dir->context, dir->dir);
    while (dir->entry && (!strcmp(dir->entry->name, ".") || !strcmp(dir->entry->name, "..")));
    dir->entries += dir->entry != NULL;
    return dir->entry != NULL;
}

const char *ps5_smb_dirent_name(void *opened)
{
    struct ps5_smb_dir *dir = opened;
    return dir->entry ? dir->entry->name : NULL;
}

bool ps5_smb_dirent_is_dir(void *opened)
{
    struct ps5_smb_dir *dir = opened;
    return dir->entry && dir->entry->st.smb2_type == SMB2_TYPE_DIRECTORY;
}

void ps5_smb_closedir(void *opened)
{
    struct ps5_smb_dir *dir = opened;
    if (!dir)
        return;
    SMB_LOG("[SMB] %s: listed %u entries\n", dir->url, dir->entries);
    if (ps5_smb_alive(dir->context))
        smb2_closedir(dir->context, dir->dir);
    ps5_smb_disconnect(dir->context);
    free(dir);
}

bool ps5_smb_stage(const char *url, const char *directory, char *path, size_t size)
{
    const char *name = strrchr(url, '/');
    if (!name || !name[1] || !directory || !*directory ||
        (mkdir(directory, 0777) != 0 && errno != EEXIST))
        return false;
    /* shortcut: one copy at a time, named as on the share; two games of the same file
     * name loaded at once (a subsystem's) would need a folder each. */
    const int length = snprintf(path, size, "%s/%s", directory, name + 1);
    if (length <= 0 || (size_t)length >= size)
        return false;
    int64_t total = 0, copied = 0, got = 0;
    void *from = ps5_smb_open(url, RETRO_VFS_FILE_ACCESS_READ, &total);
    if (!from)
        return false;
    /* write(), not stdio: this console's fwrite() runs at 3-13 MiB/s where write() of
     * a few MiB runs at 150-230 (patches/series, 0094). */
    const int to = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    const size_t block = 4u << 20;
    uint8_t *buffer = to >= 0 ? malloc(block) : NULL;
    while (buffer && (got = ps5_smb_read(from, buffer, block)) > 0)
    {
        int64_t written = 0;
        while (written < got)
        {
            const ssize_t n = write(to, buffer + written, (size_t)(got - written));
            if (n <= 0)
                break;
            written += n;
        }
        if (written != got)
            break;
        copied += got;
    }
    free(buffer);
    ps5_smb_close(from);
    const bool closed = to >= 0 && close(to) == 0;
    const bool whole = closed && copied == total && got == 0;
    SMB_LOG("[SMB] staged %lld of %lld bytes for a core that reads paths itself\n",
            (long long)copied, (long long)total);
    if (!whole && to >= 0)
        unlink(path);
    return whole;
}
