/* Copyright (C) 2026 Mihawk-99 */
/* SPDX-License-Identifier: LGPL-2.1-or-later */
#include "packet_io.h"
#include "protocol.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
static unsigned descriptors(void)
{
    unsigned count=0;
    for(int fd=0;fd<256;++fd)if(fcntl(fd,F_GETFD)>=0)++count;
    return count;
}
int main(void)
{
    _Static_assert(sizeof(PwGpuMessage)==64,"broker wire format");
    assert(pw_gpu_contains(0x200000000,16384,0x200003ffc,4));
    assert(!pw_gpu_contains(0x200000000,16384,0x200003ffc,8));
    assert(!pw_gpu_contains(UINT64_MAX-7,16,UINT64_MAX-7,4));
    assert(!pw_gpu_contains(0,16384,0,0));
    int pair[2],pipefd[2],passed[2];unsigned count;
    assert(!ps5_gpu_packet_socketpair(pair,32768));assert(!pipe(pipefd));
    const unsigned baseline=descriptors();char out[16];
    assert(!ps5_gpu_packet_send(pair[0],"request",8,pipefd,2));
    assert(ps5_gpu_packet_recv(pair[1],out,sizeof(out),passed,&count)==8 && count==2 && !strcmp(out,"request"));
    assert(write(passed[1],"ok",3)==3 && read(passed[0],out,sizeof(out))==3 && !strcmp(out,"ok"));
    close(passed[0]);close(passed[1]);assert(descriptors()==baseline);
    assert(!ps5_gpu_packet_send(pair[0],"signal",7,NULL,0));
    assert(ps5_gpu_packet_recv(pair[1],out,sizeof(out),passed,&count)==7 && !count);
    assert(!ps5_gpu_packet_send(pair[0],"long",5,pipefd,2));
    assert(ps5_gpu_packet_recv(pair[1],out,1,passed,&count)==-1 && errno==EMSGSIZE && !count);
    assert(descriptors()==baseline);
    struct Packet { char bytes[32768]; } full={0},received={0};
    memset(full.bytes,'a',sizeof(full.bytes));
    assert(!ps5_gpu_packet_send(pair[0],&full,sizeof(full),pipefd,2));
    assert(ps5_gpu_packet_recv(pair[1],&received,sizeof(received),passed,&count)==sizeof(full) && count==2 && !memcmp(&full,&received,sizeof(full)));
    close(passed[0]);close(passed[1]);assert(descriptors()==baseline);
    /* The kernel installs received rights before reporting truncation. Close
     * all installed descriptors even when a peer sends too many of them. */
    int many[3]={pipefd[0],pipefd[1],pipefd[0]};
    union { struct cmsghdr align;char data[CMSG_SPACE(sizeof(many))]; } control={0};
    struct iovec vec={(void *)"fds",4};struct msghdr msg={0};
    msg.msg_iov=&vec;msg.msg_iovlen=1;msg.msg_control=control.data;msg.msg_controllen=sizeof(control.data);
    struct cmsghdr *c=CMSG_FIRSTHDR(&msg);c->cmsg_level=SOL_SOCKET;c->cmsg_type=SCM_RIGHTS;c->cmsg_len=CMSG_LEN(sizeof(many));
    memcpy(CMSG_DATA(c),many,sizeof(many));assert(sendmsg(pair[0],&msg,0)==4);
    assert(ps5_gpu_packet_recv(pair[1],out,sizeof(out),passed,&count)==-1 && errno==EMSGSIZE && !count);
    assert(descriptors()==baseline);
    /* Payload rendezvous transfers the existing packet endpoint through a
     * stream; bootstrap and input remain distinct packets afterward. */
    int stream[2],control_fd[2];unsigned char marker=0x50,got=0;
    assert(!socketpair(AF_UNIX,SOCK_STREAM,0,stream));
    assert(!ps5_gpu_packet_send(stream[0],&marker,1,&pair[1],1));
    assert(ps5_gpu_packet_recv(stream[1],&got,1,control_fd,&count)==1 && count==1 && got==marker);
    int kind=0;socklen_t kind_size=sizeof(kind);
    assert(!getsockopt(control_fd[0],SOL_SOCKET,SO_TYPE,&kind,&kind_size) && kind==SOCK_SEQPACKET);
    assert(!ps5_gpu_packet_send(pair[0],&full,sizeof(full),pipefd,2));
    assert(!ps5_gpu_packet_send(pair[0],"input",6,&pipefd[0],1));
    assert(ps5_gpu_packet_recv(control_fd[0],&received,sizeof(received),passed,&count)==sizeof(full) && count==2 && !memcmp(&full,&received,sizeof(full)));
    close(passed[0]);close(passed[1]);
    assert(ps5_gpu_packet_recv(control_fd[0],out,sizeof(out),passed,&count)==6 && count==1 && !strcmp(out,"input"));
    close(passed[0]);close(control_fd[0]);close(stream[0]);close(stream[1]);assert(descriptors()==baseline);
    close(pipefd[0]);close(pipefd[1]);close(pair[0]);close(pair[1]);
    puts("GPU packet transport: transferred descriptors, signals and truncation cleanup passed");
}
