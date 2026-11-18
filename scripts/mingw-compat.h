#pragma once
#ifdef __cplusplus
#include <wchar.h>

static inline const wchar_t *viogpu_compat_widen(const char *s)
{
    static thread_local wchar_t ring[8][256];
    static thread_local unsigned next;
    wchar_t *out = ring[next++ % 8];
    size_t i = 0;
    for (; s[i] && i < 255; i++)
        out[i] = (wchar_t)(unsigned char)s[i];
    out[i] = 0;
    return out;
}
#define __FUNCTIONW__ viogpu_compat_widen(__FUNCTION__)
#endif

#ifndef __in
#define __in
#endif
#ifndef __in_ecount
#define __in_ecount(x)
#endif
