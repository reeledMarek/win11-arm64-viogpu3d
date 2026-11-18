#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdint.h>

typedef int (__cdecl *PFN_SDL_Init)(uint32_t);
typedef void (__cdecl *PFN_SDL_Quit)(void);
typedef int (__cdecl *PFN_SDL_GL_LoadLibrary)(const char *);
typedef int (__cdecl *PFN_SDL_GL_SetAttribute)(int, int);
typedef void* (__cdecl *PFN_SDL_CreateWindow)(const char *, int, int, uint64_t);
typedef void* (__cdecl *PFN_SDL_GL_CreateContext)(void *);
typedef void (__cdecl *PFN_SDL_DestroyWindow)(void *);
typedef void* (__cdecl *PFN_SDL_GL_GetProcAddress)(const char *);

typedef void (__stdcall *PFN_glGenFramebuffers)(int, unsigned*);
typedef void (__stdcall *PFN_glBindFramebuffer)(unsigned, unsigned);
typedef void (__stdcall *PFN_glFramebufferTexture2D)(unsigned, unsigned, unsigned, unsigned, int);
typedef unsigned (__stdcall *PFN_glCheckFramebufferStatus)(unsigned);

int main(void) {
    FILE *f = fopen("test_depth32f.txt", "w");
    HMODULE sdl = LoadLibraryA("SDL3.dll");
    auto pInit = (PFN_SDL_Init)GetProcAddress(sdl, "SDL_Init");
    auto pQuit = (PFN_SDL_Quit)GetProcAddress(sdl, "SDL_Quit");
    auto pLoad = (PFN_SDL_GL_LoadLibrary)GetProcAddress(sdl, "SDL_GL_LoadLibrary");
    auto pSet = (PFN_SDL_GL_SetAttribute)GetProcAddress(sdl, "SDL_GL_SetAttribute");
    auto pWin = (PFN_SDL_CreateWindow)GetProcAddress(sdl, "SDL_CreateWindow");
    auto pCtx = (PFN_SDL_GL_CreateContext)GetProcAddress(sdl, "SDL_GL_CreateContext");
    auto pDWin = (PFN_SDL_DestroyWindow)GetProcAddress(sdl, "SDL_DestroyWindow");
    auto pGPA = (PFN_SDL_GL_GetProcAddress)GetProcAddress(sdl, "SDL_GL_GetProcAddress");

    pInit(0x20);
    pLoad(NULL);
    pSet(17, 3); pSet(18, 3); pSet(20, 1); pSet(19, 2);
    void *w = pWin("D32F", 320, 240, 2147614730ULL);
    void *c = w ? pCtx(w) : NULL;
    fprintf(f, "ctx=%p ver='%s'\n", c, c ? (const char*)glGetString(GL_VERSION) : "NULL");
    if (c) {
        unsigned tex = 0, ctex = 0, fbo = 0;
        glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, 0x8CAC /* GL_DEPTH_COMPONENT32F */, 256, 256, 0, GL_DEPTH_COMPONENT, GL_FLOAT, NULL);
        fprintf(f, "glTexImage2D(GL_DEPTH_COMPONENT32F) err=0x%x\n", glGetError());

        glGenTextures(1, &ctex);
        glBindTexture(GL_TEXTURE_2D, ctex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        fprintf(f, "glTexImage2D(GL_RGBA8) err=0x%x\n", glGetError());

        auto glGenFramebuffers = (PFN_glGenFramebuffers)pGPA("glGenFramebuffers");
        auto glBindFramebuffer = (PFN_glBindFramebuffer)pGPA("glBindFramebuffer");
        auto glFramebufferTexture2D = (PFN_glFramebufferTexture2D)pGPA("glFramebufferTexture2D");
        auto glCheckFramebufferStatus = (PFN_glCheckFramebufferStatus)pGPA("glCheckFramebufferStatus");

        glGenFramebuffers(1, &fbo);
        glBindFramebuffer(0x8D40, fbo);
        glFramebufferTexture2D(0x8D40, 0x8CE0, GL_TEXTURE_2D, ctex, 0);
        glFramebufferTexture2D(0x8D40, 0x8D00 /* GL_DEPTH_ATTACHMENT */, GL_TEXTURE_2D, tex, 0);
        unsigned st = glCheckFramebufferStatus(0x8D40);
        fprintf(f, "FBO status=0x%x (0x8CD5=COMPLETE) err=0x%x\n", st, glGetError());
    }
    if (w) pDWin(w);
    pQuit();
    fclose(f);
    return 0;
}
