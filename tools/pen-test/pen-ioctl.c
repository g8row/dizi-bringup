/* Test-only: xiaomi_touch SET_CUR_VALUE ioctl without libc.
 * Usage: pen-ioctl <mode> <value>   (same buffer layout as xiaomi-pen.cpp) */
typedef unsigned long u64;
static long sys(long n, long a, long b, long c, long d) {
	register long x8 asm("x8") = n, x0 asm("x0") = a, x1 asm("x1") = b,
		x2 asm("x2") = c, x3 asm("x3") = d;
	asm volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}
enum { SYS_openat = 56, SYS_close = 57, SYS_write = 64, SYS_exit = 93, SYS_ioctl = 29 };
static int atoi_(const char *s) { int neg = 0, v = 0; if (*s == '-') { neg = 1; s++; }
	while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0'); return neg ? -v : v; }
static void say(const char *s) { long n = 0; while (s[n]) n++; sys(SYS_write, 1, (long)s, n, 0); }
static int buf[256];
void _start_c(long *sp) {
	int argc = (int)sp[0]; char **argv = (char **)(sp + 1);
	if (argc != 3) { say("usage: pen-ioctl <mode> <value>\n"); sys(SYS_exit, 2, 0, 0, 0); }
	long fd = sys(SYS_openat, -100, (long)"/dev/xiaomi-touch", 02 /*O_RDWR*/, 0);
	if (fd < 0) { say("open failed\n"); sys(SYS_exit, 1, 0, 0, 0); }
	buf[0] = 0; buf[1] = atoi_(argv[1]); buf[2] = atoi_(argv[2]);
	long r = sys(SYS_ioctl, fd, 0x7400 /*_IO('t',0)*/, (long)buf, 0);
	sys(SYS_close, fd, 0, 0, 0);
	say(r < 0 ? "ioctl failed\n" : "ok\n");
	sys(SYS_exit, r < 0, 0, 0, 0);
}
asm(".globl _start\n_start:\n mov x0, sp\n bl _start_c\n");
