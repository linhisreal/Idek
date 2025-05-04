#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <d3d11.h>
#include <tchar.h>
#include <Windows.h>
#include <filesystem>
#include <shellapi.h>
#include <winhttp.h>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <curl/curl.h>
#include "base64.h"
#include <nlohmann/json.hpp>
#include <shlobj.h>
#include <zip.h>
#include <wininet.h>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "zip.lib")
#pragma comment(lib, "wininet.lib")

// GLOBALS...
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);
static std::string hiddenFolderPath;
static float g_DownloadProgress = 0.0f;
static bool g_DownloadInProgress = false;
static std::atomic<bool> g_DownloadComplete = false;
static std::atomic<bool> g_DownloadSuccess = false;
static std::string g_ErrorMessage;

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

using json = nlohmann::json;

// easy url opening
inline void OpenBrowser(const std::wstring& url) {
    ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

static size_t WriteCallbackFile(void* ptr, size_t size, size_t nmemb, FILE* stream) {
    return fwrite(ptr, size, nmemb, stream);
}

static int ProgressCallback(void*, curl_off_t dltotal, curl_off_t dlnow, curl_off_t, curl_off_t) {
    g_DownloadProgress = dltotal > 0 ? static_cast<float>(dlnow) / static_cast<float>(dltotal) : 0.0f;
    return 0;
}

bool DownloadFile(const std::string& url, const std::string& outputPath) {
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl) {
        g_ErrorMessage = "Failed to initialize CURL";
        return false;
    }

    try {
        std::filesystem::create_directories(std::filesystem::path(outputPath).parent_path());
    }
    catch (const std::exception& e) {
        g_ErrorMessage = std::string("Error creating directory: ") + e.what();
        return false;
    }

    FILE* fp = nullptr;
    if (fopen_s(&fp, outputPath.c_str(), "wb") != 0 || !fp) {
        g_ErrorMessage = "Failed to open file for writing";
        return false;
    }

    std::unique_ptr<FILE, decltype(&fclose)> file_guard(fp, fclose);

    curl_easy_setopt(curl.get(), CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, WriteCallbackFile);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, fp);

    g_DownloadProgress = 0.0f;
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFOFUNCTION, ProgressCallback);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFODATA, nullptr);
    curl_easy_setopt(curl.get(), CURLOPT_NOPROGRESS, 0L);

    curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_USERAGENT, "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
    curl_easy_setopt(curl.get(), CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT, 300L);
    curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT, 30L);
    curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_LIMIT, 1000L); // Abort if less than 1KB/sec for 30 sec
    curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_TIME, 30L);

    // HTTP headers
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Accept: */*");
    headers = curl_slist_append(headers, "Cache-Control: no-cache");
    curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform(curl.get());
    curl_slist_free_all(headers);

    if (res != CURLE_OK) {
        g_ErrorMessage = std::string("Download failed: ") + curl_easy_strerror(res);
        std::filesystem::remove(outputPath);
        return false;
    }

    // verify file has content
    try {
        if (std::filesystem::file_size(outputPath) == 0) {
            g_ErrorMessage = "Downloaded file is empty. The download may have been blocked or failed.";
            std::filesystem::remove(outputPath);
            return false;
        }
    }
    catch (const std::exception& e) {
        g_ErrorMessage = std::string("File size error: ") + e.what();
        std::filesystem::remove(outputPath);
        return false;
    }

    return true;
}

bool ExtractZipFile(const std::string& zipPath, const std::string& extractPath) {
    int err = 0;
    zip* archive = zip_open(zipPath.c_str(), 0, &err);

    if (!archive) {
        g_ErrorMessage = "Failed to open ZIP archive";
        return false;
    }

    try {
        zip_int64_t num_entries = zip_get_num_entries(archive, 0);

        for (zip_uint64_t i = 0; i < num_entries; ++i) {
            const char* name = zip_get_name(archive, i, 0);
            if (!name) continue;

            std::string fullOutputPath = extractPath + "\\" + std::string(name);
            std::filesystem::path outputPath(fullOutputPath);

            if (name[strlen(name) - 1] == '/') {
                std::filesystem::create_directories(outputPath);
            }
            else {
                std::filesystem::create_directories(outputPath.parent_path());

                zip_file* zf = zip_fopen_index(archive, i, 0);
                if (!zf) continue;

                FILE* fout = nullptr;
                if (fopen_s(&fout, fullOutputPath.c_str(), "wb") == 0 && fout) {
                    char buffer[8192]; // Larger buffer for better performance
                    zip_int64_t bytesRead = 0;
                    while ((bytesRead = zip_fread(zf, buffer, sizeof(buffer))) > 0) {
                        fwrite(buffer, 1, static_cast<size_t>(bytesRead), fout);
                    }
                    fclose(fout);
                }
                zip_fclose(zf);
            }
        }

        zip_close(archive);
        return true;
    }
    catch (const std::exception& e) {
        if (archive) zip_close(archive);
        g_ErrorMessage = std::string("ZIP extraction error: ") + e.what();
        return false;
    }
}

// create hidden folder
std::string CreateHiddenFolder() {
    char appDataPath[MAX_PATH] = { 0 };
    if (FAILED(SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath))) {
        g_ErrorMessage = "Failed to get AppData path";
        return "";
    }

    std::string folderPath = std::string(appDataPath) + "\\VelocityData";

    try {
        std::filesystem::create_directories(folderPath);
        SetFileAttributesA(folderPath.c_str(), FILE_ATTRIBUTE_HIDDEN);
        return folderPath;
    }
    catch (const std::exception& e) {
        g_ErrorMessage = std::string("Failed to create hidden folder: ") + e.what();
        return "";
    }
}

// save key
bool SaveKeyToFile(const std::string& key) {
    try {
        std::string keyFilePath = std::filesystem::current_path().string() + "\\key.txt";
        std::ofstream keyFile(keyFilePath);

        if (!keyFile.is_open()) {
            g_ErrorMessage = "Failed to open key file for writing";
            return false;
        }

        keyFile << key;
        return true;
    }
    catch (const std::exception& e) {
        g_ErrorMessage = std::string("Failed to save key: ") + e.what();
        return false;
    }
}

// simple http get with better error handling
std::string HttpGet(const std::wstring& host, const std::wstring& path) {
    HINTERNET hSession = WinHttpOpen(L"VelocityLauncher/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);

    if (!hSession) {
        g_ErrorMessage = "Failed to initialize WinHTTP session";
        return "";
    }

    std::string result;
    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);

    if (hConnect) {
        HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path.c_str(),
            nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);

        if (hRequest) {
            // set timeouts
            DWORD timeout = 30000; // 30 seconds
            WinHttpSetOption(hRequest, WINHTTP_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
            WinHttpSetOption(hRequest, WINHTTP_OPTION_SEND_TIMEOUT, &timeout, sizeof(timeout));
            WinHttpSetOption(hRequest, WINHTTP_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));

            if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                WINHTTP_NO_REQUEST_DATA, 0, 0, 0) && WinHttpReceiveResponse(hRequest, nullptr)) {
                DWORD dwSize = 0;
                do {
                    DWORD dwDownloaded = 0;
                    if (!WinHttpQueryDataAvailable(hRequest, &dwSize)) break;

                    if (dwSize > 0) {
                        std::vector<char> buffer(dwSize + 1);
                        ZeroMemory(buffer.data(), buffer.size());

                        if (WinHttpReadData(hRequest, buffer.data(), dwSize, &dwDownloaded))
                            result.append(buffer.data(), dwDownloaded);
                    }
                } while (dwSize > 0);
            }
            WinHttpCloseHandle(hRequest);
        }
        WinHttpCloseHandle(hConnect);
    }
    WinHttpCloseHandle(hSession);

    return result;
}

bool validateKey(const std::string& token) {
    if (token.empty()) {
        g_ErrorMessage = "Empty key";
        return false;
    }

    try {
        std::wstring host = L"work.ink";
        std::wstring path = L"/_api/v2/token/isValid/" + std::wstring(token.begin(), token.end());
        std::string response = HttpGet(host, path);

        if (response.empty()) {
            g_ErrorMessage = "Work.ink validation failed";
            return false;
        }

        auto workInkJson = json::parse(response);
        if (!workInkJson["valid"].get<bool>()) {
            g_ErrorMessage = "Invalid key";
            return false;
        }

        // get current IP
        std::string ipResponse = HttpGet(L"api.ipify.org", L"/?format=json");
        if (ipResponse.empty()) {
            g_ErrorMessage = "Failed to get IP address";
            return false;
        }

        std::string currentIP;
        try {
            currentIP = json::parse(ipResponse)["ip"].get<std::string>();
        }
        catch (...) {
            g_ErrorMessage = "Failed to parse IP address";
            return false;
        }

        // fetch existing keys from GitHub
        std::string githubUrl = "";
        std::string tokenHeader = "Authorization: Bearer";

        CURL* curl = curl_easy_init();
        if (!curl) {
            g_ErrorMessage = "CURL initialization failed";
            return false;
        }

        std::string jsonStr;
        struct curl_slist* headers = NULL;
        headers = curl_slist_append(headers, tokenHeader.c_str());
        headers = curl_slist_append(headers, "User-Agent: VelocityUploader");
        curl_easy_setopt(curl, CURLOPT_URL, githubUrl.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, +[](char* ptr, size_t size, size_t nmemb, std::string* data) {
            data->append(ptr, size * nmemb); return size * nmemb;
            });
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &jsonStr);
        CURLcode res = curl_easy_perform(curl);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        if (res != CURLE_OK || jsonStr.empty()) {
            g_ErrorMessage = "Failed to fetch keys from GitHub";
            return false;
        }

        // parse GitHub response
        json ghJson;
        try {
            ghJson = json::parse(jsonStr);
        }
        catch (const std::exception& e) {
            g_ErrorMessage = "Failed to parse GitHub response";
            return false;
        }

        std::string sha = ghJson["sha"];
        std::string downloadUrl = ghJson["download_url"];

        std::string contentRaw = HttpGet(L"raw.githubusercontent.com",
            std::wstring(downloadUrl.begin() + 8, downloadUrl.end()));

        if (contentRaw.empty()) {
            g_ErrorMessage = "Failed to get keys content from GitHub";
            return false;
        }

        json keysJson;
        try {
            keysJson = json::parse(contentRaw);
        }
        catch (const std::exception& e) {
            keysJson = json::object();
        }

        // ignore the line i said fr :pray:
        bool keyExists = keysJson.contains(token);

        if (keyExists) {
            // key exists, check IP
            std::string savedIP = keysJson[token].get<std::string>();

            // block if IPs don't match :p
            if (savedIP != currentIP) {
                g_ErrorMessage = "HWID/IP Mismatch: This key is already registered to a different IP address";
                return false;
            }

            // IPs match,allow access
            return true;
        }
        else {
            json updatedJson = keysJson;

            updatedJson[token] = currentIP;

            // check if we actually modified anything
            if (updatedJson.dump() == keysJson.dump()) {
                return false;
            }

            std::string updatedContent = updatedJson.dump();

            // base64 encode the content for da GitHub
            std::string encoded;
            try {
                encoded = base64_encode(updatedContent);
            }
            catch (const std::exception& e) {
                return false;
            }

            json payload = {
                {"message", "Add key " + token},
                {"content", encoded},
                {"sha", sha}
            };

            std::string uploadJson = payload.dump();

            // upload new key (this time using a separate CURL handle :p)
            CURL* pushCurl = curl_easy_init();
            if (!pushCurl) {
                g_ErrorMessage = "Failed to initialize CURL for upload";
                return false;
            }

            std::string result;
            struct curl_slist* pushHeaders = NULL;
            pushHeaders = curl_slist_append(pushHeaders, tokenHeader.c_str());
            pushHeaders = curl_slist_append(pushHeaders, "User-Agent: VelocityUploader");
            pushHeaders = curl_slist_append(pushHeaders, "Content-Type: application/json");

            curl_easy_setopt(pushCurl, CURLOPT_URL, githubUrl.c_str());
            curl_easy_setopt(pushCurl, CURLOPT_CUSTOMREQUEST, "PUT");
            curl_easy_setopt(pushCurl, CURLOPT_HTTPHEADER, pushHeaders);
            curl_easy_setopt(pushCurl, CURLOPT_POSTFIELDS, uploadJson.c_str());
            curl_easy_setopt(pushCurl, CURLOPT_WRITEFUNCTION, +[](char* ptr, size_t size, size_t nmemb, std::string* data) {
                data->append(ptr, size * nmemb); return size * nmemb;
                });
            curl_easy_setopt(pushCurl, CURLOPT_WRITEDATA, &result);

            CURLcode pushRes = curl_easy_perform(pushCurl);
            curl_slist_free_all(pushHeaders);
            curl_easy_cleanup(pushCurl);

            if (pushRes != CURLE_OK) {
                g_ErrorMessage = "Failed to register key";
                return false;
            }

            if (!result.empty()) {
                try {
                    auto resultJson = json::parse(result);
                    if (resultJson.contains("message") &&
                        resultJson["message"].get<std::string>() != "OK" &&
                        !resultJson.contains("content")) {
                        g_ErrorMessage = "GitHub error: " + resultJson["message"].get<std::string>();
                        return false;
                    }
                }
                catch (...) {
                    // Ignore JSON parsing errors in result
                }
            }

            // successfully added new key
            return true;
        }
    }
    catch (const json::exception& e) {
        g_ErrorMessage = std::string("JSON error: ") + e.what();
        return false;
    }
    catch (const std::exception& e) {
        g_ErrorMessage = std::string("Validation error: ") + e.what();
        return false;
    }
    catch (...) {
        g_ErrorMessage = "Unknown validation error";
        return false;
    }
}

// the function that downloads+unzips+creates key
bool ProcessValidKey(const std::string& key) {
    std::string downloadUrl = "https://cdn.discordapp.com/attachments/1364078781626581063/1366139955188994239/VelocityX.zip?ex=6817c57a&is=681673fa&hm=e977373fb00b613725e30e9618f9d6bf541b415e84d8ca5b04fe70ec94f59b7d&";
    std::string timestamp = std::to_string(time(nullptr));
    hiddenFolderPath = CreateHiddenFolder();

    if (hiddenFolderPath.empty())
        return false; // err already set in CreateHiddenFolder

    std::string zipPath = hiddenFolderPath + "\\VelocityX.zip";
    std::string synapseFolder = hiddenFolderPath + "\\VelocityX\\Synapse";

    g_DownloadInProgress = true;

    if (!DownloadFile(downloadUrl, zipPath) || !ExtractZipFile(zipPath, hiddenFolderPath) || !SaveKeyToFile(key)) {
        g_DownloadInProgress = false;
        return false;
    }

    try {
        std::filesystem::remove(zipPath);
    }
    catch (...) {} // ignore cleanup errors

    g_DownloadInProgress = false;
    return true;
}

bool CheckForKeyAndLaunchSynapse() {
    try {
        std::string keyFilePath = std::filesystem::current_path().string() + "\\key.txt";

        if (!std::filesystem::exists(keyFilePath))
            return false;

        std::ifstream keyFile(keyFilePath);
        if (!keyFile.is_open())
            return false;

        std::string key;
        std::getline(keyFile, key);
        keyFile.close();

        if (key.empty()) {
            try {
                std::filesystem::remove(keyFilePath);
            }
            catch (...) {}
            return false;
        }

        // IMPORTANT: Validate the key against the GitHub repo
        if (!validateKey(key)) {
            try {
                std::filesystem::remove(keyFilePath);
            }
            catch (...) {}
            return false;
        }

        char appDataPath[MAX_PATH] = { 0 };
        if (FAILED(SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath)))
            return false;

        std::string synapsePath = std::string(appDataPath) + "\\VelocityData\\VelocityX\\Synapse\\Synapse Launcher.exe";
        if (!std::filesystem::exists(synapsePath))
            return false;

        std::string workingDirectory = std::string(appDataPath) + "\\VelocityData\\VelocityX\\Synapse";

        SHELLEXECUTEINFOA sei = { sizeof(sei) };
        sei.fMask = SEE_MASK_NOASYNC;
        sei.lpVerb = "open";
        sei.lpFile = synapsePath.c_str();
        sei.lpDirectory = workingDirectory.c_str();
        sei.nShow = SW_SHOWNORMAL;

        if (ShellExecuteExA(&sei)) {
            exit(0);
            return true;
        }

        return false;
    }
    catch (const std::exception&) {
        return false;
    }
}

void ProcessKeyAsync(const std::string& key) {
    g_DownloadComplete = g_DownloadSuccess = false;
    g_ErrorMessage.clear();

    std::thread([key]() {
        g_DownloadSuccess = ProcessValidKey(key);
        g_DownloadComplete = true;
        }).detach();
}

bool CreateDeviceD3D(HWND hWnd) {
    DXGI_SWAP_CHAIN_DESC sd{};
    sd.BufferCount = 2;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hWnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0 };
    D3D_FEATURE_LEVEL featureLevel;

    HRESULT res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
        featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);

    if (res == DXGI_ERROR_UNSUPPORTED)
        res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0,
            featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);

    if (res != S_OK)
        return false;

    CreateRenderTarget();
    return true;
}

void CleanupDeviceD3D() {
    CleanupRenderTarget();
    if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = nullptr; }
    if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nullptr; }
    if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = nullptr; }
}

void CreateRenderTarget() {
    ID3D11Texture2D* pBackBuffer;
    g_pSwapChain->GetBuffer(0, IID_PPV_ARGS(&pBackBuffer));
    if (pBackBuffer) {
        g_pd3dDevice->CreateRenderTargetView(pBackBuffer, nullptr, &g_mainRenderTargetView);
        pBackBuffer->Release();
    }
}

void CleanupRenderTarget() {
    if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = nullptr; }
}

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return 1;

    switch (msg) {
    case WM_SIZE:
        if (wParam == SIZE_MINIMIZED) return 0;
        g_ResizeWidth = LOWORD(lParam);
        g_ResizeHeight = HIWORD(lParam);
        return 0;
    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU) return 0;
        break;
    case WM_DESTROY:
        ::PostQuitMessage(0);
        return 0;
    }
    return ::DefWindowProcW(hWnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int) {
    // init curl
    curl_global_init(CURL_GLOBAL_ALL);

    char appDataPath[MAX_PATH] = { 0 };
    SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath);
    hiddenFolderPath = std::string(appDataPath) + "\\VelocityData";

    if (CheckForKeyAndLaunchSynapse()) {
        curl_global_cleanup();
        return 0;
    }

    WNDCLASSEXW wc = { sizeof(wc), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr, L"Velocity Custom Launcher", nullptr };
    RegisterClassExW(&wc);
    HWND hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST, L"Velocity Custom Launcher", NULL, WS_POPUP, 100, 100, 1920, 1080, NULL, NULL, wc.hInstance, NULL);
    SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), 0, ULW_COLORKEY);

    if (!CreateDeviceD3D(hwnd)) {
        CleanupDeviceD3D();
        UnregisterClassW(wc.lpszClassName, wc.hInstance);
        curl_global_cleanup();
        return 1;
    }

    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 8.0f;
    style.FrameRounding = style.GrabRounding = 6.0f;

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

    ImVec4 clear_color = colors[ImGuiCol_WindowBg];
    static char key_input[64] = "";
    bool done = false;
    ImVec2 window_pos = ImVec2((float)1280 / 2 - 200, (float)800 / 2 - 60);
    ImVec2 window_size = ImVec2(440, 180);
    static bool show_error_popup = false, show_success_popup = false;
    static std::string error_message;

    while (!done) {
        // handle messages
        MSG msg;
        while (PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            if (msg.message == WM_QUIT)
                done = true;
        }
        if (done) break;

        if (g_ResizeWidth != 0 && g_ResizeHeight != 0) {
            CleanupRenderTarget();
            g_pSwapChain->ResizeBuffers(0, g_ResizeWidth, g_ResizeHeight, DXGI_FORMAT_UNKNOWN, 0);
            g_ResizeWidth = g_ResizeHeight = 0;
            CreateRenderTarget();
        }

        if (g_DownloadComplete) {
            g_DownloadInProgress = false;
            if (g_DownloadSuccess) {
                show_success_popup = true;
                std::thread([hwnd]() { Sleep(5000); PostMessage(hwnd, WM_QUIT, 0, 0); }).detach();
            }
            else {
                show_error_popup = true;
                error_message = g_ErrorMessage.empty() ?
                    "Download or extraction failed. Please try again." : g_ErrorMessage;
            }
            g_DownloadComplete = false;
        }

        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();

        // Main window
        ImGui::SetNextWindowPos(window_pos, ImGuiCond_Always);
        ImGui::SetNextWindowSize(window_size);
        ImGui::Begin("Key System", nullptr, ImGuiWindowFlags_NoDecoration);
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

            // input area
            float total_width = 350 + style.ItemSpacing.x + 85;
            float indent_x = (ImGui::GetWindowSize().x - total_width) * 0.5f;
            ImGui::Indent(indent_x);

            ImGui::Text("Enter Key:");
            ImGui::SameLine();
            ImGui::SetNextItemWidth(250);
            ImGui::InputText("##keyinput", key_input, IM_ARRAYSIZE(key_input));
            ImGui::SameLine();

            // confirm button
            bool button_disabled = g_DownloadInProgress;
            if (button_disabled) ImGui::PushStyleVar(ImGuiStyleVar_Alpha, ImGui::GetStyle().Alpha * 0.5f);

            if (ImGui::Button("Confirm", ImVec2(85, 0)) && !button_disabled) {
                if (strlen(key_input) == 0) {
                    show_error_popup = true;
                    error_message = "Please enter a key";
                }
                else {
                    if (validateKey(key_input)) {
                        ProcessKeyAsync(key_input);
                    }
                    else {
                        show_error_popup = true;
                        error_message = g_ErrorMessage.empty() ?
                            "Invalid key. Try again." : g_ErrorMessage;
                    }
                }
            }

            if (button_disabled) ImGui::PopStyleVar();
            ImGui::Unindent(indent_x);

            // error popup
            if (show_error_popup) {
                ImGui::SetNextWindowPos(ImVec2(
                    window_pos.x + (window_size.x - 300) * 0.5f,
                    window_pos.y + window_size.y + 10.0f));
                ImGui::SetNextWindowSize(ImVec2(300, 0), ImGuiCond_Always);

                if (ImGui::Begin("##ErrorPopup", nullptr, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                    ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus)) {
                    ImGui::TextWrapped("%s", error_message.c_str());
                    ImGui::SetCursorPosX((ImGui::GetWindowWidth() - 100) * 0.5f);
                    if (ImGui::Button("OK", ImVec2(100, 30)))
                        show_error_popup = false;
                    ImGui::End();
                }
            }

            // success popup
            if (show_success_popup) {
                ImGui::SetNextWindowPos(ImVec2(
                    window_pos.x + (window_size.x - 300) * 0.5f,
                    window_pos.y + window_size.y + 10.0f));
                ImGui::SetNextWindowSize(ImVec2(300, 0), ImGuiCond_Always);

                if (ImGui::Begin("##SuccessPopup", nullptr, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                    ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus)) {
                    ImGui::TextWrapped("Successfully downloaded. Please re-open the launcher!\n(ily mommy lina <3)");
                    ImGui::SetCursorPosX((ImGui::GetWindowWidth() - 100) * 0.5f);
                    if (ImGui::Button("OK", ImVec2(100, 30))) {
                        show_success_popup = false;
                        PostMessage(hwnd, WM_QUIT, 0, 0);
                    }
                    ImGui::End();
                }
            }

            // download progress display
            if (g_DownloadInProgress) {
                ImGui::SetNextWindowPos(ImVec2(
                    window_pos.x + (window_size.x - 300) * 0.5f,
                    window_pos.y + window_size.y + 10.0f));
                ImGui::SetNextWindowSize(ImVec2(300, 0), ImGuiCond_Always);

                if (ImGui::Begin("##DownloadingPopup", nullptr, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                    ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus)) {
                    ImGui::TextWrapped("Downloading and extracting VelocityX. Please wait...");

                    char buffer[32];
                    sprintf_s(buffer, "%.0f%%", g_DownloadProgress * 100.0f);
                    ImGui::ProgressBar(g_DownloadProgress, ImVec2(-1, 0), buffer);
                    ImGui::End();
                }
            }

            ImGui::Dummy(ImVec2(0.0f, 10.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - 100) * 0.5f);
            if (ImGui::Button("Get Key", ImVec2(100, 0)) && !g_DownloadInProgress)
                OpenBrowser(L"https://workink.net/1Y5j/9qk7e7ho");

            ImGui::Dummy(ImVec2(0.0f, 12.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - ImGui::CalcTextSize("A premium key can be purchased to skip this.").x) * 0.5f);
            ImGui::Text("A premium key can be purchased to skip this.");

            ImGui::Dummy(ImVec2(0.0f, 10.0f));
            ImGui::SetCursorPosX((ImGui::GetWindowSize().x - 150) * 0.5f);
            if (ImGui::Button("Contact Reseller", ImVec2(150, 0)) && !g_DownloadInProgress)
                OpenBrowser(L"https://discord.gg/velocitykeys");
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
    DestroyWindow(hwnd);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);
    curl_global_cleanup();

    return 0;
}
