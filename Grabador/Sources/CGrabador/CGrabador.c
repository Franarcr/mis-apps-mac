#include "CGrabador.h"

#include <errno.h>
#include <string.h>
#include <sys/socket.h>

mode_t archive_entry_filetype(struct archive_entry *);

int cg_entry_is_file(struct archive_entry *entry) { return archive_entry_filetype(entry) == 0100000; }

int cg_receive_fd(int socket) {
    char byte;
    struct iovec iov = { &byte, 1 };
    union {
        struct cmsghdr header;
        char space[CMSG_SPACE(sizeof(int))];
    } control;
    struct msghdr message;
    memset(&message, 0, sizeof(message));
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control.space;
    message.msg_controllen = sizeof(control.space);

    ssize_t received;
    do {
        received = recvmsg(socket, &message, 0);
    } while (received < 0 && errno == EINTR);
    if (received <= 0) return -1;

    for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&message); cmsg != NULL; cmsg = CMSG_NXTHDR(&message, cmsg)) {
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS) {
            int fd;
            memcpy(&fd, CMSG_DATA(cmsg), sizeof(int));
            return fd;
        }
    }
    return -1;
}
