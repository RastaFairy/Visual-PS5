/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <ps5/kernel.h>

#include "gpl/hbldr.h"

#ifndef LAUNCHER_UI_PATH
#define LAUNCHER_UI_PATH "/data/ps5_homebrew_launcher_ui.elf"
#endif

#define REQUEST_PATH "/data/ps5_homebrew_launcher_request.txt"
#define LAST_RUN_LOG "/data/ps5_homebrew_last_run.txt"

int sceUserServiceInitialize(void *);
void sceUserServiceTerminate(void);
int sceKernelSendNotificationRequest(int, void *, size_t, int);

typedef struct notify_request {
    char useless1[45];
    char message[3075];
} notify_request_t;

static void
append_log(const char *msg) {
    FILE *fp;

    if(!msg) {
        return;
    }

    fp = fopen("/data/ps5_homebrew_launcher.log", "a");
    if(!fp) {
        return;
    }

    fprintf(fp, "[bootstrap] %s\n", msg);
    fclose(fp);
}

static void
notify_text(const char *msg) {
    if(!msg) {
        return;
    }

    append_log(msg);
}

static void
notify_path(const char *prefix, const char *path) {
    char buf[1200];

    snprintf(buf, sizeof(buf), "%s%s", prefix ? prefix : "", path ? path : "(null)");
    notify_text(buf);
}

static int
elevate_self(void) {
    static const uint8_t caps[16] = {
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    };

    if(kernel_set_ucred_authid(-1, 0x4801000000000013L)) {
        return -1;
    }
    if(kernel_set_ucred_uid(-1, 0)) {
        return -1;
    }
    if(kernel_set_ucred_caps(-1, caps)) {
        return -1;
    }

    return 0;
}

static int
file_exists(const char *path) {
    return access(path, F_OK) == 0;
}

static void
clear_request_file(void) {
    remove(REQUEST_PATH);
}

static int
read_request(char *target, size_t target_size, char *cwd, size_t cwd_size) {
    FILE *fp = fopen(REQUEST_PATH, "r");
    char line1[1024];
    char line2[1024];
    size_t len;

    if(!fp) {
        return -1;
    }

    if(!fgets(line1, sizeof(line1), fp)) {
        fclose(fp);
        return -1;
    }
    if(!fgets(line2, sizeof(line2), fp)) {
        line2[0] = 0;
    }
    fclose(fp);

    len = strlen(line1);
    if(len && line1[len - 1] == '\n') {
        line1[len - 1] = 0;
    }
    len = strlen(line2);
    if(len && line2[len - 1] == '\n') {
        line2[len - 1] = 0;
    }

    snprintf(target, target_size, "%s", line1);
    snprintf(cwd, cwd_size, "%s", line2[0] ? line2 : "/data");
    return target[0] ? 0 : -1;
}

static int
process_alive(pid_t pid) {
    if(pid <= 0) {
        return 0;
    }
    if(kill(pid, 0) == 0) {
        return 1;
    }
    return errno != ESRCH;
}

static int
open_last_run_log(void) {
    int fd = open(LAST_RUN_LOG, O_CREAT | O_TRUNC | O_WRONLY, 0644);
    static const char header[] = "=== ps5_homebrew_launcher run log ===\n";
    if(fd >= 0) {
        write(fd, header, sizeof(header) - 1);
    }
    return fd;
}

static void
write_last_run_line(int fd, const char *label, const char *value) {
    if(fd < 0 || !label) {
        return;
    }
    write(fd, label, strlen(label));
    if(value) {
        write(fd, value, strlen(value));
    }
    write(fd, "\n", 1);
}

int
main(int argc, char **argv) {
    char cwd_buf[1024];
    char target_buf[1024];
    char *launch_argv[] = {0, 0};
    char *envp[] = {0};
    const char *target = LAUNCHER_UI_PATH;
    const char *cwd = "/data";
    int supervise_ui = 0;
    pid_t launched_pid = -1;

    if(argc > 1 && argv[1] && argv[1][0]) {
        snprintf(target_buf, sizeof(target_buf), "%s", argv[1]);
        target = target_buf;
        launch_argv[0] = target_buf;

        if(argc > 2 && argv[2] && argv[2][0]) {
            snprintf(cwd_buf, sizeof(cwd_buf), "%s", argv[2]);
            cwd = cwd_buf;
        } else {
            char *slash;
            snprintf(cwd_buf, sizeof(cwd_buf), "%s", target_buf);
            slash = strrchr(cwd_buf, '/');
            if(slash) {
                *slash = 0;
                cwd = cwd_buf;
            }
        }
    } else {
        launch_argv[0] = (char *)LAUNCHER_UI_PATH;
        supervise_ui = 1;
    }

    notify_text("bootstrap start");

    if(sceUserServiceInitialize(0)) {
        notify_text("UserService init failed");
        perror("sceUserServiceInitialize");
        return EXIT_FAILURE;
    }

    if(elevate_self()) {
        notify_text("privilege elevation failed");
        sceUserServiceTerminate();
        return EXIT_FAILURE;
    }

    notify_text("launching bigapp UI");
    notify_path("ui target: ", target);
    notify_path("ui cwd: ", cwd);

    clear_request_file();

    launched_pid = hbldr_launch(cwd, target, -1, launch_argv, envp);
    if(launched_pid < 0) {
        notify_text("hbldr_launch failed");
        perror("hbldr_launch");
        sceUserServiceTerminate();
        return EXIT_FAILURE;
    }

    notify_text("UI launched");

    if(supervise_ui) {
        char requested_target[1024];
        char requested_cwd[1024];
        char *requested_argv[] = {0};

        notify_text("supervising UI");
        while(process_alive(launched_pid)) {
            if(file_exists(REQUEST_PATH) &&
               read_request(requested_target, sizeof(requested_target),
                            requested_cwd, sizeof(requested_cwd)) == 0) {
                int log_fd;
                notify_text("request received");
                clear_request_file();
                sleep(1);
                log_fd = open_last_run_log();
                write_last_run_line(log_fd, "target=", requested_target);
                write_last_run_line(log_fd, "cwd=", requested_cwd);
                hbldr_launch(requested_cwd, requested_target, log_fd, requested_argv, envp);
                if(log_fd >= 0) {
                    close(log_fd);
                }
                break;
            }
            usleep(100 * 1000);
        }
    }

    sceUserServiceTerminate();
    return EXIT_SUCCESS;
}
