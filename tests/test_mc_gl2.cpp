#include <windows.h>
#include <stdio.h>
#include <stdint.h>

typedef int (__cdecl *PFN_SDL_Init)(uint32_t flags);
typedef void (__cdecl *PFN_SDL_Quit)(void);
typedef const char* (__cdecl *PFN_SDL_GetError)(void);
typedef int (__cdecl *PFN_SDL_GL_LoadLibrary)(const char *path);
typedef int (__cdecl *PFN_SDL_GL_SetAttribute)(int attr, int val);
typedef void (__cdecl *PFN_SDL_GL_ResetAttributes)(void);
typedef int (__cdecl *PFN_SDL_GL_GetAttribute)(int attr, int *val);
typedef void* (__cdecl *PFN_SDL_CreateWindow)(const char *title, int w, int h, uint64_t flags);
typedef void* (__cdecl *PFN_SDL_GL_CreateContext)(void *win);
typedef void (__cdecl *PFN_SDL_DestroyWindow)(void *win);
typedef void (__cdecl *PFN_SDL_GL_DestroyContext)(void *ctx);
typedef const unsigned char* (__stdcall *PFN_glGetString)(unsigned name);

static void try_case(FILE *f, const char *name,
                     PFN_SDL_GL_ResetAttributes pReset,
                     PFN_SDL_GL_SetAttribute pSet,
                     PFN_SDL_GL_GetAttribute pGet,
                     PFN_SDL_CreateWindow pWin,
                     PFN_SDL_GL_CreateContext pCtx,
                     PFN_SDL_DestroyWindow pDWin,
                     PFN_SDL_GL_DestroyContext pDCtx,
                     PFN_SDL_GetError pErr,
                     int maj, int min, int prof, int flags, int srgb) {
    pReset();
    if (maj) { pSet(17, maj); pSet(18, min); }
    if (prof) pSet(20, prof);
    if (flags) pSet(19, flags);
    if (srgb >= 0) pSet(22, srgb);
    void *w = pWin(name, 320, 480, 2147614730ULL);
    void *c = w ? pCtx(w) : NULL;
    fprintf(f, "[%s] win=%p ctx=%p err='%s'\n", name, w, c, c ? "OK" : pErr());
    if (c) {
        int gmaj=0, gmin=0, gprof=0;
        pGet(17, &gmaj); pGet(18, &gmin); pGet(20, &gprof);
        HMODULE ogl = GetModuleHandleA("opengl32.dll");
        auto pGetStr = (PFN_glGetString)GetProcAddress(ogl, "glGetString");
        fprintf(f, "   attr=(%d.%d prof=%d) GL_VERSION='%s' RENDERER='%s'\n",
                gmaj, gmin, gprof,
                pGetStr ? (const char*)pGetStr(0x1F02) : "?",
                pGetStr ? (const char*)pGetStr(0x1F01) : "?");
        pDCtx(c);
    }
    if (w) pDWin(w);
    fflush(f);
}

int main(void) {
    FILE *f = fopen("test_mc_gl2.txt", "w");
    HMODULE sdl = LoadLibraryA("SDL3.dll");
    auto pInit = (PFN_SDL_Init)GetProcAddress(sdl, "SDL_Init");
    auto pQuit = (PFN_SDL_Quit)GetProcAddress(sdl, "SDL_Quit");
    auto pErr = (PFN_SDL_GetError)GetProcAddress(sdl, "SDL_GetError");
    auto pLoadGL = (PFN_SDL_GL_LoadLibrary)GetProcAddress(sdl, "SDL_GL_LoadLibrary");
    auto pSet = (PFN_SDL_GL_SetAttribute)GetProcAddress(sdl, "SDL_GL_SetAttribute");
    auto pReset = (PFN_SDL_GL_ResetAttributes)GetProcAddress(sdl, "SDL_GL_ResetAttributes");
    auto pGet = (PFN_SDL_GL_GetAttribute)GetProcAddress(sdl, "SDL_GL_GetAttribute");
    auto pWin = (PFN_SDL_CreateWindow)GetProcAddress(sdl, "SDL_CreateWindow");
    auto pCtx = (PFN_SDL_GL_CreateContext)GetProcAddress(sdl, "SDL_GL_CreateContext");
    auto pDWin = (PFN_SDL_DestroyWindow)GetProcAddress(sdl, "SDL_DestroyWindow");
    auto pDCtx = (PFN_SDL_GL_DestroyContext)GetProcAddress(sdl, "SDL_GL_DestroyContext");

    pInit(0x20);
    pLoadGL(NULL);
    try_case(f, "default",     pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 0, 0, 0, 0, -1);
    try_case(f, "2.1_compat",  pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 2, 1, 2, 0, -1);
    try_case(f, "3.3_compat",  pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 3, 3, 2, 0, -1);
    try_case(f, "3.3_core",    pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 3, 3, 1, 0, -1);
    try_case(f, "3.3_core_fc", pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 3, 3, 1, 2, -1);
    try_case(f, "4.6_core",    pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 4, 6, 1, 0, -1);
    try_case(f, "attr22_only", pReset, pSet, pGet, pWin, pCtx, pDWin, pDCtx, pErr, 0, 0, 0, 0, 1);

    /* Direct WGL check on GetModuleHandle("viogpu_wgl.dll") + registry check */
    HMODULE wglmod = GetModuleHandleA("viogpu_wgl.dll");
    fprintf(f, "viogpu_wgl.dll=%p DrvCreateContextAttribs=%p\n",
            wglmod, wglmod ? GetProcAddress(wglmod, "DrvCreateContextAttribs") : NULL);
    pQuit();
    fclose(f);
    return 0;
}
