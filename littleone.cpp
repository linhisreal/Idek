// YOUR INCLUDES...
#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <d3d11.h>
#include <tchar.h>

#include <Windows.h>
#include <filesystem>
#include <shellapi.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <shlobj.h>
#include <zip.h>
#include <wininet.h>
#pragma comment(lib, "zip.lib")
#pragma comment(lib, "wininet.lib")

// GLOBALS...
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

// DirectX globals...
static ID3D11Device* g_pd3dDevice = nullptr;
static ID3D11DeviceContext* g_pd3dDeviceContext = nullptr;
static IDXGISwapChain* g_pSwapChain = nullptr;
static bool g_SwapChainOccluded = false;
static UINT g_ResizeWidth = 0, g_ResizeHeight = 0;
static ID3D11RenderTargetView* g_mainRenderTargetView = nullptr;

// function declarations
bool CreateDeviceD3D(HWND hWnd);
void CleanupDeviceD3D();
void CreateRenderTarget();
void CleanupRenderTarget();
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

bool CheckForKeyAndLaunchSynapse();
std::string CreateHiddenFolder();
bool DownloadFile(const std::string& url, const std::string& outputPath);
bool ExtractZipFile(const std::string& zipPath, const std::string& extractPath);
bool SaveKeyToFile(const std::string& key);
bool validateKey(const std::string& token);
void OpenBrowser(const std::wstring& url);

// easy url opening
void OpenBrowser(const std::wstring& url) {
    ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

using json = nlohmann::json;

// write callback for curl
size_t WriteCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    ((std::string*)userp)->append((char*)contents, size * nmemb);
    return size * nmemb;
}

// download file
bool DownloadFile(const std::string& url, const std::string& outputPath) {
    CURL* curl;
    FILE* fp;
    CURLcode res;

    curl = curl_easy_init();
    if (!curl) {
        return false;
    }

    errno_t err = fopen_s(&fp, outputPath.c_str(), "wb");
    if (err != 0 || !fp) {
        curl_easy_cleanup(curl);
        return false;
    }

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, NULL);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);

    res = curl_easy_perform(curl);

    curl_easy_cleanup(curl);
    fclose(fp);

    // If curl failed or file is 0 bytes, return false
    if (res != CURLE_OK) return false;
    if (std::filesystem::file_size(outputPath) == 0) return false;

    return true;
}

// unzip file
bool ExtractZipFile(const std::string& zipPath, const std::string& extractPath) {
    int err = 0;
    zip* z = zip_open(zipPath.c_str(), 0, &err);

    if (!z) {
        return false;
    }

    std::filesystem::create_directories(extractPath);

    zip_int64_t num_entries = zip_get_num_entries(z, 0);

    for (zip_int64_t i = 0; i < num_entries; i++) {
        const char* name = zip_get_name(z, i, 0);

        std::string full_path = extractPath + "\\" + name;
        std::string dir_path = full_path.substr(0, full_path.find_last_of("\\/"));
        std::filesystem::create_directories(dir_path);

        if (name[strlen(name) - 1] != '/') {
            zip_file* zf = zip_fopen_index(z, i, 0);
            if (zf) {
                FILE* fp;
                errno_t err = fopen_s(&fp, full_path.c_str(), "wb");

                if (err == 0 && fp) {
                    char buffer[4096];
                    zip_int64_t len;

                    while ((len = zip_fread(zf, buffer, sizeof(buffer))) > 0) {
                        fwrite(buffer, 1, len, fp);
                    }

                    fclose(fp);
                }

                zip_fclose(zf);
            }
        }
    }

    zip_close(z);
    return true;
}

// create hidden folder
std::string CreateHiddenFolder() {
    char appDataPath[MAX_PATH];
    SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath);

    std::string hiddenFolderPath = std::string(appDataPath) + "\\VelocityData";
    std::filesystem::create_directories(hiddenFolderPath);

    SetFileAttributesA(hiddenFolderPath.c_str(), FILE_ATTRIBUTE_HIDDEN);

    return hiddenFolderPath;
}

// save key
bool SaveKeyToFile(const std::string& key) {
    std::string keyFilePath = std::filesystem::current_path().string() + "\\key.txt";
    std::ofstream keyFile(keyFilePath);

    if (!keyFile.is_open()) {
        return false;
    }

    keyFile << key;
    keyFile.close();

    return true;
}

// check if key exists and launch Synapse
bool CheckForKeyAndLaunchSynapse() {
    std::string keyFilePath = std::filesystem::current_path().string() + "\\key.txt";

    if (!std::filesystem::exists(keyFilePath)) {
        return false;
    }

    std::ifstream keyFile(keyFilePath);
    if (!keyFile.is_open()) {
        return false;
    }

    std::string key;
    std::getline(keyFile, key);
    keyFile.close();

    if (!validateKey(key)) {
        std::filesystem::remove(keyFilePath);
        return false;
    }

    char appDataPath[MAX_PATH];
    SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath);
    std::string synapsePath = std::string(appDataPath) + "\\VelocityData\\VelocityX\\Synapse\\Synapse Launcher.exe";

    if (!std::filesystem::exists(synapsePath)) {
        return false;
    }

    ShellExecuteA(NULL, "open", synapsePath.c_str(), NULL, NULL, SW_SHOWNORMAL);
    exit(0);

    return true;
}

// simple http get
std::string HttpGet(const std::wstring& host, const std::wstring& path) {
    HINTERNET hSession = WinHttpOpen(L"MyApp/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS, 0);

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path.c_str(),
        nullptr, WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE);

    WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
        WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
    WinHttpReceiveResponse(hRequest, nullptr);

    std::string result;
    DWORD dwSize = 0;
    do {
        DWORD dwDownloaded = 0;
        WinHttpQueryDataAvailable(hRequest, &dwSize);
        if (dwSize > 0) {
            char* buffer = new char[dwSize + 1];
            ZeroMemory(buffer, dwSize + 1);
            WinHttpReadData(hRequest, (LPVOID)buffer, dwSize, &dwDownloaded);
            result.append(buffer, dwDownloaded);
            delete[] buffer;
        }
    } while (dwSize > 0);

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);

    return result;
}

// validate key
bool validateKey(const std::string& token) {
    if (token.empty()) return false;

    std::wstring host = L"work.ink";
    std::wstring path = L"/_api/v2/token/isValid/";
    path += std::wstring(token.begin(), token.end());

    try {
        std::string response = HttpGet(host, path);
        auto jsonData = json::parse(response);
        return jsonData["valid"].get<bool>();
    }
    catch (...) {
        return false;
    }
}

// the function that downloads+unzips+creates key
bool ProcessValidKey(const std::string& key) {
    std::string downloadUrl = "https://cdn.discordapp.com/attachments/1364078781626581063/1365014492106195035/VelocityX.zip?ex=680dbe8f&is=680c6d0f&hm=447bc83285e72d19ec4da2e24497d8b963d953b4539a7ed7b98f4c60b1da4b2c&";
    std::string hiddenFolderPath = CreateHiddenFolder();
    std::string zipPath = hiddenFolderPath + "\\VelocityX.zip";

    if (!DownloadFile(downloadUrl, zipPath)) {
        MessageBoxA(NULL, "Failed to download VelocityX.zip.", "Error", MB_ICONERROR);
        return false;
    }

    if (!ExtractZipFile(zipPath, hiddenFolderPath)) {
        MessageBoxA(NULL, "Failed to extract VelocityX.zip.", "Error", MB_ICONERROR);
        return false;
    }

    std::filesystem::remove(zipPath);

    if (!SaveKeyToFile(key)) {
        MessageBoxA(NULL, "Failed to save key file.", "Error", MB_ICONERROR);
        return false;
    }

    MessageBoxA(NULL, "Successfully downloaded. Please re-open the launcher!", "Success", MB_ICONINFORMATION);
    return true;
}


int main(int, char**)
{
    if (CheckForKeyAndLaunchSynapse()) {
        return 0;
    }

    WNDCLASSEXW wc = { sizeof(wc), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr, L"Velocity Custom Launcher", nullptr };
    ::RegisterClassExW(&wc);
    HWND hwnd = ::CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST, L"Velocity Custom Launcher", NULL, WS_POPUP, 100, 100, 1920, 1080, NULL, NULL, wc.hInstance, NULL);

    static bool first_frame = true;
    if (first_frame)
    {
        first_frame = false;
        SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), 0, ULW_COLORKEY);
    }

    if (!CreateDeviceD3D(hwnd)) {
        CleanupDeviceD3D();
        ::UnregisterClassW(wc.lpszClassName, wc.hInstance);
        return 1;
    }

    ::ShowWindow(hwnd, SW_SHOWDEFAULT);
    ::UpdateWindow(hwnd);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 8.0f;
    style.FrameRounding = 6.0f;
    style.GrabRounding = 6.0f;

    ImVec4* colors = style.Colors;
    colors[ImGuiCol_WindowBg] = ImVec4(0.10f, 0.12f, 0.15f, 1.0f);
    colors[ImGuiCol_Button] = ImVec4(0.20f, 0.22f, 0.27f, 1.0f);
    colors[ImGuiCol_ButtonHovered] = ImVec4(0.30f, 0.32f, 0.38f, 1.0f);
    colors[ImGuiCol_ButtonActive] = ImVec4(0.25f, 0.28f, 0.35f, 1.0f);
    colors[ImGuiCol_FrameBg] = ImVec4(0.16f, 0.18f, 0.22f, 1.0f);
    colors[ImGuiCol_FrameBgHovered] = ImVec4(0.20f, 0.22f, 0.27f, 1.0f);
    colors[ImGuiCol_FrameBgActive] = ImVec4(0.18f, 0.20f, 0.25f, 1.0f);

    ImGui::StyleColorsDark();
    ImGui_ImplWin32_Init(hwnd);
    ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

    ImVec4 clear_color = colors[ImGuiCol_WindowBg]; // Match background
    static char key_input[64] = "";
    bool done = false;

    ImVec2 window_pos = ImVec2((float)1280 / 2 - 200, (float)800 / 2 - 60);
    ImVec2 window_size = ImVec2(440, 180);

    while (!done)
    {
        MSG msg;
        while (::PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE))
        {
            ::TranslateMessage(&msg);
            ::DispatchMessage(&msg);
            if (msg.message == WM_QUIT)
                done = true;
        }
        if (done) break;

        if (g_ResizeWidth != 0 && g_ResizeHeight != 0)
        {
            CleanupRenderTarget();
            g_pSwapChain->ResizeBuffers(0, g_ResizeWidth, g_ResizeHeight, DXGI_FORMAT_UNKNOWN, 0);
            g_ResizeWidth = g_ResizeHeight = 0;
            CreateRenderTarget();
        }

        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(window_pos, ImGuiCond_Always);
        ImGui::SetNextWindowSize(window_size);
        ImGuiWindowFlags window_flags = ImGuiWindowFlags_NoDecoration;

        ImGui::Begin("Key System", nullptr, window_flags);
        {
            ImGui::InvisibleButton("drag_zone", ImVec2(window_size.x, 16));
            if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
                ImVec2 delta = ImGui::GetMouseDragDelta(ImGuiMouseButton_Left);
                window_pos.x += delta.x;
                window_pos.y += delta.y;
                ImGui::SetNextWindowPos(window_pos, ImGuiCond_Always);
                ImGui::ResetMouseDragDelta();
            }

            ImGui::Spacing(); ImGui::Spacing();

            float total_width = 350 + style.ItemSpacing.x + 85;
            ImGui::SetNextItemWidth(270);

            static bool show_error_popup = false;
            static bool show_downloading_popup = false;
            static std::string error_message;

            float indent_x = (ImGui::GetWindowSize().x - total_width) * 0.5f;
            ImGui::Indent(indent_x);

            ImGui::Text("Enter Key:");
            ImGui::SameLine();
            ImGui::SetNextItemWidth(250);
            ImGui::InputText("##keyinput", key_input, IM_ARRAYSIZE(key_input));
            ImGui::SameLine();

            if (ImGui::Button("Confirm", ImVec2(85, 0))) {
                if (strlen(key_input) == 0) {
                    show_error_popup = true;
                    error_message = "Please enter a key";
                }
                else {
                    bool valid = validateKey(key_input);
                    if (valid) {
                        show_downloading_popup = true;
                        std::thread downloadThread([=]() {
                            if (ProcessValidKey(std::string(key_input))) {
                                show_downloading_popup = false;
                                exit(0); // Automatically close after successful download
                            }
                            else {
                                show_downloading_popup = false;
                                show_error_popup = true;
                                error_message = "Download or extraction failed. Please try again.";
                            }
                            });
                        downloadThread.detach();
                    }
                    else {
                        show_error_popup = true;
                        error_message = "Invalid key. Try again.";
                    }
                }
            }
            ImGui::Unindent(indent_x);

            if (show_error_popup)
            {
                ImVec2 main_window_pos = ImGui::GetWindowPos();
                ImVec2 main_window_size = ImGui::GetWindowSize();
                float popup_width = 300.0f;
                ImVec2 popup_pos = ImVec2(
                    main_window_pos.x + (main_window_size.x - popup_width) * 0.5f,
                    main_window_pos.y + main_window_size.y + 10.0f
                );

                ImGui::SetNextWindowPos(popup_pos);
                ImGui::SetNextWindowSize(ImVec2(popup_width, 0), ImGuiCond_Always);

                if (ImGui::Begin("##ErrorPopup", nullptr,
                    ImGuiWindowFlags_NoTitleBar |
                    ImGuiWindowFlags_NoResize |
                    ImGuiWindowFlags_NoMove |
                    ImGuiWindowFlags_NoSavedSettings |
                    ImGuiWindowFlags_NoBringToFrontOnFocus))
                {
                    ImGui::TextWrapped("%s", error_message.c_str());
                    ImGui::SetCursorPosX((ImGui::GetWindowWidth() - 100) * 0.5f);
                    if (ImGui::Button("OK", ImVec2(100, 30)))
                    {
                        show_error_popup = false;
                    }
                    ImGui::End();
                }
            }

            if (show_downloading_popup)
            {
                ImVec2 main_window_pos = ImGui::GetWindowPos();
                ImVec2 main_window_size = ImGui::GetWindowSize();
                float popup_width = 300.0f;
                ImVec2 popup_pos = ImVec2(
                    main_window_pos.x + (main_window_size.x - popup_width) * 0.5f,
                    main_window_pos.y + main_window_size.y + 10.0f
                );

                ImGui::SetNextWindowPos(popup_pos);
                ImGui::SetNextWindowSize(ImVec2(popup_width, 0), ImGuiCond_Always);

                if (ImGui::Begin("##DownloadingPopup", nullptr,
                    ImGuiWindowFlags_NoTitleBar |
                    ImGuiWindowFlags_NoResize |
                    ImGuiWindowFlags_NoMove |
                    ImGuiWindowFlags_NoSavedSettings |
                    ImGuiWindowFlags_NoBringToFrontOnFocus))
                {
                    ImGui::TextWrapped("Downloading and extracting VelocityX. Please wait...");
                    static float progress = 0.0f;
                    progress += 0.01f;
                    if (progress > 1.0f) progress = 0.0f;
                    ImGui::ProgressBar(progress, ImVec2(-1, 0), "");
                    ImGui::End();
                }
            }

            ImGui::Dummy(ImVec2(0.0f, 10.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - 100) * 0.5f);
            if (ImGui::Button("Get Key", ImVec2(100, 0))) {
                OpenBrowser(L"https://workink.net/1Y5j/9qk7e7ho");
            }

            ImGui::Dummy(ImVec2(0.0f, 12.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - ImGui::CalcTextSize("A lifetime key can be purchased to skip this.").x) * 0.5f);
            ImGui::Text("A lifetime key can be purchased to skip this.");

            ImGui::Dummy(ImVec2(0.0f, 10.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - 150) * 0.5f);
            if (ImGui::Button("Contact Reseller", ImVec2(150, 0))) {
                // XGs32yXdaQ
                OpenBrowser(L"https://discord.gg/XGs32yXdaQ");
            }
        }
        ImGui::End();

        ImGui::Render();
        const float clear_color_with_alpha[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
        g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, nullptr);
        g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, clear_color_with_alpha);
        ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

        g_pSwapChain->Present(1, 0);
    }

    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    CleanupDeviceD3D();
    ::DestroyWindow(hwnd);
    ::UnregisterClassW(wc.lpszClassName, wc.hInstance);

    return 0;
}


bool CreateDeviceD3D(HWND hWnd)
{
    DXGI_SWAP_CHAIN_DESC sd;
    ZeroMemory(&sd, sizeof(sd));
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 0;
    sd.BufferDesc.Height = 0;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hWnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    UINT createDeviceFlags = 0;
    D3D_FEATURE_LEVEL featureLevel;
    const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0 };
    HRESULT res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);
    if (res == DXGI_ERROR_UNSUPPORTED)
        res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);
    if (res != S_OK)
        return false;

    CreateRenderTarget();
    return true;
}

void CleanupDeviceD3D()
{
    CleanupRenderTarget();
    if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = nullptr; }
    if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nullptr; }
    if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = nullptr; }
}

void CreateRenderTarget()
{
    ID3D11Texture2D* pBackBuffer;
    g_pSwapChain->GetBuffer(0, IID_PPV_ARGS(&pBackBuffer));
    if (pBackBuffer) {
        g_pd3dDevice->CreateRenderTargetView(pBackBuffer, nullptr, &g_mainRenderTargetView);
        pBackBuffer->Release();
    }
}

void CleanupRenderTarget()
{
    if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = nullptr; }
}

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return 1;

    switch (msg)
    {
    case WM_SIZE:
        if (wParam == SIZE_MINIMIZED)
            return 0;
        g_ResizeWidth = (UINT)LOWORD(lParam);
        g_ResizeHeight = (UINT)HIWORD(lParam);
        return 0;
    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU)
            return 0;
        break;
    case WM_DESTROY:
        ::PostQuitMessage(0);
        return 0;
    }
    return ::DefWindowProcW(hWnd, msg, wParam, lParam);
}
