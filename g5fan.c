#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <stdint.h>

#define IOCTL_MAGIC 0xEC
#define MAGIC_READ_CL  (IOCTL_MAGIC + 1)
#define MAGIC_WRITE_CL (IOCTL_MAGIC + 2)

#define R_HWCHECK_CL    _IOR(IOCTL_MAGIC, 0x05, int32_t*)
#define R_CL_HW_IF_STR  _IOR(MAGIC_READ_CL, 0x00, char*)
#define R_CL_FANINFO1   _IOR(MAGIC_READ_CL, 0x10, int32_t*)
#define R_CL_FANINFO2   _IOR(MAGIC_READ_CL, 0x11, int32_t*)
#define R_CL_FANINFO3   _IOR(MAGIC_READ_CL, 0x12, int32_t*)
#define W_CL_FANSPEED   _IOW(MAGIC_WRITE_CL, 0x10, int32_t*)
#define W_CL_FANAUTO    _IOW(MAGIC_WRITE_CL, 0x11, int32_t*)
#define W_CL_PERF_PROFILE _IOW(MAGIC_WRITE_CL, 0x15, int32_t*)

static volatile sig_atomic_t running = 1;
static void stop(int s) { (void)s; running = 0; }

static int fd;

static int32_t rd(unsigned long req) {
    int32_t v = -1;
    if (ioctl(fd, req, &v) < 0) { perror("ioctl read"); return -1; }
    return v;
}

static int set_speed_pct(int pct) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    int raw = (int)(pct * 255.0 / 100.0 + 0.5);
    int32_t arg = (raw & 0xff) | ((raw & 0xff) << 8) | ((raw & 0xff) << 16);
    if (ioctl(fd, W_CL_FANSPEED, &arg) < 0) { perror("set fanspeed"); return 1; }
    return 0;
}

static int set_auto(void) {
    int32_t arg = 0xF; /* all fans auto, like TCC SetFansAuto() */
    if (ioctl(fd, W_CL_FANAUTO, &arg) < 0) { perror("set auto"); return 1; }
    return 0;
}

static int set_perf(int prof) {
    int32_t arg = prof & 0xff;
    if (ioctl(fd, W_CL_PERF_PROFILE, &arg) < 0) { perror("set perf profile"); return 1; }
    return 0;
}

static int status(void) {
    int32_t hw = rd(R_HWCHECK_CL);
    char ifstr[64] = {0};
    ioctl(fd, R_CL_HW_IF_STR, ifstr);
    printf("interface : %s (hwcheck %d)\n", ifstr, hw);

    int32_t fi[3];
    fi[0] = rd(R_CL_FANINFO1);
    fi[1] = rd(R_CL_FANINFO2);
    fi[2] = rd(R_CL_FANINFO3);
    const char *names[3] = { "CPU", "GPU", "fan3" };
    for (int i = 0; i < 3; i++) {
        if (fi[i] < 0) continue;
        int duty_raw = fi[i] & 0xff;
        int temp     = (int8_t)((fi[i] >> 0x10) & 0xff);
        printf("%-4s: duty %3d/%d (%3d%%)  temp %2d C\n",
               names[i], duty_raw, 255, duty_raw * 100 / 255, temp);
    }
    return 0;
}

static int hold(int pct) {
    signal(SIGINT, stop);
    signal(SIGTERM, stop);
    while (running) {
        if (set_speed_pct(pct)) return 1;
        for (int i = 0; running && i < 20; i++) usleep(100000); /* write every ~2s */
    }
    set_auto();
    return 0;
}

int main(int argc, char **argv) {
    fd = open("/dev/tuxedo_io", O_RDWR);
    if (fd < 0) { perror("open /dev/tuxedo_io"); return 1; }

    if (argc >= 2 && strcmp(argv[1], "status") == 0) {
        status();
    } else if (argc >= 2 && strcmp(argv[1], "on") == 0) {
        int pct = (argc >= 3) ? atoi(argv[2]) : 100;
        if (set_speed_pct(pct)) { close(fd); return 1; }
        usleep(200000);
        printf("fans set to %d%%\n", pct);
        status();
    } else if (argc >= 2 && strcmp(argv[1], "hold") == 0) {
        int pct = (argc >= 3) ? atoi(argv[2]) : 100;
        return hold(pct);
    } else if (argc >= 2 && strcmp(argv[1], "perf") == 0) {
        int prof = (argc >= 3) ? atoi(argv[2]) : 2;
        if (prof < 0 || prof > 3) prof = 2;
        if (set_perf(prof)) { close(fd); return 1; }
        printf("performance profile set to %d\n", prof);
    } else if (argc >= 2 && (strcmp(argv[1], "off") == 0 || strcmp(argv[1], "auto") == 0)) {
        if (set_auto()) { close(fd); return 1; }
        printf("fans back to EC auto control\n");
        status();
    } else {
        fprintf(stderr, "usage: g5fan status | on [0-100] | hold [0-100] | perf [0-3] | off\n");
        close(fd);
        return 1;
    }

    close(fd);
    return 0;
}
