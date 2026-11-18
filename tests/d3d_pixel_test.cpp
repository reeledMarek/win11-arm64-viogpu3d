#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3d9.h>
#include <stdio.h>

int main(void) {
    FILE *f = fopen("d3d_pixel_test.txt", "w");
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "YttriumD3DPix";
    RegisterClassA(&wc);

    // 1. D3D11 SwapChain test
    HWND w11 = CreateWindowExA(0, "YttriumD3DPix", "D3D11 Pixel Test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                               50, 50, 320, 240, NULL, NULL, wc.hInstance, NULL);
    DXGI_SWAP_CHAIN_DESC scd = {};
    scd.BufferCount = 1;
    scd.BufferDesc.Width = 300;
    scd.BufferDesc.Height = 200;
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.OutputWindow = w11;
    scd.SampleDesc.Count = 1;
    scd.Windowed = TRUE;
    ID3D11Device *dev11 = NULL;
    ID3D11DeviceContext *ctx11 = NULL;
    IDXGISwapChain *sc = NULL;
    D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_0;
    HRESULT hr11 = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                                 D3D11_SDK_VERSION, &scd, &sc, &dev11, &fl, &ctx11);
    fprintf(f, "D3D11CreateDeviceAndSwapChain hr=0x%08lx fl=0x%x\n", (unsigned long)hr11, (unsigned)fl);
    if (SUCCEEDED(hr11) && sc) {
        ID3D11Texture2D *bb = NULL;
        ID3D11RenderTargetView *rtv = NULL;
        sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb);
        if (bb) {
            dev11->CreateRenderTargetView(bb, NULL, &rtv);
            if (rtv) {
                float col[4] = {0.1f, 0.9f, 0.2f, 1.0f};
                ctx11->OMSetRenderTargets(1, &rtv, NULL);
                ctx11->ClearRenderTargetView(rtv, col);
                HRESULT hrp = sc->Present(0, 0);
                fprintf(f, "D3D11 Present hr=0x%08lx\n", (unsigned long)hrp);
                rtv->Release();
            }
            bb->Release();
        }
    }

    // 2. D3D9 / D3D9Ex test
    HWND w9 = CreateWindowExA(0, "YttriumD3DPix", "D3D9 Pixel Test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              420, 50, 320, 240, NULL, NULL, wc.hInstance, NULL);
    typedef HRESULT (WINAPI *PFN_Direct3DCreate9Ex)(UINT, IDirect3D9Ex**);
    HMODULE hm9 = LoadLibraryA("d3d9.dll");
    IDirect3D9 *d9 = NULL;
    IDirect3D9Ex *d9ex = NULL;
    IDirect3DDevice9 *dev9 = NULL;
    IDirect3DDevice9Ex *dev9ex = NULL;
    D3DPRESENT_PARAMETERS pp = {};
    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.hDeviceWindow = w9;
    pp.BackBufferFormat = D3DFMT_UNKNOWN;
    if (hm9) {
        auto pEx = (PFN_Direct3DCreate9Ex)GetProcAddress(hm9, "Direct3DCreate9Ex");
        HRESULT hrex = pEx ? pEx(D3D_SDK_VERSION, &d9ex) : E_FAIL;
        fprintf(f, "Direct3DCreate9Ex hr=0x%08lx d9ex=%p\n", (unsigned long)hrex, d9ex);
        if (SUCCEEDED(hrex) && d9ex) {
            D3DADAPTER_IDENTIFIER9 aid = {};
            d9ex->GetAdapterIdentifier(D3DADAPTER_DEFAULT, 0, &aid);
            fprintf(f, "D3D9 Adapter: %s | %s\n", aid.Driver, aid.Description);
            HRESULT hrd = d9ex->CreateDeviceEx(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, w9,
                D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, NULL, &dev9ex);
            fprintf(f, "D3D9Ex CreateDeviceEx(HWVP) hr=0x%08lx dev=%p\n", (unsigned long)hrd, dev9ex);
            if (SUCCEEDED(hrd) && dev9ex) {
                dev9ex->Clear(0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(230, 50, 50), 1.0f, 0);
                HRESULT hrp9 = dev9ex->Present(NULL, NULL, NULL, NULL);
                fprintf(f, "D3D9Ex Present hr=0x%08lx\n", (unsigned long)hrp9);
            }
        }
    }
    fflush(f);
    Sleep(2500);
    if (dev9ex) dev9ex->Release();
    if (d9ex) d9ex->Release();
    if (sc) sc->Release();
    if (ctx11) ctx11->Release();
    if (dev11) dev11->Release();
    DestroyWindow(w9);
    DestroyWindow(w11);
    fclose(f);
    return 0;
}
