/* PS5 RetroArch - a headless child for the local-process probe (frontends/child-probe).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Started by the probe through Sony's local-process service
 * (sceSystemServiceAddLocalProcess) with the libc-only preload mask, the route
 * ../PS5_Proton proved on firmware 10.01. It has no C runtime, heap or graphics:
 * only libkernel, as theirs. It reports over the socket the service hands it at
 * descriptor 3 what a child process gets (its native PID and the memory it sees),
 * then waits: a "done" message is answered and the helper idles until the probe
 * closes it through the service; without one it stays alive, which is how the
 * probe tests a child across its own LoadExec.
 */
#include <stddef.h>
#include <stdint.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

int sceKernelUsleep(unsigned microseconds);
int sceKernelAvailableFlexibleMemorySize(size_t *size);
size_t sceKernelGetDirectMemorySize(void);
int sceKernelAvailableDirectMemorySize(long start, long end, size_t alignment, long *found, size_t *size);

/* What the helper reports; frontends/child-probe/child_probe.c reads the same layout. */
struct report
{
    char magic[8];       /* "PS5CHILD" */
    int32_t pid;         /* its native PID */
    int32_t socket_type; /* descriptor 3's type */
    uint64_t flexible_free;
    uint64_t direct_total;
    uint64_t direct_largest_free;
};

static int ready(int fd, short events, int milliseconds)
{
    struct pollfd descriptor = {fd, events, 0};
    return poll(&descriptor, 1, milliseconds) == 1 && (descriptor.revents & events);
}

__attribute__((noreturn)) void _start(void *parameters, void *teardown)
{
    (void)parameters;
    (void)teardown;
    struct report report = {{'P', 'S', '5', 'C', 'H', 'I', 'L', 'D'}, 0, 0, 0, 0, 0};
    socklen_t length = sizeof(report.socket_type);
    if (getsockopt(3, SOL_SOCKET, SO_TYPE, &report.socket_type, &length) == 0 && report.socket_type == SOCK_SEQPACKET)
    {
        size_t flexible = 0, largest = 0;
        long found = 0;
        report.pid = getpid();
        if (sceKernelAvailableFlexibleMemorySize(&flexible) == 0)
            report.flexible_free = flexible;
        report.direct_total = sceKernelGetDirectMemorySize();
        if (sceKernelAvailableDirectMemorySize(0, (long)report.direct_total, 0, &found, &largest) == 0)
            report.direct_largest_free = largest;
        if (ready(3, POLLOUT, 5000) && send(3, &report, sizeof(report), MSG_NOSIGNAL) == sizeof(report))
        {
            char message = 0;
            /* "done": answer, then idle until closed. No message: stay alive, also
             * when the probe's end of the socket goes away (its LoadExec). */
            for (;;)
            {
                struct pollfd socket_state = {3, POLLIN, 0};
                if (poll(&socket_state, 1, 1000) != 1)
                    continue;
                if (!(socket_state.revents & POLLIN) || recv(3, &message, 1, 0) != 1)
                    break; /* hung up, or an error: nothing more will come */
                if (message == 'D')
                {
                    const char answer = 'K';
                    if (ready(3, POLLOUT, 5000))
                        (void)send(3, &answer, 1, MSG_NOSIGNAL);
                    break;
                }
            }
        }
    }
    for (;;)
        sceKernelUsleep(100000);
}
