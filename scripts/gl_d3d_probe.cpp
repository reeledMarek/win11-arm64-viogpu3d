#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <GL/gl.h>
#include <stdio.h>

static void print_gl_info(void) {
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "YttriumGLProbe";
    RegisterClassA(&wc);

    HWND hwnd = CreateWindowExA(0, "YttriumGLProbe", "GL Probe", WS_OVERLAPPEDWINDOW,
                                0, 0, 256, 256, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) {
        printf("OpenGL: CreateWindowExA failed (%lu)\n", GetLastError());
        return;
    }
    HDC hdc = GetDC(hwnd);
    PIXELFORMATDESCRIPTOR pfd = {0};
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.iLayerType = PFD_MAIN_PLANE;

    int pf = ChoosePixelFormat(hdc, &pfd);
    if (!pf || !SetPixelFormat(hdc, pf, &pfd)) {
        printf("OpenGL: SetPixelFormat failed (%lu)\n", GetLastError());
        ReleaseDC(hwnd, hdc);
        DestroyWindow(hwnd);
        return;
    }
    HGLRC rc = wglCreateContext(hdc);
    if (!rc || !wglMakeCurrent(hdc, rc)) {
        printf("OpenGL: wglCreateContext/MakeCurrent failed (%lu)\n", GetLastError());
        ReleaseDC(hwnd, hdc);
        DestroyWindow(hwnd);
        return;
    }

    printf("GL_VENDOR   : %s\n", (const char *)glGetString(GL_VENDOR));
    printf("GL_RENDERER : %s\n", (const char *)glGetString(GL_RENDERER));
    printf("GL_VERSION  : %s\n", (const char *)glGetString(GL_VERSION));

    glClearColor(0.1f, 0.4f, 0.8f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    SwapBuffers(hdc);
    printf("OpenGL draw : OK (err=0x%x)\n", (unsigned)glGetError());

    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(rc);
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);
}

static void print_d3d11_info(void) {
    IDXGIFactory1 *factory = NULL;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void **)&factory);
    if (FAILED(hr) || !factory) {
        printf("DXGI: CreateDXGIFactory1 failed (0x%08lx)\n", (unsigned long)hr);
        return;
    }
    IDXGIAdapter1 *adapter = NULL;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 desc;
        adapter->GetDesc1(&desc);
        wprintf(L"DXGI[%u]     : %ls (Vendor=0x%04x Device=0x%04x DedicatedVRAM=%lluMB Flags=0x%x)\n",
                i, desc.Description, desc.VendorId, desc.DeviceId,
                (unsigned long long)(desc.DedicatedVideoMemory / (1024 * 1024)), desc.Flags);
        adapter->Release();
    }
    factory->Release();

    D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_0;
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                           D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (SUCCEEDED(hr) && dev) {
        printf("D3D11 HW    : OK (feature level 0x%x)\n", (unsigned)fl);
        if (ctx) ctx->Release();
        dev->Release();
    } else {
        printf("D3D11 HW    : FAILED (0x%08lx)\n", (unsigned long)hr);
    }
}

int main(void) {
    printf("=== Yttrium ARM64/x86 3D Probe ===\n");
    print_d3d11_info();
    print_gl_info();
    return 0;
}
