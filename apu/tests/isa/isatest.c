/* RV32IM torture test: the same file is compiled for the host and for NOVA-1;
 * both must print identical output. Avoids C undefined behaviour (no division
 * by zero, no INT_MIN / -1), so any difference is an emulator bug. */
#include <stdint.h>
#ifndef INT32_MIN
#define INT32_MIN (-2147483647-1)
#endif

#ifdef NOVA
static void putc_(char c) { *(volatile uint32_t *)0x3000000C = (uint8_t)c; }
#else
#include <stdio.h>
static void putc_(char c) { putchar(c); }
#endif

static void hex(uint32_t v) {
    for (int i = 7; i >= 0; i--) putc_("0123456789abcdef"[(v >> (i * 4)) & 15]);
}

static volatile uint32_t vals[] = {
    0, 1, 2, 3, 7, 0x7fffffff, 0x80000000, 0x80000001, 0xffffffff, 0xfffffffe,
    0x12345678, 0xdeadbeef, 0x0000ffff, 0xffff0000, 31, 32, 33, 1000003, 0xaaaaaaaa, 0x55555555,
};
#define N (sizeof vals / sizeof vals[0])

static uint32_t acc = 0x811c9dc5;
static void mix(uint32_t v) { acc = (acc ^ v) * 16777619u; }

int main(void) {
    for (unsigned i = 0; i < N; i++) {
        for (unsigned j = 0; j < N; j++) {
            uint32_t a = vals[i], b = vals[j];
            int32_t sa = (int32_t)a, sb = (int32_t)b;
            mix(a + b); mix(a - b); mix(a & b); mix(a | b); mix(a ^ b);
            mix(a << (b & 31)); mix(a >> (b & 31)); mix((uint32_t)(sa >> (b & 31)));
            mix(sa < sb); mix(a < b);
            mix(a * b);
            mix((uint32_t)(((int64_t)sa * (int64_t)sb) >> 32));            /* mulh */
            mix((uint32_t)(((uint64_t)a * (uint64_t)b) >> 32));            /* mulhu */
            mix((uint32_t)(((int64_t)sa * (int64_t)(uint64_t)b) >> 32));  /* mulhsu */
            if (b != 0) {
                mix(a / b); mix(a % b);
                if (!(sa == INT32_MIN && sb == -1)) { mix((uint32_t)(sa / sb)); mix((uint32_t)(sa % sb)); }
            }
        }
        /* sign/zero extension of narrow loads */
        volatile uint8_t  *p8  = (volatile uint8_t *)&vals[i];
        volatile uint16_t *p16 = (volatile uint16_t *)&vals[i];
        mix((uint32_t)(int32_t)(int8_t)p8[1]); mix(p8[3]);
        mix((uint32_t)(int32_t)(int16_t)p16[1]); mix(p16[0]);
        hex(acc); putc_(i % 4 == 3 ? '\n' : ' ');
    }
    /* 64-bit division goes through libgcc, exercising long instruction sequences */
    uint64_t big = ((uint64_t)vals[11] << 32) | vals[10];
    mix((uint32_t)(big / 1000003u)); mix((uint32_t)(big % 97u));
    hex(acc); putc_('\n');
    return 0;
}
