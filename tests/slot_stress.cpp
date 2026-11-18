#include <windows.h>
#include <d3d11.h>
#include <GL/gl.h>
#include <stdio.h>

int main(void) {
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "YttriumStress";
    RegisterClassA(&wc);

    FILE *log = fopen("slot_stress.log", "w");
    const int N = 50;
    HWND hwnds[50];
    HDC hdcs[50];
    HGLRC rcs[50];
    for (int i = 0; i < N; i++) {
        hwnds[i] = CreateWindowExA(0, "YttriumStress", "Stress", WS_OVERLAPPEDWINDOW, 0, 0, 128, 128, NULL, NULL, wc.hInstance, NULL);
        hdcs[i] = GetDC(hwnds[i]);
        PIXELFORMATDESCRIPTOR pfd = {0};
        pfd.nSize = sizeof(pfd);
        pfd.nVersion = 1;
        pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
        pfd.iPixelType = PFD_TYPE_RGBA;
        pfd.cColorBits = 32;
        pfd.cDepthBits = 24;
        pfd.iLayerType = PFD_MAIN_PLANE;
        int pf = ChoosePixelFormat(hdcs[i], &pfd);
        SetPixelFormat(hdcs[i], pf, &pfd);
        rcs[i] = wglCreateContext(hdcs[i]);
        BOOL ok = wglMakeCurrent(hdcs[i], rcs[i]);
        if (ok) {
            glClearColor(0.2f, 0.5f, 0.3f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            SwapBuffers(hdcs[i]);
        }
        fprintf(log, "GL[%d]: rc=%p ok=%d err=%lu\n", i, rcs[i], ok, GetLastError());
        fflush(log);
    }

    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_0;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    fprintf(log, "D3D11CreateDevice hr=0x%lx fl=0x%x\n", (unsigned long)hr, (unsigned)fl);
    fflush(log);
    if (SUCCEEDED(hr) && dev) {
        for (int i = 0; i < 600; i++) {
            D3D11_TEXTURE2D_DESC td = {0};
            td.Width = 256; td.Height = 256; td.MipLevels = 1; td.ArraySize = 1;
            td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
            td.SampleDesc.Count = 1;
            td.Usage = D3D11_USAGE_STAGING;
            td.CPUAccessFlags = D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE;
            ID3D11Texture2D *tex = NULL;
            HRESULT thr = dev->CreateTexture2D(&td, NULL, &tex);
            D3D11_MAPPED_SUBRESOURCE mapped = {0};
            HRESULT mhr = E_FAIL;
            if (SUCCEEDED(thr) && tex) {
                mhr = ctx->Map(tex, 0, D3D11_MAP_READ_WRITE, 0, &mapped);
            }
            fprintf(log, "TEX[%d]: create=0x%lx map=0x%lx\n", i, (unsigned long)thr, (unsigned long)mhr);
            fflush(log);
        }
    }

    fprintf(log, "STRESS_DONE\n");
    fclose(log);
    for (int i = 0; i < N; i++) {
        wglMakeCurrent(NULL, NULL);
        wglDeleteContext(rcs[i]);
        ReleaseDC(hwnds[i], hdcs[i]);
        DestroyWindow(hwnds[i]);
    }
    return 0;
}
