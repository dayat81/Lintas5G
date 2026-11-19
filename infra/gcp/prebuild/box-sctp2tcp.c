// sctp2tcp: LD_PRELOAD shim for TEST ONLY. Maps SCTP sockets (one-to-one/SEQPACKET) to TCP with a 4-byte length
// framing so srsRAN gNB <-> Open5GS AMF (NGAP) can run on a host kernel without SCTP (e.g. the Grok box).
// Both peers must load it. Not for lab VMs (they have kernel SCTP).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/sctp.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>
#define MAXFD 65536
static unsigned char mark[MAXFD];  // 1 = sctp-over-tcp fd, 2 = accepted fd with pending COMM_UP notification
#define REAL(f) static __typeof__(f) *real_##f; if (!real_##f) real_##f = dlsym(RTLD_NEXT, #f)
static int is_s(int fd) { return fd >= 0 && fd < MAXFD && mark[fd]; }
int socket(int d, int t, int p) {
  REAL(socket);
  if (p != IPPROTO_SCTP) return real_socket(d, t, p);
  int fl = t & (SOCK_NONBLOCK | SOCK_CLOEXEC);
  int fd = real_socket(d, SOCK_STREAM | fl, IPPROTO_TCP);
  if (fd >= 0 && fd < MAXFD) { mark[fd] = 1; int one = 1; setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one); }
  return fd;
}
int setsockopt(int fd, int lvl, int opt, const void *v, socklen_t l) {
  REAL(setsockopt);
  if (lvl == IPPROTO_SCTP) return 0;
  return real_setsockopt(fd, lvl, opt, v, l);
}
int getsockopt(int fd, int lvl, int opt, void *v, socklen_t *l) {
  REAL(getsockopt);
  if (lvl == IPPROTO_SCTP) {
    if (v && l) memset(v, 0, *l);
    if (opt == SCTP_EVENTS && l) *l = sizeof(struct sctp_event_subscribe);
    return 0;
  }
  return real_getsockopt(fd, lvl, opt, v, l);
}
static void mark_new(int lfd, int nfd) { if (is_s(lfd) && nfd >= 0 && nfd < MAXFD) { mark[nfd] = 2; int one = 1; setsockopt(nfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one); } }
int accept(int fd, struct sockaddr *a, socklen_t *l) { REAL(accept); int n = real_accept(fd, a, l); mark_new(fd, n); return n; }
int accept4(int fd, struct sockaddr *a, socklen_t *l, int f) { REAL(accept4); int n = real_accept4(fd, a, l, f); mark_new(fd, n); return n; }
int close(int fd) { REAL(close); if (fd >= 0 && fd < MAXFD) mark[fd] = 0; return real_close(fd); }
int sctp_bindx(int fd, struct sockaddr *a, int n, int flags) {
  (void)n; (void)flags;
  socklen_t l = a->sa_family == AF_INET6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
  int one = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  return bind(fd, a, l);
}
int sctp_connectx(int fd, struct sockaddr *a, int n, sctp_assoc_t *id) {
  (void)n; if (id) *id = 1;
  socklen_t l = a->sa_family == AF_INET6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
  return connect(fd, a, l);
}
static int xfer(int fd, void *b, size_t n, int wr) {  // full read/write, waits on EAGAIN (loopback, small msgs)
  size_t o = 0;
  while (o < n) {
    ssize_t r = wr ? send(fd, (char *)b + o, n - o, MSG_NOSIGNAL) : recv(fd, (char *)b + o, n - o, 0);
    if (r > 0) { o += r; continue; }
    if (r == 0) return 0;
    if (errno == EINTR) continue;
    if (errno == EAGAIN || errno == EWOULDBLOCK) { struct pollfd p = {fd, wr ? POLLOUT : POLLIN, 0}; poll(&p, 1, 1000); continue; }
    return -1;
  }
  return 1;
}
int sctp_sendmsg(int fd, const void *msg, size_t len, struct sockaddr *to, socklen_t tl, uint32_t ppid, uint32_t flags,
                 uint16_t stream, uint32_t ttl, uint32_t ctx) {
  (void)to; (void)tl; (void)ppid; (void)stream; (void)ttl; (void)ctx;
  if (flags & SCTP_EOF) { shutdown(fd, SHUT_WR); return 0; }
  uint32_t h = htonl((uint32_t)len);
  if (xfer(fd, &h, 4, 1) <= 0 || xfer(fd, (void *)msg, len, 1) <= 0) { if (!errno) errno = EPIPE; return -1; }
  return (int)len;
}
static int notif(int fd, void *msg, size_t len, struct sockaddr *from, socklen_t *fl, int *mf, uint16_t state) {
  struct sctp_assoc_change n; memset(&n, 0, sizeof n);
  n.sac_type = SCTP_ASSOC_CHANGE; n.sac_length = sizeof n; n.sac_state = state;
  n.sac_outbound_streams = 30; n.sac_inbound_streams = 30; n.sac_assoc_id = 1;
  if (len < sizeof n) { errno = EMSGSIZE; return -1; }
  memcpy(msg, &n, sizeof n);
  if (from && fl) getpeername(fd, from, fl);
  if (mf) *mf = MSG_NOTIFICATION | MSG_EOR;
  return sizeof n;
}
int sctp_recvmsg(int fd, void *msg, size_t len, struct sockaddr *from, socklen_t *fl, struct sctp_sndrcvinfo *si, int *mf) {
  if (si) memset(si, 0, sizeof *si);
  if (fd >= 0 && fd < MAXFD && mark[fd] == 2) { mark[fd] = 1; return notif(fd, msg, len, from, fl, mf, SCTP_COMM_UP); }
  uint32_t h; ssize_t r = recv(fd, &h, 4, MSG_PEEK);
  if (r < 0) return -1;
  if (r == 0) return notif(fd, msg, len, from, fl, mf, SCTP_SHUTDOWN_COMP);  // peer closed
  if (xfer(fd, &h, 4, 0) <= 0) return -1;
  uint32_t n = ntohl(h);
  if (n > len) { errno = EMSGSIZE; return -1; }
  int k = xfer(fd, msg, n, 0);
  if (k <= 0) { if (k == 0) return notif(fd, msg, len, from, fl, mf, SCTP_SHUTDOWN_COMP); return -1; }
  if (from && fl) getpeername(fd, from, fl);
  if (si) { memset(si, 0, sizeof *si); si->sinfo_ppid = htonl(60); si->sinfo_assoc_id = 1; }
  if (mf) *mf = MSG_EOR;
  return (int)n;
}
