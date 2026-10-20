/* src/ps5_smb_vfs.c against the Samba server of tests/test_smb_vfs.py, the saved server in
 * PS5_SMB_CONFIG: argv[1] the server (host:port), argv[2] a folder for the staged copy,
 * argv[3] a file the test writes once the first read is done (the test then restarts the
 * server) and argv[4] the file the test writes when the server is back. */
#include "../src/ps5_smb_vfs.h"

#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libretro.h>

static unsigned char expected(uint64_t at)
{
    return (unsigned char)((at * 2654435761u) >> 13);
}

static void url(char *out, size_t size, const char *server, const char *path)
{
    snprintf(out, size, "smb://%s/%s", server, path);
}

int main(int argc, char **argv)
{
    assert(argc == 5);
    /* Linux has no SO_NOSIGPIPE (src/ps5_smb.c sets it on the console). */
    signal(SIGPIPE, SIG_IGN);
    const char *server = argv[1];
    char at[512];
    int64_t size = -1;

    /* the share's top and a folder: folders, by name, without . and .. */
    url(at, sizeof at, server, "locked");
    assert(ps5_smb_stat(at, NULL) == (RETRO_VFS_STAT_IS_VALID | RETRO_VFS_STAT_IS_DIRECTORY));
    url(at, sizeof at, server, "locked/Games/");
    void *dir = ps5_smb_opendir(at);
    assert(dir);
    int files = 0, folders = 0;
    while (ps5_smb_readdir(dir))
    {
        const char *name = ps5_smb_dirent_name(dir);
        assert(strcmp(name, ".") && strcmp(name, ".."));
        if (ps5_smb_dirent_is_dir(dir))
            folders += !strcmp(name, "Homebrew");
        else
            files += !strcmp(name, "demo game.bin");
    }
    ps5_smb_closedir(dir);
    assert(files == 1 && folders == 1);

    /* a file: its size, reads past libsmb2's per-call cap, seeks */
    url(at, sizeof at, server, "locked/Games/demo game.bin");
    assert(ps5_smb_stat(at, &size) == RETRO_VFS_STAT_IS_VALID && size == 24 << 20);
    assert(!ps5_smb_open(at, RETRO_VFS_FILE_ACCESS_WRITE, &size)); /* read-only */
    void *file = ps5_smb_open(at, RETRO_VFS_FILE_ACCESS_READ, &size);
    assert(file && size == 24 << 20);
    unsigned char *buffer = malloc(16 << 20);
    assert(ps5_smb_read(file, buffer, 16 << 20) == 16 << 20 && ps5_smb_tell(file) == 16 << 20);
    for (uint64_t i = 0; i < 16 << 20; i += 4093)
        assert(buffer[i] == expected(i));
    assert(ps5_smb_seek(file, -100, SEEK_END) == 0 && ps5_smb_tell(file) == (24 << 20) - 100);
    assert(ps5_smb_read(file, buffer, 1000) == 100 && buffer[99] == expected((24 << 20) - 1));
    assert(ps5_smb_read(file, buffer, 1000) == 0);
    assert(ps5_smb_seek(file, 5 << 20, SEEK_SET) == 0);

    /* the server restarts under an open file: the next read connects again */
    FILE *mark = fopen(argv[3], "w");
    assert(mark && fclose(mark) == 0);
    while (access(argv[4], F_OK) != 0)
        usleep(20000);
    assert(ps5_smb_read(file, buffer, 3) == 3 && buffer[2] == expected((5 << 20) + 2));
    assert(ps5_smb_tell(file) == (5 << 20) + 3);
    ps5_smb_close(file);

    /* the copy a core that opens paths itself gets */
    char staged[512];
    assert(ps5_smb_stage(at, argv[2], staged, sizeof staged));
    assert(!strcmp(staged + strlen(argv[2]), "/demo game.bin"));
    FILE *copy = fopen(staged, "rb");
    assert(copy && fseek(copy, 0, SEEK_END) == 0 && ftell(copy) == 24 << 20);
    assert(fseek(copy, (20 << 20) + 7, SEEK_SET) == 0 && fgetc(copy) == expected((20 << 20) + 7));
    fclose(copy);
    url(at, sizeof at, server, "locked/Games/missing.bin");
    assert(!ps5_smb_stat(at, NULL) && !ps5_smb_stage(at, argv[2], staged, sizeof staged));

    /* never another server, never outside a share */
    assert(!ps5_smb_stat("smb://192.0.2.1/locked", NULL));
    assert(!ps5_smb_opendir("smb://192.0.2.1/locked/Games"));
    snprintf(at, sizeof at, "smb://%s", server);
    assert(!ps5_smb_stat(at, NULL));
    free(buffer);
    puts("smb vfs: listing, stat, 24 MiB read and seeks, read-only, reconnect after a server "
         "restart, staged copy, saved server only PASS");
    return 0;
}
