/*
 * z/OS stub: __strerror_r_ascii
 *
 * OpenSSL 4.0.0 built with zopen toolchain calls __strerror_r_ascii()
 * to get an ASCII error string. On z/OS, strerror() returns EBCDIC;
 * this function converts it to ASCII via iconv or __e2a_s().
 *
 * Signature (inferred from usage in openssl):
 *   char *__strerror_r_ascii(int errnum, char *buf, size_t buflen);
 *
 * Returns buf filled with ASCII error string, or NULL on failure.
 */
#include <string.h>
#include <errno.h>

/* IBM z/OS built-in EBCDIC-to-ASCII converter */
extern int __e2a_l(char *buffer, size_t buflen);

char *__strerror_r_ascii(int errnum, char *buf, size_t buflen) {
    char *msg = strerror(errnum);  /* EBCDIC string on z/OS */
    if (!msg || buflen == 0) return NULL;
    strncpy(buf, msg, buflen - 1);
    buf[buflen - 1] = '\0';
    /* Convert EBCDIC buf to ASCII in-place */
    __e2a_l(buf, strlen(buf));
    return buf;
}
