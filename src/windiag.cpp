// windiag.cpp -- FleshCore: WHERE the game's thread is stuck, not just WHETHER.
//
// THE BLIND SPOT THIS CLOSES. FleshCore.log can show the
// game's thread running none of FleshCore's tasks for a minute or more (the
// startup tail, or at the main
// menu after an Alt-Tab), one line a second, every one of them "not running".
// Nothing else says WHICH thread sits WHERE in WHAT module, what the window is
// told meanwhile, or how long the one D3D call that creates the device takes
// (the gap between another plugin's hook on that call and a later
// plugin's post-init line can run to a minute and a half, and no log times it). The
// three probes here are built to answer those.
//
// THREE THREADS HAVE BEEN CALLED 'THE MAIN THREAD', and the sampler walks all of
// them plus the one nobody named: one ran DataLoaded (flesh.cpp's
// g_mainThread), one runs FleshCore's tasks (g_taskThread -- the one the heartbeat
// times; it stays 0 until the first task has run),
// one is the process's primary thread (created the D3D device inside another
// plugin's hook, owns the window), and one ran two plugins' Present-hook work
// -- the renderer's thread, which the
// swap-chain Present probe below learns by being called on it.
//
// THE RULES THIS FILE FOLLOWS.
//   * Nothing here takes a FleshCore lock. Lines go out through Env::log /
//     Env::profLog, whose flesh.cpp adapters TryEnter the log locks and drop
//     the line when held -- the watchdog's own rule (flesh.cpp, HeartbeatTick).
//   * While ANY thread is suspended, this code makes system calls and reads
//     mapped memory, nothing else: no heap, no CRT I/O, no lock, no loader
//     lock (GetModuleHandleEx / GetModuleFileName), no dbghelp (it may
//     HeapAlloc while the target is stopped -- a target stopped inside
//     HeapAlloc then owns the lock the poller would wait for). Even RtlLookupFunctionEntry
//     is out: it takes ntdll's inverted-function-table lock in shared mode and
//     a thread stopped inside LoadLibrary may hold it exclusive. The function
//     table is read from the owning image's .pdata by hand, which is what
//     RtlLookupFunctionEntry does underneath, minus the lock.
//   * Nothing read while a thread is stopped goes through flesh.cpp's Readable:
//     that is a thread_local VirtualQuery cache that only ForgetMemory resets,
//     and the poller never calls it, so an entry for an exited thread's stack
//     would say 'committed' forever. PeFunctionEntry and WalkSuspended use
//     DefaultReadable (VirtualQuery, uncached). WarmReadable still touches the
//     cache once before the first SuspendThread so that no GCC-emutls
//     first-touch malloc can happen later on this thread (a second safeguard now,
//     not required).
//   * A remembered thread id is only a number: Windows hands an exited thread's
//     id to the next thread created anywhere on the machine, so every id is
//     checked against GetProcessIdOfThread and GetExitCodeThread AFTER
//     OpenThread and BEFORE SuspendThread; a stale one is forgotten, never
//     suspended.
//   * The IAT slot is written once and never re-wrapped: a hook installed later saved
//     this probe's pointer as its own original, and writing the probe in again
//     would make the two call each other forever. Later changes are only logged.
//   * The WndProc subclass publishes its predecessor BEFORE SetWindowLongPtr
//     swaps it in, so no message can ever find it unset; it never falls back
//     to DefWindowProc, which could swallow a WM_ACTIVATE / WM_SIZE the game
//     needs. One record per window, looked up by HWND, so a window found before
//     the swap chain named the real one keeps chaining to ITS predecessor, and a
//     window re-found after another died is reused, never chained to itself.
//     Its body is lock-free and writes a ring; the poller does the logging.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include "windiag.h"
#include <d3d11.h>      // D3D11CreateDeviceAndSwapChain's signature, DXGI_SWAP_CHAIN_DESC, IDXGISwapChain; nothing is LINKED -- the probe chains to the slot's previous value
#include <tlhelp32.h>   // the 10 s sweep's thread snapshot (kernel32, no link flag)
#include <cstdio>
#include <cstdarg>
#include <cstring>

namespace windiag {
namespace {

// ======================================================================= ENVIRONMENT
Env           g_env{};
volatile long g_installed = 0;

// Before Install (the import-table walk run on its own) there is no Env::readable;
// this is the same VirtualQuery walk flesh.cpp's RangeOK performs, uncached.
bool DefaultReadable(const void* p, std::size_t n)
{
    if (!p || !n) return false;
    const std::uint8_t* cur = static_cast<const std::uint8_t*>(p);
    std::size_t left = n;
    while (left) {
        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(cur, &mbi, sizeof mbi) != sizeof mbi) return false;
        if (mbi.State != MEM_COMMIT || (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return false;
        const std::uint8_t* end = static_cast<const std::uint8_t*>(mbi.BaseAddress) + mbi.RegionSize;
        const std::size_t avail = std::size_t(end - cur);
        if (avail >= left) return true;
        left -= avail; cur += avail;
    }
    return true;
}
bool Readable(const void* p, std::size_t n) { return g_env.readable ? g_env.readable(p, n) : DefaultReadable(p, n); }

// ONE LINE, FORMATTED HERE, HANDED TO flesh.cpp. Every FleshCore.log line
// carries [WINDIAG] so a log can be grepped for the lot; the profiler log
// gets the long dumps. Both adapters are non-blocking (see windiag.h).
__attribute__((format(gnu_printf, 1, 2)))
void LogF(const char* fmt, ...)
{
    if (!g_env.log) return;
    char line[1100];
    std::memcpy(line, "[WINDIAG] ", 10);
    va_list ap; va_start(ap, fmt); std::vsnprintf(line + 10, 1000, fmt, ap); va_end(ap);
    g_env.log(line);
}
__attribute__((format(gnu_printf, 1, 2)))
void ProfF(const char* fmt, ...)
{
    if (!g_env.profLog) return;
    char line[1100];
    std::memcpy(line, "[WINDIAG] ", 10);
    va_list ap; va_start(ap, fmt); std::vsnprintf(line + 10, 1000, fmt, ap); va_end(ap);
    g_env.profLog(line);
}

// THE CLOCK. QueryPerformanceCounter, raw, so a WndProc entry costs one read
// and the poller converts later; GetTickCount's 16 ms steps are the order of
// the thing measured (flesh.cpp, NowMs).
LONGLONG Qpc() { LARGE_INTEGER c; QueryPerformanceCounter(&c); return c.QuadPart; }
double QpcPerMs()
{
    static double perMs = 0.0;
    if (perMs == 0.0) { LARGE_INTEGER f; if (QueryPerformanceFrequency(&f) && f.QuadPart) perMs = double(f.QuadPart) / 1000.0; else perMs = 1.0; }
    return perMs;
}
double QpcToMs(LONGLONG dt) { return double(dt) / QpcPerMs(); }
// Local wall time of a QPC reading taken earlier (the ring stores QPC; the
// log line is written up to 200 ms later and must carry the ARRIVAL time, which
// is what lines up with other plugins' own stamps).
void WallStampOf(LONGLONG qpcAt, char* out, std::size_t n)
{
    FILETIME ft{}; GetSystemTimeAsFileTime(&ft);
    ULONGLONG t = (ULONGLONG(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    const double agoMs = QpcToMs(Qpc() - qpcAt);
    const ULONGLONG ago100ns = agoMs > 0.0 ? ULONGLONG(agoMs * 10000.0) : 0ull;
    t = ago100ns < t ? t - ago100ns : 0ull;
    FILETIME at{ DWORD(t & 0xFFFFFFFFu), DWORD(t >> 32) }, loc{};
    SYSTEMTIME st{};
    if (FileTimeToLocalFileTime(&at, &loc) && FileTimeToSystemTime(&loc, &st))
        std::snprintf(out, n, "%02u:%02u:%02u.%03u", unsigned(st.wHour), unsigned(st.wMinute), unsigned(st.wSecond), unsigned(st.wMilliseconds));
    else
        std::snprintf(out, n, "??:??:??.???");
}
void WallStampNow(char* out, std::size_t n)
{
    SYSTEMTIME st{}; GetLocalTime(&st);
    std::snprintf(out, n, "%02u:%02u:%02u.%03u", unsigned(st.wHour), unsigned(st.wMinute), unsigned(st.wSecond), unsigned(st.wMilliseconds));
}

// GetProcAddress without -Wcast-function-type: FARPROC and the real type are the
// same size, and memcpy is the one cast GCC does not argue with.
template <class F> F Proc(HMODULE m, const char* name)
{
    static_assert(sizeof(F) == sizeof(FARPROC), "function pointer size");
    F f = nullptr;
    if (!m) return f;
    FARPROC p = GetProcAddress(m, name);
    if (p) std::memcpy(&f, &p, sizeof f);
    return f;
}

// ======================================================================= IDENTITY
// Who is who, as learned in play: the thread that called
// D3D11CreateDeviceAndSwapChain, the thread that owns the window, the thread
// Present is called on, and the window itself (carried as a LONGLONG so the
// Interlocked family can move it).
volatile long     g_d3dInitThread = 0;
volatile long     g_wndThread     = 0;
volatile long     g_presentThread = 0;
volatile LONGLONG g_hwnd          = 0;
HWND GameHwnd() { return reinterpret_cast<HWND>(static_cast<LONG_PTR>(InterlockedCompareExchange64(&g_hwnd, 0, 0))); }
volatile long g_subclassed = 0;   // the WndProc subclass is in (defined here: SetGameHwnd resets it when the window changes)
void SetGameHwnd(HWND h, const char* how)
{
    const LONGLONG nv = LONGLONG(reinterpret_cast<LONG_PTR>(h));
    const LONGLONG old = InterlockedExchange64(&g_hwnd, nv);
    if (old && old != nv) {
        // The poller may have picked a window by class or visibility before
        // the swap chain named the real one: the subclass moves with the name.
        LogF("[WND] the game window is now 0x%llX (%s); it was 0x%llX -- the subclass is re-armed for the new one",
             (unsigned long long)nv, how, (unsigned long long)old);
        InterlockedExchange(&g_subclassed, 0);
    }
}

// ======================================================================= MODULE NAMES
// A MODULE NAME WITHOUT THE LOADER LOCK. GetModuleHandleEx(FROM_ADDRESS) and
// GetModuleFileName take ntdll's loader lock; a thread wedged inside a DllMain
// holds it, and asking then hangs the asker for good. Two routes, both
// lock-free: a table built from K32EnumProcessModules / K32GetModuleInformation /
// K32GetModuleBaseNameA (psapi reads the PEB's module list without the loader
// lock; refreshed BEFORE anything is suspended, read only AFTER it is resumed),
// and VirtualQuery + K32GetMappedFileNameA for any address the table does not
// know (a module loaded since, a JIT page). Nothing in either is ever called
// while a thread is stopped.
using FnEnumProcessModules   = BOOL  (WINAPI*)(HANDLE, HMODULE*, DWORD, LPDWORD);
using FnGetModuleInformation = BOOL  (WINAPI*)(HANDLE, HMODULE, void*, DWORD);
using FnGetModuleBaseNameA   = DWORD (WINAPI*)(HANDLE, HMODULE, LPSTR, DWORD);
using FnGetMappedFileNameA   = DWORD (WINAPI*)(HANDLE, LPVOID, LPSTR, DWORD);
using FnGetThreadDescription = HRESULT (WINAPI*)(HANDLE, PWSTR*);
using FnRtlVirtualUnwind     = PEXCEPTION_ROUTINE (NTAPI*)(DWORD, DWORD64, DWORD64, PRUNTIME_FUNCTION, PCONTEXT, PVOID*, PDWORD64, PKNONVOLATILE_CONTEXT_POINTERS);
FnEnumProcessModules   g_enumModules   = nullptr;
FnGetModuleInformation g_moduleInfo    = nullptr;
FnGetModuleBaseNameA   g_moduleName    = nullptr;
FnGetMappedFileNameA   g_mappedName    = nullptr;
FnGetThreadDescription g_threadDesc    = nullptr;   // Win10 1607+; names PrismaUI's and ENB's worker threads when they set one
FnRtlVirtualUnwind     g_rtlVirtualUnwind = nullptr;

struct ModInfoMirror { void* base; DWORD size; void* entry; };   // psapi's MODULEINFO, 24 bytes on x64
static_assert(sizeof(ModInfoMirror) == 24, "MODULEINFO is 24 bytes on x64");
struct ModRec { std::uintptr_t base, end; char name[40]; };
constexpr int kMaxMods = 1024;   // room for a large modlist's SKSE DLLs plus the system's: a module past the cap still names itself through K32GetMappedFileNameA
ModRec g_mods[kMaxMods];        // POLLER THREAD ONLY (the sampler runs there)
int    g_modCount = 0;
void RefreshModuleTable()
{
    g_modCount = 0;
    if (!g_enumModules || !g_moduleInfo || !g_moduleName) return;
    static HMODULE hm[kMaxMods];
    DWORD needed = 0;
    if (!g_enumModules(GetCurrentProcess(), hm, DWORD(sizeof hm), &needed)) return;
    int n = int(needed / sizeof(HMODULE)); if (n > kMaxMods) n = kMaxMods;
    for (int i = 0; i < n; ++i) {
        ModInfoMirror mi{};
        if (!g_moduleInfo(GetCurrentProcess(), hm[i], &mi, DWORD(sizeof mi))) continue;
        ModRec& r = g_mods[g_modCount];
        r.base = reinterpret_cast<std::uintptr_t>(mi.base); r.end = r.base + mi.size;
        r.name[0] = 0;
        if (!g_moduleName(GetCurrentProcess(), hm[i], r.name, DWORD(sizeof r.name))) std::snprintf(r.name, sizeof r.name, "module@0x%llX", (unsigned long long)r.base);
        r.name[sizeof r.name - 1] = 0;
        ++g_modCount;
    }
}
// The basename of a device path ('\Device\HarddiskVolumeN\...\d3d11.dll').
void BaseNameOf(const char* path, char* out, std::size_t n)
{
    const char* b = path;
    for (const char* p = path; *p; ++p) if (*p == '\\' || *p == '/') b = p + 1;
    std::size_t i = 0; for (; b[i] && i + 1 < n; ++i) out[i] = b[i];
    out[i] = 0;
}
// ANY thread, never while something is suspended: VirtualQuery + K32GetMappedFileNameA.
bool NameAddrSys(std::uintptr_t a, char* out, std::size_t n, std::uintptr_t* rva)
{
    *rva = a; out[0] = 0;
    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(reinterpret_cast<const void*>(a), &mbi, sizeof mbi) != sizeof mbi || mbi.State != MEM_COMMIT || !mbi.AllocationBase) {
        std::snprintf(out, n, "?"); return false;
    }
    if (mbi.Type == MEM_IMAGE) {
        *rva = a - reinterpret_cast<std::uintptr_t>(mbi.AllocationBase);
        char path[MAX_PATH] = {};
        if (g_mappedName && g_mappedName(GetCurrentProcess(), reinterpret_cast<void*>(a), path, MAX_PATH)) { BaseNameOf(path, out, n); return true; }
        std::snprintf(out, n, "image@0x%llX", (unsigned long long)reinterpret_cast<std::uintptr_t>(mbi.AllocationBase));
        return true;
    }
    std::snprintf(out, n, mbi.Type == MEM_PRIVATE ? "private(jit?)" : "mapped");
    return false;
}
// POLLER THREAD ONLY: the pre-built table first (what the sampler uses for
// every frame), the system route for the rest.
void NameAddrTable(std::uintptr_t a, char* out, std::size_t n, std::uintptr_t* rva)
{
    for (int i = 0; i < g_modCount; ++i) {
        if (a >= g_mods[i].base && a < g_mods[i].end) { *rva = a - g_mods[i].base; std::snprintf(out, n, "%s", g_mods[i].name); return; }
    }
    NameAddrSys(a, out, n, rva);
}
// "module.dll+0xRVA" in one call, either route.
void FormatAddr(std::uintptr_t a, bool useTable, char* out, std::size_t n)
{
    char mod[48]; std::uintptr_t rva = 0;
    if (useTable) NameAddrTable(a, mod, sizeof mod, &rva); else NameAddrSys(a, mod, sizeof mod, &rva);
    std::snprintf(out, n, "%s+0x%llX", mod, (unsigned long long)rva);
}

// ======================================================================= THE IMPORT-TABLE WALK
// HookModuleFileIat's walk (flesh.cpp), generalised: DLL name AND function
// name, every read checked, returning the RVA of the IAT slot so the caller
// can save, write and re-read it. The same walk runs on an image read from
// DISK (RVAs mapped through the section table) and on a loaded
// module (RVAs are offsets from the base; reads go through Env::readable, as
// in flesh.cpp). It reproduces 0x017502A0 for d3d11!D3D11CreateDeviceAndSwapChain
// and 0x0174F388 / 0x0174F310 / 0x0174F298 / 0x0174F248 for the four kernel32
// slots flesh.cpp hard-codes, on the 1.6.1170 image.
struct ImageView {
    const std::uint8_t*          base = nullptr;
    std::size_t                  size = 0;       // file layout only
    bool                         fileLayout = false;
    const IMAGE_SECTION_HEADER*  sec = nullptr;  // file layout, once the headers are parsed
    unsigned                     nsec = 0;
    std::uint32_t                hdrSize = 0;
    const void* At(std::uint32_t rva, std::size_t n) const
    {
        if (!fileLayout) { const void* p = base + rva; return Readable(p, n) ? p : nullptr; }
        std::size_t off = rva;
        if (sec && rva >= hdrSize) {
            bool found = false;
            for (unsigned i = 0; i < nsec && !found; ++i) {
                const IMAGE_SECTION_HEADER& s = sec[i];
                const std::uint32_t va = s.VirtualAddress;
                const std::uint32_t span = s.Misc.VirtualSize > s.SizeOfRawData ? s.Misc.VirtualSize : s.SizeOfRawData;
                if (rva < va || rva >= va + span) continue;
                if (std::size_t(rva - va) + n > s.SizeOfRawData) return nullptr;   // in the virtual-only tail: not on disk
                off = std::size_t(s.PointerToRawData) + (rva - va);
                found = true;
            }
            if (!found) return nullptr;
        }
        if (off + n > size || off + n < off) return nullptr;
        return base + off;
    }
};
std::uint32_t FindIatSlotRva(ImageView& v, const char* dll, const char* fn)
{
    const auto* dos = static_cast<const IMAGE_DOS_HEADER*>(v.At(0, sizeof(IMAGE_DOS_HEADER)));
    if (!dos || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0) return 0;
    const auto lfanew = std::uint32_t(dos->e_lfanew);
    const auto* nt = static_cast<const IMAGE_NT_HEADERS64*>(v.At(lfanew, sizeof(IMAGE_NT_HEADERS64)));
    if (!nt || nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return 0;
    if (v.fileLayout) {
        const std::uint32_t secRva = lfanew + 4u + std::uint32_t(sizeof(IMAGE_FILE_HEADER)) + nt->FileHeader.SizeOfOptionalHeader;
        const unsigned nsec = nt->FileHeader.NumberOfSections;
        v.sec = static_cast<const IMAGE_SECTION_HEADER*>(v.At(secRva, std::size_t(nsec) * sizeof(IMAGE_SECTION_HEADER)));
        v.nsec = v.sec ? nsec : 0u;
        v.hdrSize = nt->OptionalHeader.SizeOfHeaders;
    }
    const IMAGE_DATA_DIRECTORY& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress || !dir.Size) return 0;
    const std::size_t dllLen = std::strlen(dll), fnLen = std::strlen(fn);
    for (std::uint32_t d = dir.VirtualAddress;; d += std::uint32_t(sizeof(IMAGE_IMPORT_DESCRIPTOR))) {
        const auto* imp = static_cast<const IMAGE_IMPORT_DESCRIPTOR*>(v.At(d, sizeof(IMAGE_IMPORT_DESCRIPTOR)));
        if (!imp || !imp->Name) break;
        if (!imp->OriginalFirstThunk || !imp->FirstThunk) continue;
        // Exactly strlen(dll)+1 bytes are compared, so exactly that many are checked.
        const char* name = static_cast<const char*>(v.At(imp->Name, dllLen + 1));
        if (!name || _strnicmp(name, dll, dllLen + 1) != 0) continue;
        for (std::uint32_t i = 0;; ++i) {
            const auto* ot = static_cast<const ULONGLONG*>(v.At(imp->OriginalFirstThunk + 8u * i, 8));
            if (!ot || !*ot) break;
            if (*ot & IMAGE_ORDINAL_FLAG64) continue;
            const auto ibn = std::uint32_t(*ot & 0x7FFFFFFFu);   // IMAGE_IMPORT_BY_NAME: WORD Hint, then the name
            const char* nm = static_cast<const char*>(v.At(ibn, 2 + fnLen + 1));
            if (!nm || std::strncmp(nm + 2, fn, fnLen + 1) != 0) continue;
            const std::uint32_t slotRva = imp->FirstThunk + 8u * i;
            return v.At(slotRva, 8) ? slotRva : 0u;
        }
    }
    return 0;
}

// ======================================================================= (2) THE WINDOW
// ---- the ring the WndProc writes and the poller reads --------------------------
// THE CHAINED DURATION IS THE DATUM. If WM_ACTIVATEAPP's chain takes 99 s, a
// handler below this one handles the Alt-Tab synchronously, and the log must say so
// within 200 ms of the message arriving, not 99 s later: the ENTRY record is
// published before the chain is called and the poller logs it "(in progress)";
// the RETURN is published when the chain comes back and logged on its own line.
// Messages nest (a WM_WINDOWPOSCHANGED's DefWindowProc sends WM_SIZE and
// WM_MOVE from inside the chain), so returns arrive LIFO and are matched by
// sequence number, not by order.
struct WndRec {
    long     seqIn;          // == seq once the entry fields are written; read with Interlocked*
    long     seqOut;         // == seq once the return fields are written
    LONGLONG qpcIn, qpcOut;
    UINT     msg;
    WPARAM   wp;
    LPARAM   lp;
    DWORD    tid;
    HWND     hwnd;
    LRESULT  result;
    int      a0, a1, a2, a3; // copies of pointed-to data that dies when the handler returns (WINDOWPOS, STYLESTRUCT)
    unsigned a4;
    bool     aux;            // a0..a4 are valid
};
constexpr long kRing = 512;
WndRec        g_ring[kRing];
volatile long g_ringSeq     = 0;   // the last sequence number handed out (1-based)
volatile long g_msgTotal    = 0;   // every message through the subclass -- proves the owner thread is pumping
volatile long g_setCursor   = 0;   // WM_SETCURSOR: counted, never recorded
DWORD         g_subclassOwner = 0;

// ONE RECORD PER WINDOW EVER SUBCLASSED. The poller may pick a window by
// class or visibility before the swap chain names the real one, and a window
// may die and be re-found: each window's predecessor and charset live in its
// own record, looked up by HWND, so a message to an EARLIER window never chains
// to a LATER window's predecessor, and a re-found window already held is
// reused, never chained to itself. A record's h/prev/unicode are written BEFORE
// g_subN publishes it and BEFORE SetWindowLongPtr swaps the subclass in, so the first
// message to the window already finds it. The one later write is the 'a
// subclass landed between Get and Set' fix-up in InstallSubclass: a message in
// that microsecond gap chains to 'before', as a single slot did.
// Records are never removed: a window that died can get no message, and its
// record costs one pointer compare per message to the others.
struct SubRec { HWND h; WNDPROC prev; bool unicode; };
constexpr long kSubMax = 4;
SubRec        g_sub[kSubMax];
volatile long g_subN = 0;
const SubRec* FindSub(HWND h)
{
    const long n = InterlockedCompareExchange(&g_subN, 0, 0);
    for (long i = 0; i < n; ++i) if (g_sub[i].h == h) return &g_sub[i];
    return nullptr;
}

// The whitelist: the Alt-Tab family and everything that moves, sizes, shows,
// focuses or activates the window. WM_INPUT, WM_MOUSEMOVE, WM_PAINT and
// WM_TIMER are never recorded (they would lap the ring in a second).
bool RecordedMsg(UINT m)
{
    switch (m) {
    case WM_ACTIVATEAPP: case WM_ACTIVATE: case WM_NCACTIVATE: case WM_SETFOCUS: case WM_KILLFOCUS:
    case WM_SIZE: case WM_MOVE: case WM_WINDOWPOSCHANGED: case WM_SHOWWINDOW: case WM_SYSCOMMAND:
    case WM_ENTERSIZEMOVE: case WM_EXITSIZEMOVE: case WM_DISPLAYCHANGE: case WM_MOUSEACTIVATE:
    case WM_CAPTURECHANGED: case WM_DEVICECHANGE: case WM_POWERBROADCAST: case WM_STYLECHANGED:
        return true;
    default:
        return false;
    }
}
LRESULT Chain(const SubRec* s, HWND h, UINT m, WPARAM w, LPARAM l)
{
    return s->unicode ? CallWindowProcW(s->prev, h, m, w, l) : CallWindowProcA(s->prev, h, m, w, l);
}
LRESULT CALLBACK DiagWndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    // Published before SetWindowLongPtr swapped the subclass in, so present on the first
    // message. If it ever were not (unreachable by construction: only
    // InstallSubclass puts the subclass on a window, after publishing), wait briefly and
    // then use the newest record rather than hang the pump -- NEVER
    // DefWindowProc, which could swallow a WM_ACTIVATE or WM_SIZE the game needs.
    const SubRec* s = FindSub(h);
    for (int spin = 0; !s; ++spin) {
        YieldProcessor();
        s = FindSub(h);
        if (!s && spin > 100000) { const long n = InterlockedCompareExchange(&g_subN, 0, 0); if (n > 0) s = &g_sub[n - 1]; }
    }
    InterlockedIncrement(&g_msgTotal);
    if (m == WM_SETCURSOR) { InterlockedIncrement(&g_setCursor); return Chain(s, h, m, w, l); }
    if (!RecordedMsg(m)) return Chain(s, h, m, w, l);
    const long seq = InterlockedIncrement(&g_ringSeq);
    WndRec& r = g_ring[(seq - 1) & (kRing - 1)];
    // SEQLOCK ORDER: both sequence fields are cleared (full barriers) BEFORE the
    // fields are rewritten, so a drain that copied the record 512 messages ago
    // and re-checks the sequence afterwards sees the change and discards the copy.
    InterlockedExchange(&r.seqIn, 0);
    InterlockedExchange(&r.seqOut, 0);
    r.qpcIn = Qpc(); r.qpcOut = 0; r.msg = m; r.wp = w; r.lp = l; r.tid = GetCurrentThreadId(); r.hwnd = h; r.result = 0;
    r.a0 = r.a1 = r.a2 = r.a3 = 0; r.a4 = 0; r.aux = false;
    if (m == WM_WINDOWPOSCHANGED && l && Readable(reinterpret_cast<const void*>(l), sizeof(WINDOWPOS))) {
        const WINDOWPOS* wp = reinterpret_cast<const WINDOWPOS*>(l);
        r.a0 = wp->x; r.a1 = wp->y; r.a2 = wp->cx; r.a3 = wp->cy; r.a4 = wp->flags; r.aux = true;
    } else if (m == WM_STYLECHANGED && l && Readable(reinterpret_cast<const void*>(l), sizeof(STYLESTRUCT))) {
        const STYLESTRUCT* ss = reinterpret_cast<const STYLESTRUCT*>(l);
        r.a0 = int(ss->styleOld); r.a1 = int(ss->styleNew); r.aux = true;
    }
    InterlockedExchange(&r.seqIn, seq);        // the entry is visible to the poller from here
    const LRESULT res = Chain(s, h, m, w, l);
    r.qpcOut = Qpc(); r.result = res;
    InterlockedExchange(&r.seqOut, seq);       // and now the return
    return res;
}

const char* SysCommandName(unsigned sc)
{
    switch (sc) {
    case SC_MINIMIZE: return "SC_MINIMIZE"; case SC_RESTORE: return "SC_RESTORE"; case SC_MAXIMIZE: return "SC_MAXIMIZE";
    case SC_CLOSE: return "SC_CLOSE"; case SC_MOVE: return "SC_MOVE"; case SC_SIZE: return "SC_SIZE";
    case SC_KEYMENU: return "SC_KEYMENU"; case SC_MOUSEMENU: return "SC_MOUSEMENU"; case SC_SCREENSAVE: return "SC_SCREENSAVE";
    case SC_MONITORPOWER: return "SC_MONITORPOWER"; case SC_TASKLIST: return "SC_TASKLIST"; default: return "SC_?";
    }
}
void DescribeMsg(const WndRec& r, char* out, std::size_t n)
{
    const unsigned long long wp = (unsigned long long)r.wp, lp = (unsigned long long)r.lp;
    switch (r.msg) {
    case WM_ACTIVATEAPP:
        std::snprintf(out, n, "WM_ACTIVATEAPP %s (other app's thread %llu)", wp ? "ACTIVATING" : "deactivating", lp); break;
    case WM_ACTIVATE: {
        const unsigned lo = LOWORD(r.wp);
        std::snprintf(out, n, "WM_ACTIVATE %s%s (other hwnd 0x%llX)",
                      lo == WA_INACTIVE ? "INACTIVE" : lo == WA_ACTIVE ? "ACTIVE" : lo == WA_CLICKACTIVE ? "CLICKACTIVE" : "?",
                      HIWORD(r.wp) ? " minimized" : "", lp); break; }
    case WM_NCACTIVATE:   std::snprintf(out, n, "WM_NCACTIVATE %s", wp ? "active" : "inactive"); break;
    case WM_SETFOCUS:     std::snprintf(out, n, "WM_SETFOCUS (from 0x%llX)", wp); break;
    case WM_KILLFOCUS:    std::snprintf(out, n, "WM_KILLFOCUS (to 0x%llX)", wp); break;
    case WM_SIZE: {
        static const char* kind[5] = { "RESTORED", "MINIMIZED", "MAXIMIZED", "MAXSHOW", "MAXHIDE" };
        std::snprintf(out, n, "WM_SIZE %s client %ux%u", wp <= 4 ? kind[wp] : "?", unsigned(LOWORD(r.lp)), unsigned(HIWORD(r.lp))); break; }
    case WM_MOVE:         std::snprintf(out, n, "WM_MOVE client origin %d,%d", int(short(LOWORD(r.lp))), int(short(HIWORD(r.lp)))); break;
    case WM_WINDOWPOSCHANGED:
        if (r.aux) std::snprintf(out, n, "WM_WINDOWPOSCHANGED x %d y %d cx %d cy %d flags 0x%X%s%s%s%s", r.a0, r.a1, r.a2, r.a3, r.a4,
                                 (r.a4 & SWP_NOSIZE) ? " NOSIZE" : "", (r.a4 & SWP_NOMOVE) ? " NOMOVE" : "",
                                 (r.a4 & SWP_SHOWWINDOW) ? " SHOWWINDOW" : "", (r.a4 & SWP_HIDEWINDOW) ? " HIDEWINDOW" : "");
        else std::snprintf(out, n, "WM_WINDOWPOSCHANGED (WINDOWPOS unreadable)");
        break;
    case WM_SHOWWINDOW:   std::snprintf(out, n, "WM_SHOWWINDOW %s (status %llu)", wp ? "shown" : "hidden", lp); break;
    case WM_SYSCOMMAND:   std::snprintf(out, n, "WM_SYSCOMMAND %s (0x%llX)", SysCommandName(unsigned(wp & 0xFFF0u)), wp); break;
    case WM_ENTERSIZEMOVE: std::snprintf(out, n, "WM_ENTERSIZEMOVE"); break;
    case WM_EXITSIZEMOVE:  std::snprintf(out, n, "WM_EXITSIZEMOVE"); break;
    case WM_DISPLAYCHANGE: std::snprintf(out, n, "WM_DISPLAYCHANGE %llu bpp, desktop now %ux%u", wp, unsigned(LOWORD(r.lp)), unsigned(HIWORD(r.lp))); break;
    case WM_MOUSEACTIVATE: std::snprintf(out, n, "WM_MOUSEACTIVATE (top-level 0x%llX, hit-test %d, mouse msg %u)", wp, int(short(LOWORD(r.lp))), unsigned(HIWORD(r.lp))); break;
    case WM_CAPTURECHANGED: std::snprintf(out, n, "WM_CAPTURECHANGED (capture to 0x%llX)", lp); break;
    case WM_DEVICECHANGE:  std::snprintf(out, n, "WM_DEVICECHANGE event 0x%llX", wp); break;
    case WM_POWERBROADCAST: std::snprintf(out, n, "WM_POWERBROADCAST event 0x%llX", wp); break;
    case WM_STYLECHANGED:
        if (r.aux) std::snprintf(out, n, "WM_STYLECHANGED GWL_%s 0x%08X -> 0x%08X", int(LONG_PTR(r.wp)) == GWL_EXSTYLE ? "EXSTYLE" : "STYLE", unsigned(r.a0), unsigned(r.a1));
        else std::snprintf(out, n, "WM_STYLECHANGED (STYLESTRUCT unreadable)");
        break;
    default:              std::snprintf(out, n, "msg 0x%X wp 0x%llX lp 0x%llX", r.msg, wp, lp); break;
    }
}

// ---- the drain (poller thread only) --------------------------------------------
long g_drained = 0;                       // the last entry logged
struct Pending { long seq; LONGLONG lastNagQpc; };
Pending g_pending[64]; int g_pendingN = 0;
double g_slowestMs = -1.0; long g_slowestSeq = 0; UINT g_slowestMsg = 0;
long g_lostToLap = 0;
// The running maximum is kept for every message; the tag is spent only on the
// slow ones (>= 50 ms), and the poller's state line carries the maximum.
void NoteDuration(const WndRec& r, long seq, double ms, char* tag, std::size_t n)
{
    tag[0] = 0;
    const bool slow = ms >= 50.0;
    const bool record = ms > g_slowestMs;
    if (record) { g_slowestMs = ms; g_slowestSeq = seq; g_slowestMsg = r.msg; }
    if (slow && record) std::snprintf(tag, n, " -- SLOW (>= 50 ms), the slowest so far");
    else if (slow)      std::snprintf(tag, n, " -- SLOW (>= 50 ms; slowest so far #%ld at %.1f ms)", g_slowestSeq, g_slowestMs);
}
void RemovePending(int i) { for (int j = i; j + 1 < g_pendingN; ++j) g_pending[j] = g_pending[j + 1]; --g_pendingN; }
void DrainRing()
{
    const long produced = InterlockedCompareExchange(&g_ringSeq, 0, 0);
    if (produced - g_drained > kRing) {
        const long lost = produced - g_drained - kRing;
        g_lostToLap += lost;
        LogF("[WND] the message ring lapped: %ld recorded message(s) were overwritten before this drain (%ld lost so far)", lost, g_lostToLap);
        g_drained = produced - kRing;
    }
    static LONGLONG unpublishedSince = 0;
    while (g_drained < produced) {
        const long seq = g_drained + 1;
        WndRec& r = g_ring[(seq - 1) & (kRing - 1)];
        const long in = InterlockedCompareExchange(&r.seqIn, 0, 0);
        if (in < seq) {
            // Reserved, not yet published: a microsecond window, or the owner
            // thread is stopped right there. Two seconds of it means the thread
            // died between the two stores; the entry is given up, not waited for.
            const LONGLONG now = Qpc();
            if (!unpublishedSince) { unpublishedSince = now; break; }
            if (QpcToMs(now - unpublishedSince) < 2000.0) break;
            LogF("[WND] #%ld was reserved by the owner thread but never written in 2 s -- skipped", seq);
            unpublishedSince = 0; ++g_drained; continue;
        }
        unpublishedSince = 0;
        if (in > seq) { ++g_drained; ++g_lostToLap; continue; }   // reused already
        // COPY, THEN RE-CHECK: the writer of seq+512 clears both sequence fields
        // before it rewrites the record, so a copy taken while it writes is
        // caught by re-reading them after the copy; a mismatch is a lap.
        const long out = InterlockedCompareExchange(&r.seqOut, 0, 0);
        const WndRec c = r;
        if (InterlockedCompareExchange(&r.seqIn, 0, 0) != seq || (out == seq && InterlockedCompareExchange(&r.seqOut, 0, 0) != seq)) {
            ++g_drained; ++g_lostToLap; continue;
        }
        char what[256]; DescribeMsg(c, what, sizeof what);
        char at[16]; WallStampOf(c.qpcIn, at, sizeof at);
        char where[48] = "";
        if (c.hwnd != GameHwnd()) std::snprintf(where, sizeof where, " on window 0x%llX", (unsigned long long)reinterpret_cast<std::uintptr_t>(c.hwnd));
        if (out == seq) {
            const double ms = QpcToMs(c.qpcOut - c.qpcIn);
            char tag[96]; NoteDuration(c, seq, ms, tag, sizeof tag);
            LogF("[WND] #%ld %s %s%s on thread %lu -> returned 0x%llX after %.2f ms%s",
                 seq, at, what, where, (unsigned long)c.tid, (unsigned long long)c.result, ms, tag);
        } else {
            LogF("[WND] #%ld %s %s%s on thread %lu -> entered (in progress: the chain below ours has not returned yet)",
                 seq, at, what, where, (unsigned long)c.tid);
            if (g_pendingN < 64) g_pending[g_pendingN++] = Pending{ seq, Qpc() };
            else LogF("[WND] #%ld: too many messages in progress to track its return", seq);
        }
        ++g_drained;
    }
    for (int i = 0; i < g_pendingN;) {
        const long seq = g_pending[i].seq;
        WndRec& r = g_ring[(seq - 1) & (kRing - 1)];
        if (InterlockedCompareExchange(&r.seqIn, 0, 0) != seq) {
            LogF("[WND] #%ld: the ring lapped before its return was seen -- the duration is lost", seq);
            RemovePending(i); continue;
        }
        if (InterlockedCompareExchange(&r.seqOut, 0, 0) == seq) {
            const WndRec c = r;    // copy, then re-check both sequences (see above)
            if (InterlockedCompareExchange(&r.seqIn, 0, 0) != seq || InterlockedCompareExchange(&r.seqOut, 0, 0) != seq) {
                LogF("[WND] #%ld: the ring lapped while its return was being read -- the duration is lost", seq);
                ++g_lostToLap; RemovePending(i); continue;
            }
            const double ms = QpcToMs(c.qpcOut - c.qpcIn);
            char what[256]; DescribeMsg(c, what, sizeof what);
            char tag[96]; NoteDuration(c, seq, ms, tag, sizeof tag);
            LogF("[WND] #%ld %s returned 0x%llX after %.1f ms (%.2f s) on thread %lu%s", seq, what, (unsigned long long)c.result, ms, ms / 1000.0, (unsigned long)c.tid, tag);
            RemovePending(i); continue;
        }
        const LONGLONG now = Qpc();
        if (QpcToMs(now - g_pending[i].lastNagQpc) >= 5000.0) {
            const WndRec c = r;
            if (InterlockedCompareExchange(&r.seqIn, 0, 0) == seq) {
                char what[256]; DescribeMsg(c, what, sizeof what);
                LogF("[WND] #%ld %s is STILL inside the chain below ours after %.1f s (thread %lu)", seq, what, QpcToMs(now - c.qpcIn) / 1000.0, (unsigned long)c.tid);
            }
            g_pending[i].lastNagQpc = now;
        }
        ++i;
    }
}

// ---- the subclass ---------------------------------------------------------------
// ONE INSTALL, FROM WHATEVER THREAD GETS THERE FIRST: the D3D probe on the
// owner thread (inside device creation), the heartbeat
// beat if the task thread owns the window, else the poller thread cross-thread
// (legal inside one process, and the only option when no FleshCore code ever
// runs on the owner thread). The predecessor is read with GetWindowLongPtr and
// published BEFORE the swap. The exe registers its class with RegisterClassA
// and creates it with CreateWindowExA (its import table has no W variants), so
// IsWindowUnicode is expected to say ANSI and the A pair is used; a W pair on
// an ANSI window would make USER32 thunk every text message.
bool InstallSubclass(HWND h, const char* how)
{
    if (!h || !IsWindow(h)) return false;
    if (InterlockedCompareExchange(&g_subclassed, 1, 0) != 0) return true;
    const bool uni = IsWindowUnicode(h) != FALSE;
    const LONG_PTR before = uni ? GetWindowLongPtrW(h, GWLP_WNDPROC) : GetWindowLongPtrA(h, GWLP_WNDPROC);
    if (!before) {
        InterlockedExchange(&g_subclassed, 0);
        LogF("[WND] GetWindowLongPtr%c(GWLP_WNDPROC) on 0x%llX failed (%lu) -- no subclass this time", uni ? 'W' : 'A', (unsigned long long)reinterpret_cast<std::uintptr_t>(h), GetLastError());
        return false;
    }
    // A window already held (re-found after the swap chain's window died, or
    // named twice): DiagWndProc is still in its chain -- 'before' is &DiagWndProc
    // when the charset matched, a USER32 thunk handle when it did not, which is
    // why the record lookup decides too. NEVER chain to itself.
    if (before == reinterpret_cast<LONG_PTR>(&DiagWndProc) || FindSub(h)) {
        const DWORD owner = GetWindowThreadProcessId(h, nullptr);
        g_subclassOwner = owner;
        InterlockedExchange(&g_wndThread, long(owner));
        LogF("[WND] 0x%llX already carries our subclass (%s) -- reused, not re-installed", (unsigned long long)reinterpret_cast<std::uintptr_t>(h), how);
        return true;
    }
    const long n = InterlockedCompareExchange(&g_subN, 0, 0);
    if (n >= kSubMax) {
        InterlockedExchange(&g_subclassed, 0);
        static bool said = false;   // the poller retries every 5 s; say it once
        if (!said) { said = true; LogF("[WND] %ld windows subclassed already -- 0x%llX is left alone (no window-message log for it)", n, (unsigned long long)reinterpret_cast<std::uintptr_t>(h)); }
        return false;
    }
    g_sub[n].prev = reinterpret_cast<WNDPROC>(before); g_sub[n].unicode = uni; g_sub[n].h = h;
    InterlockedExchange(&g_subN, n + 1);                 // the record is visible BEFORE the swap
    const LONG_PTR ours = reinterpret_cast<LONG_PTR>(&DiagWndProc);
    const LONG_PTR prev = uni ? SetWindowLongPtrW(h, GWLP_WNDPROC, ours) : SetWindowLongPtrA(h, GWLP_WNDPROC, ours);
    if (!prev) {
        // The swap failed, so no message can hold this record: take it back.
        g_sub[n].h = nullptr; InterlockedExchange(&g_subN, n);
        InterlockedExchange(&g_subclassed, 0);
        LogF("[WND] SetWindowLongPtr%c(GWLP_WNDPROC) on 0x%llX failed (%lu) -- no window-message log this session", uni ? 'W' : 'A', (unsigned long long)reinterpret_cast<std::uintptr_t>(h), GetLastError());
        return false;
    }
    if (prev != before) g_sub[n].prev = reinterpret_cast<WNDPROC>(prev);   // a subclass landed in the gap: chain to the real predecessor (the one post-publication write, see SubRec)
    const DWORD owner = GetWindowThreadProcessId(h, nullptr);
    g_subclassOwner = owner;
    InterlockedExchange(&g_wndThread, long(owner));
    char who[80]; FormatAddr(std::uintptr_t(prev), false, who, sizeof who);
    // The engine's own WindowProc is at exe+0x64C880 on 1.6.1170 (as published by another plugin)
    // -- compared and logged, never relied on.
    const bool isEngine = g_env.exeBase && std::uintptr_t(prev) == g_env.exeBase + 0x64C880u;
    RECT wr{}, cr{}; GetWindowRect(h, &wr); GetClientRect(h, &cr);
    LogF("[WND] subclassed 0x%llX %s: owner thread %lu, this thread %lu, %s window; predecessor 0x%llX = %s (%s). Installed as soon as the"
         " window existed, so every subclass another plugin installs later sits ABOVE ours:"
         " the chained duration measures the predecessor and everything below it, not the plugin procs above -- the sampler covers those."
         " Window %ldx%ld at %ld,%ld, client %ldx%ld, style 0x%08lX ex 0x%08lX, iconic %d, foreground %s",
         (unsigned long long)reinterpret_cast<std::uintptr_t>(h), how, (unsigned long)owner, (unsigned long)GetCurrentThreadId(),
         uni ? "Unicode" : "ANSI", (unsigned long long)prev, who,
         isEngine ? "the engine's own WindowProc, exe+0x64C880" : "another subclass above the engine's WindowProc, or a USER32 thunk handle",
         long(wr.right - wr.left), long(wr.bottom - wr.top), long(wr.left), long(wr.top), long(cr.right), long(cr.bottom),
         (unsigned long)GetWindowLongPtrA(h, GWL_STYLE), (unsigned long)GetWindowLongPtrA(h, GWL_EXSTYLE),
         IsIconic(h) ? 1 : 0, GetForegroundWindow() == h ? "yes" : "NO");
    return true;
}

// ---- finding the window ----------------------------------------------------------
// NOTHING HANDS OVER THE HWND. PrismaUI finds it itself and exports no accessor;
// facts.h has no window offset. Best source: the swap-chain description the
// D3D probe sees (OutputWindow). Else the class the exe registers,
// 'Skyrim Special Edition' (ASCII at RVA 0x1892F80), else any top-level
// window of this process (visible, or of that class). A pid check follows
// every answer: two Skyrims on one desktop must not subclass each other.
BOOL CALLBACK EnumTopLevel(HWND h, LPARAM out)
{
    DWORD pid = 0; GetWindowThreadProcessId(h, &pid);
    if (pid != GetCurrentProcessId() || GetWindow(h, GW_OWNER) != nullptr) return TRUE;
    char cls[64] = {}; GetClassNameA(h, cls, sizeof cls);
    if (std::strcmp(cls, "Skyrim Special Edition") != 0 && !IsWindowVisible(h)) return TRUE;
    *reinterpret_cast<HWND*>(out) = h;
    return FALSE;
}
HWND FindGameWindow(const char** how)
{
    HWND h = GameHwnd();
    if (h && IsWindow(h)) { *how = "already known"; return h; }
    *how = "FindWindowA(class 'Skyrim Special Edition')";
    h = FindWindowA("Skyrim Special Edition", nullptr);
    if (h) { DWORD pid = 0; GetWindowThreadProcessId(h, &pid); if (pid != GetCurrentProcessId()) h = nullptr; }
    if (!h) { *how = "EnumWindows (a top-level window of this process)"; EnumWindows(EnumTopLevel, reinterpret_cast<LPARAM>(&h)); }
    if (h) { DWORD pid = 0; GetWindowThreadProcessId(h, &pid); if (pid != GetCurrentProcessId()) h = nullptr; }
    if (!h) { *how = "nothing"; return nullptr; }
    SetGameHwnd(h, *how);
    InterlockedExchange(&g_wndThread, long(GetWindowThreadProcessId(h, nullptr)));
    return h;
}

// ======================================================================= (1b) THE SWAP-CHAIN PROBE
// THE ALT-TAB PATH. A long stall after an Alt-Tab can be a swap-chain resize:
// the engine re-creates its render targets (BSShaderRenderTargets::Create)
// and a d3d11 proxy such as ENB may rebuild its shader cache, and none of
// that passes through D3D11CreateDeviceAndSwapChain.
// So the IDXGISwapChain the game is handed -- ENB's proxy, or DXGI's -- gets
// four of its vtable slots timed: Present (8), SetFullscreenState (10),
// ResizeBuffers (13), ResizeTarget (14). SSE Display Tweaks patches the same
// slots; whoever writes later wraps the other, and both chain, so the order
// does not matter. Present is on the frame path: it records its thread once
// (THE renderer's thread, which the sampler then walks) and speaks only when
// a single call exceeds a second.
using FnPresent            = HRESULT (STDMETHODCALLTYPE*)(IDXGISwapChain*, UINT, UINT);
using FnSetFullscreenState = HRESULT (STDMETHODCALLTYPE*)(IDXGISwapChain*, BOOL, IDXGIOutput*);
using FnResizeBuffers      = HRESULT (STDMETHODCALLTYPE*)(IDXGISwapChain*, UINT, UINT, UINT, DXGI_FORMAT, UINT);
using FnResizeTarget       = HRESULT (STDMETHODCALLTYPE*)(IDXGISwapChain*, const DXGI_MODE_DESC*);
FnPresent            g_origPresent            = nullptr;
FnSetFullscreenState g_origSetFullscreenState = nullptr;
FnResizeBuffers      g_origResizeBuffers      = nullptr;
FnResizeTarget       g_origResizeTarget       = nullptr;
void**               g_scVtable               = nullptr;
volatile long        g_scArmed                = 0;   // the one vtable this process may patch has been claimed (set BEFORE patching)
volatile long        g_scSlots                = 0;   // how many of the four slots actually hold a probe (set AFTER patching: the actual count)
volatile long        g_presentCalls           = 0;
volatile long        g_resizeCalls            = 0;

const char* DxgiFormatName(unsigned f)
{
    switch (f) {
    case DXGI_FORMAT_UNKNOWN: return "UNKNOWN"; case DXGI_FORMAT_R8G8B8A8_UNORM: return "R8G8B8A8_UNORM";
    case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB: return "R8G8B8A8_UNORM_SRGB"; case DXGI_FORMAT_B8G8R8A8_UNORM: return "B8G8R8A8_UNORM";
    case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB: return "B8G8R8A8_UNORM_SRGB"; case DXGI_FORMAT_R10G10B10A2_UNORM: return "R10G10B10A2_UNORM";
    case DXGI_FORMAT_R16G16B16A16_FLOAT: return "R16G16B16A16_FLOAT"; default: return "?";
    }
}
const char* SwapEffectName(unsigned e)
{
    switch (e) {
    case DXGI_SWAP_EFFECT_DISCARD: return "DISCARD"; case DXGI_SWAP_EFFECT_SEQUENTIAL: return "SEQUENTIAL";
    case DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL: return "FLIP_SEQUENTIAL"; case DXGI_SWAP_EFFECT_FLIP_DISCARD: return "FLIP_DISCARD"; default: return "?";
    }
}
const char* DriverTypeName(int d)
{
    switch (d) {
    case D3D_DRIVER_TYPE_HARDWARE: return "HARDWARE"; case D3D_DRIVER_TYPE_REFERENCE: return "REFERENCE"; case D3D_DRIVER_TYPE_NULL: return "NULL";
    case D3D_DRIVER_TYPE_SOFTWARE: return "SOFTWARE"; case D3D_DRIVER_TYPE_WARP: return "WARP"; case D3D_DRIVER_TYPE_UNKNOWN: return "UNKNOWN"; default: return "?";
    }
}
HRESULT STDMETHODCALLTYPE ProbePresent(IDXGISwapChain* self, UINT sync, UINT flags)
{
    if (InterlockedCompareExchange(&g_presentThread, long(GetCurrentThreadId()), 0) == 0)
        LogF("[DXGI] Present runs on thread %lu -- the renderer's thread; the stall sampler walks it from now on",
             (unsigned long)GetCurrentThreadId());
    InterlockedIncrement(&g_presentCalls);
    const LONGLONG q0 = Qpc();
    const HRESULT hr = g_origPresent(self, sync, flags);
    const double ms = QpcToMs(Qpc() - q0);
    if (ms >= 1000.0)
        LogF("[DXGI] Present(sync %u, flags 0x%X) took %.1f ms (%.2f s), hr 0x%08lX, on thread %lu -- a frame that long IS the stall",
             sync, flags, ms, ms / 1000.0, (unsigned long)hr, (unsigned long)GetCurrentThreadId());
    return hr;
}
HRESULT STDMETHODCALLTYPE ProbeSetFullscreenState(IDXGISwapChain* self, BOOL fs, IDXGIOutput* target)
{
    const long call = InterlockedIncrement(&g_resizeCalls);
    const DWORD tid = GetCurrentThreadId();
    LogF("[DXGI] #%ld SetFullscreenState(%s, target 0x%llX) BEGINS on thread %lu", call, fs ? "FULLSCREEN" : "windowed", (unsigned long long)reinterpret_cast<std::uintptr_t>(target), (unsigned long)tid);
    const LONGLONG q0 = Qpc();
    const HRESULT hr = g_origSetFullscreenState(self, fs, target);
    const double ms = QpcToMs(Qpc() - q0);
    LogF("[DXGI] #%ld SetFullscreenState RETURNED hr 0x%08lX after %.1f ms (%.2f s) on thread %lu", call, (unsigned long)hr, ms, ms / 1000.0, (unsigned long)tid);
    ProfF("[DXGI] #%ld SetFullscreenState(%s) %.1f ms hr 0x%08lX thread %lu", call, fs ? "FULLSCREEN" : "windowed", ms, (unsigned long)hr, (unsigned long)tid);
    return hr;
}
HRESULT STDMETHODCALLTYPE ProbeResizeBuffers(IDXGISwapChain* self, UINT count, UINT w, UINT h, DXGI_FORMAT fmt, UINT flags)
{
    const long call = InterlockedIncrement(&g_resizeCalls);
    const DWORD tid = GetCurrentThreadId();
    LogF("[DXGI] #%ld ResizeBuffers(%u buffer(s), %ux%u, format %u %s, flags 0x%X) BEGINS on thread %lu -- the render targets are about to be re-created",
         call, count, w, h, unsigned(fmt), DxgiFormatName(unsigned(fmt)), flags, (unsigned long)tid);
    const LONGLONG q0 = Qpc();
    const HRESULT hr = g_origResizeBuffers(self, count, w, h, fmt, flags);
    const double ms = QpcToMs(Qpc() - q0);
    LogF("[DXGI] #%ld ResizeBuffers RETURNED hr 0x%08lX after %.1f ms (%.2f s) on thread %lu", call, (unsigned long)hr, ms, ms / 1000.0, (unsigned long)tid);
    ProfF("[DXGI] #%ld ResizeBuffers(%ux%u) %.1f ms hr 0x%08lX thread %lu", call, w, h, ms, (unsigned long)hr, (unsigned long)tid);
    return hr;
}
HRESULT STDMETHODCALLTYPE ProbeResizeTarget(IDXGISwapChain* self, const DXGI_MODE_DESC* mode)
{
    const long call = InterlockedIncrement(&g_resizeCalls);
    const DWORD tid = GetCurrentThreadId();
    if (mode && Readable(mode, sizeof *mode))
        LogF("[DXGI] #%ld ResizeTarget(%ux%u @ %u/%u Hz, format %u %s) BEGINS on thread %lu", call, mode->Width, mode->Height,
             mode->RefreshRate.Numerator, mode->RefreshRate.Denominator, unsigned(mode->Format), DxgiFormatName(unsigned(mode->Format)), (unsigned long)tid);
    else
        LogF("[DXGI] #%ld ResizeTarget(null or unreadable DXGI_MODE_DESC) BEGINS on thread %lu", call, (unsigned long)tid);
    const LONGLONG q0 = Qpc();
    const HRESULT hr = g_origResizeTarget(self, mode);
    const double ms = QpcToMs(Qpc() - q0);
    LogF("[DXGI] #%ld ResizeTarget RETURNED hr 0x%08lX after %.1f ms (%.2f s) on thread %lu", call, (unsigned long)hr, ms, ms / 1000.0, (unsigned long)tid);
    ProfF("[DXGI] #%ld ResizeTarget %.1f ms hr 0x%08lX thread %lu", call, ms, (unsigned long)hr, (unsigned long)tid);
    return hr;
}
// The original goes into ITS global BEFORE the probe goes into the slot: a
// call arriving in between must find something to chain to.
bool PatchSlot(void** slot, void* probe, void* origGlobal)
{
    DWORD old = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old)) return false;
    std::memcpy(origGlobal, slot, sizeof(void*));
    *slot = probe;
    DWORD dummy = 0; VirtualProtect(slot, sizeof(void*), old, &dummy);
    return true;
}
void InstallSwapChainProbe(IDXGISwapChain* sc)
{
    if (!sc || !Readable(sc, sizeof(void*))) { LogF("[DXGI] the returned swap chain pointer 0x%llX is unreadable -- no swap-chain probe", (unsigned long long)reinterpret_cast<std::uintptr_t>(sc)); return; }
    void** vt = *reinterpret_cast<void***>(sc);
    if (!vt || !Readable(vt, 15 * sizeof(void*))) { LogF("[DXGI] swap chain vtable 0x%llX unreadable -- no swap-chain probe", (unsigned long long)reinterpret_cast<std::uintptr_t>(vt)); return; }
    if (InterlockedCompareExchange(&g_scArmed, 1, 0) != 0) {
        if (vt != g_scVtable)
            LogF("[DXGI] a swap chain with a DIFFERENT vtable (0x%llX, the probe sits on 0x%llX) -- not patched: one swap-chain probe per session",
                 (unsigned long long)reinterpret_cast<std::uintptr_t>(vt), (unsigned long long)reinterpret_cast<std::uintptr_t>(g_scVtable));
        return;
    }
    char presentWas[80], resizeWas[80], vtOwner[80];
    FormatAddr(reinterpret_cast<std::uintptr_t>(vt[8]), false, presentWas, sizeof presentWas);
    FormatAddr(reinterpret_cast<std::uintptr_t>(vt[13]), false, resizeWas, sizeof resizeWas);
    FormatAddr(reinterpret_cast<std::uintptr_t>(vt), false, vtOwner, sizeof vtOwner);
    long slots = 0;
    bool ok = PatchSlot(vt + 8, reinterpret_cast<void*>(&ProbePresent), &g_origPresent);                         if (ok) ++slots;
    if (ok) { ok = PatchSlot(vt + 10, reinterpret_cast<void*>(&ProbeSetFullscreenState), &g_origSetFullscreenState); if (ok) ++slots; }
    if (ok) { ok = PatchSlot(vt + 13, reinterpret_cast<void*>(&ProbeResizeBuffers), &g_origResizeBuffers);           if (ok) ++slots; }
    if (ok) { ok = PatchSlot(vt + 14, reinterpret_cast<void*>(&ProbeResizeTarget), &g_origResizeTarget);             if (ok) ++slots; }
    g_scVtable = vt;
    InterlockedExchange(&g_scSlots, slots);   // the actual count, after the fact: OnInputLoaded reports this count, not the claim
    if (!ok) {
        // Whatever was patched before the failure stays patched (each probe
        // chains to a saved original); the arm line says how far it got.
        LogF("[DXGI] VirtualProtect on the swap chain vtable failed (%lu) part-way (%ld of 4 slots hold a probe): Present %s, SetFullscreenState %s, ResizeBuffers %s, ResizeTarget %s",
             GetLastError(), slots, g_origPresent ? "armed" : "NOT armed", g_origSetFullscreenState ? "armed" : "NOT armed",
             g_origResizeBuffers ? "armed" : "NOT armed", g_origResizeTarget ? "armed" : "NOT armed");
        return;
    }
    LogF("[DXGI] swap-chain probe armed on vtable %s (0x%llX) of the IDXGISwapChain the game holds (0x%llX): Present was %s, ResizeBuffers was %s;"
         " Present (thread id once, >= 1 s calls), SetFullscreenState, ResizeBuffers and ResizeTarget are timed. SSE Display Tweaks patches"
         " the same slots -- whoever wrote later wraps the other and both chain",
         vtOwner, (unsigned long long)reinterpret_cast<std::uintptr_t>(vt), (unsigned long long)reinterpret_cast<std::uintptr_t>(sc), presentWas, resizeWas);
}

// ======================================================================= (1) THE DEVICE-CREATION PROBE
// THE GAP NOBODY TIMES. Between another plugin's own hook
// on D3D11CreateDeviceAndSwapChain and a later plugin's post-init line, start-up
// can lose a minute and a half: the device, the swap chain, a d3d11.dll proxy, any upscaler
// and the driver
// all live in that gap, and no log times it. SkyrimSE.exe imports the function
// BY NAME from d3d11.dll (IAT slot RVA 0x017502A0 on 1.6.1170), so the same
// by-name walk that hooks the file APIs finds it. A plugin can write that slot
// BEFORE FleshCore's SKSEPlugin_Load, and then what the probe saves and
// chains to is ITS hook; and SSE Display Tweaks hooks the call site (it has no
// 'd3d11.dll' string), so the chain can run SDT -> thunk -> [slot] = this probe -> that hook ->
// a d3d11.dll proxy. The DXGI_SWAP_CHAIN_DESC logged is the one the probe sees, i.e.
// after SDT's edits.
using FnD3D11CreateDeviceAndSwapChain = HRESULT (WINAPI*)(IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL*, UINT, UINT,
                                                          const DXGI_SWAP_CHAIN_DESC*, IDXGISwapChain**, ID3D11Device**, D3D_FEATURE_LEVEL*, ID3D11DeviceContext**);
FnD3D11CreateDeviceAndSwapChain g_chainCreate   = nullptr;
ULONGLONG*                      g_d3dSlot       = nullptr;   // SkyrimSE.exe's IAT slot
ULONGLONG                       g_slotWritten   = 0;         // what the probe wrote (the probe itself)
ULONGLONG                       g_slotLastSeen  = 0;         // what the last RecheckIatSlot saw
volatile long                   g_d3dCalls      = 0;

HRESULT WINAPI ProbeD3D11CreateDeviceAndSwapChain(IDXGIAdapter* adapter, D3D_DRIVER_TYPE driverType, HMODULE software, UINT flags,
                                                   const D3D_FEATURE_LEVEL* levels, UINT nLevels, UINT sdk, const DXGI_SWAP_CHAIN_DESC* scd,
                                                   IDXGISwapChain** swapChain, ID3D11Device** device, D3D_FEATURE_LEVEL* levelOut, ID3D11DeviceContext** context)
{
    const long  call = InterlockedIncrement(&g_d3dCalls);
    const DWORD tid  = GetCurrentThreadId();
    InterlockedCompareExchange(&g_d3dInitThread, long(tid), 0);
    char t0s[16]; WallStampNow(t0s, sizeof t0s);
    const LONGLONG q0 = Qpc();
    char desc[400]; std::snprintf(desc, sizeof desc, "no DXGI_SWAP_CHAIN_DESC (null or unreadable)");
    HWND hwnd = nullptr;
    if (scd && Readable(scd, sizeof *scd)) {
        hwnd = scd->OutputWindow;
        std::snprintf(desc, sizeof desc,
                      "OutputWindow 0x%llX, Windowed %d, BufferDesc %ux%u format %u (%s) @ %u/%u Hz, SampleDesc %u/%u, BufferUsage 0x%X, BufferCount %u, SwapEffect %u (%s), Flags 0x%X",
                      (unsigned long long)reinterpret_cast<std::uintptr_t>(hwnd), int(scd->Windowed), scd->BufferDesc.Width, scd->BufferDesc.Height,
                      unsigned(scd->BufferDesc.Format), DxgiFormatName(unsigned(scd->BufferDesc.Format)),
                      scd->BufferDesc.RefreshRate.Numerator, scd->BufferDesc.RefreshRate.Denominator,
                      scd->SampleDesc.Count, scd->SampleDesc.Quality, unsigned(scd->BufferUsage), scd->BufferCount,
                      unsigned(scd->SwapEffect), SwapEffectName(unsigned(scd->SwapEffect)), unsigned(scd->Flags));
    }
    const int firstLevel = (levels && nLevels && Readable(levels, sizeof *levels)) ? int(levels[0]) : -1;
    char chainName[80]; FormatAddr(reinterpret_cast<std::uintptr_t>(g_chainCreate), false, chainName, sizeof chainName);
    LogF("[D3D] D3D11CreateDeviceAndSwapChain call #%ld BEGINS at %s on thread %lu: pAdapter 0x%llX, DriverType %d (%s), Flags 0x%X, %u feature level(s) first 0x%X, SDK %u; %s; chaining to %s",
         call, t0s, (unsigned long)tid, (unsigned long long)reinterpret_cast<std::uintptr_t>(adapter), int(driverType), DriverTypeName(int(driverType)), flags,
         nLevels, unsigned(firstLevel), sdk, desc, chainName);
    ProfF("[D3D] device creation #%ld BEGINS at %s on thread %lu: %s", call, t0s, (unsigned long)tid, desc);
    (void)software;
    if (hwnd) {
        SetGameHwnd(hwnd, "the swap chain's OutputWindow");
        const DWORD owner = GetWindowThreadProcessId(hwnd, nullptr);
        InterlockedExchange(&g_wndThread, long(owner));
        if (owner == tid) InstallSubclass(hwnd, "from the D3D probe, on the window's own thread");
        else LogF("[WND] the swap chain's window 0x%llX belongs to thread %lu, not this one (%lu) -- the poller will subclass it cross-thread",
                  (unsigned long long)reinterpret_cast<std::uintptr_t>(hwnd), (unsigned long)owner, (unsigned long)tid);
    }
    HRESULT hr = E_FAIL;
    if (g_chainCreate) hr = g_chainCreate(adapter, driverType, software, flags, levels, nLevels, sdk, scd, swapChain, device, levelOut, context);
    else LogF("[D3D] nothing to chain to (the slot held 0 at install) -- returning E_FAIL");
    const double ms = QpcToMs(Qpc() - q0);
    char t1s[16]; WallStampNow(t1s, sizeof t1s);
    const int levelGot = (levelOut && Readable(levelOut, sizeof *levelOut)) ? int(*levelOut) : -1;
    const std::uintptr_t dev = (device && Readable(device, sizeof *device)) ? reinterpret_cast<std::uintptr_t>(*device) : 0;
    const std::uintptr_t sc  = (swapChain && Readable(swapChain, sizeof *swapChain)) ? reinterpret_cast<std::uintptr_t>(*swapChain) : 0;
    const std::uintptr_t ctx = (context && Readable(context, sizeof *context)) ? reinterpret_cast<std::uintptr_t>(*context) : 0;
    LogF("[D3D] call #%ld RETURNED hr 0x%08lX, feature level 0x%X, after %.1f ms (%.2f s): %s -> %s on thread %lu; device 0x%llX, swap chain 0x%llX, context 0x%llX",
         call, (unsigned long)hr, unsigned(levelGot), ms, ms / 1000.0, t0s, t1s, (unsigned long)tid,
         (unsigned long long)dev, (unsigned long long)sc, (unsigned long long)ctx);
    ProfF("[D3D] device creation #%ld RETURNED hr 0x%08lX after %.1f ms (%.2f s): %s -> %s -- device creation itself, measured directly",
          call, (unsigned long)hr, ms, ms / 1000.0, t0s, t1s);
    if (SUCCEEDED(hr) && sc) InstallSwapChainProbe(reinterpret_cast<IDXGISwapChain*>(sc));
    return hr;
}
void InstallD3dProbe()
{
    if (!g_env.exeBase) { LogF("[D3D] no exe base -- the device-creation probe is off"); return; }
    ImageView v; v.base = reinterpret_cast<const std::uint8_t*>(g_env.exeBase); v.fileLayout = false;
    const std::uint32_t rva = FindIatSlotRva(v, "d3d11.dll", "D3D11CreateDeviceAndSwapChain");
    const std::uint32_t dxgiRva = FindIatSlotRva(v, "dxgi.dll", "CreateDXGIFactory");   // logged as a cross-check, not hooked
    if (!rva) { LogF("[D3D] SkyrimSE.exe does not import d3d11!D3D11CreateDeviceAndSwapChain by name -- the device-creation probe is off"); return; }
    ULONGLONG* slot = reinterpret_cast<ULONGLONG*>(g_env.exeBase + rva);
    ULONGLONG cur = *slot;
    DWORD oldProt = 0;
    if (!VirtualProtect(slot, sizeof(ULONGLONG), PAGE_READWRITE, &oldProt)) { LogF("[D3D] VirtualProtect on the IAT slot failed (%lu) -- the device-creation probe is off", GetLastError()); return; }
    // WRITTEN WITH A COMPARE-EXCHANGE, NOT BLIND. Another plugin may write the
    // slot between this read and this write (another plugin can write it just before
    // SKSEPlugin_Load; a plugin loading alongside could land in
    // the gap), and a blind store would chain the probe to a hook the slot no longer
    // holds while silently dropping theirs. The chain target is published
    // before each attempt, so a call arriving right after the swap finds it;
    // one retry against the new value, then the probe stays off and says so.
    const ULONGLONG ours = reinterpret_cast<ULONGLONG>(&ProbeD3D11CreateDeviceAndSwapChain);
    bool armed = false;
    for (int attempt = 0; attempt < 2 && !armed; ++attempt) {
        std::memcpy(&g_chainCreate, &cur, sizeof cur);
        const ULONGLONG seen = ULONGLONG(InterlockedCompareExchange64(reinterpret_cast<volatile LONGLONG*>(slot), LONGLONG(ours), LONGLONG(cur)));
        if (seen == cur) { armed = true; break; }
        char nowWho[80]; FormatAddr(std::uintptr_t(seen), false, nowWho, sizeof nowWho);
        LogF("[D3D] the IAT slot changed under us while arming: 0x%llX became 0x%llX (%s) -- %s", (unsigned long long)cur, (unsigned long long)seen, nowWho,
             attempt == 0 ? "retrying against the new value" : "giving up: the device-creation probe is off");
        cur = seen;
    }
    DWORD dummy = 0; VirtualProtect(slot, sizeof(ULONGLONG), oldProt, &dummy);
    if (!armed) { g_chainCreate = nullptr; return; }
    char who[80]; FormatAddr(std::uintptr_t(cur), false, who, sizeof who);
    g_d3dSlot = slot; g_slotWritten = ours; g_slotLastSeen = ours;
    char whoMod[48]; std::uintptr_t whoRva = 0; NameAddrSys(std::uintptr_t(cur), whoMod, sizeof whoMod, &whoRva);
    char dxgiText[48];
    if (dxgiRva) std::snprintf(dxgiText, sizeof dxgiText, "at 0x%X", dxgiRva); else std::snprintf(dxgiText, sizeof dxgiText, "not imported by name");
    LogF("[D3D] device-creation probe armed in SkyrimSE.exe's IAT slot for d3d11!D3D11CreateDeviceAndSwapChain at RVA 0x%X (%s 0x17502A0 parsed from the 1.6.1170 image;"
         " dxgi!CreateDXGIFactory %s); the slot held 0x%llX = %s (%s) and the probe now sits in front of it",
         rva, rva == 0x17502A0u ? "matches" : "DIFFERS FROM", dxgiText, (unsigned long long)cur, who,
         _stricmp(whoMod, "d3d11.dll") == 0 ? "a d3d11.dll export: no earlier hook" : "another plugin's hook, chained to");
}

// ======================================================================= (3) THE STALL STACK SAMPLER
// THE FUNCTION TABLE, READ FROM THE IMAGE ITSELF. An image's .pdata
// (IMAGE_DIRECTORY_ENTRY_EXCEPTION) is a sorted array of RUNTIME_FUNCTION; a
// binary search over it is what RtlLookupFunctionEntry does underneath, minus
// ntdll's inverted-function-table lock, which a thread stopped inside
// LoadLibrary may hold exclusive. Every read goes through DefaultReadable: an
// UNCACHED VirtualQuery, because flesh.cpp's Readable is a per-thread cache that
// only ForgetMemory (never called on the poller) invalidates, and a stack region
// remembered as committed stays 'readable' after its thread has exited.
PRUNTIME_FUNCTION PeFunctionEntry(std::uintptr_t pc, std::uintptr_t* imageBase)
{
    *imageBase = 0;
    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(reinterpret_cast<const void*>(pc), &mbi, sizeof mbi) != sizeof mbi || mbi.Type != MEM_IMAGE || !mbi.AllocationBase) return nullptr;
    const auto base = reinterpret_cast<std::uintptr_t>(mbi.AllocationBase);
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (!DefaultReadable(dos, sizeof(IMAGE_DOS_HEADER)) || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0) return nullptr;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + std::uint32_t(dos->e_lfanew));
    if (!DefaultReadable(nt, sizeof(IMAGE_NT_HEADERS64)) || nt->Signature != IMAGE_NT_SIGNATURE) return nullptr;
    *imageBase = base;
    const IMAGE_DATA_DIRECTORY& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION];
    if (!dir.VirtualAddress || dir.Size < sizeof(RUNTIME_FUNCTION)) return nullptr;
    const auto* tab = reinterpret_cast<const RUNTIME_FUNCTION*>(base + dir.VirtualAddress);
    std::size_t lo = 0, hi = dir.Size / sizeof(RUNTIME_FUNCTION);
    if (!DefaultReadable(tab, hi * sizeof(RUNTIME_FUNCTION))) return nullptr;
    const DWORD rva = DWORD(pc - base);
    while (lo < hi) {
        const std::size_t mid = (lo + hi) / 2;
        if (rva < tab[mid].BeginAddress) hi = mid;
        else if (rva >= tab[mid].EndAddress) lo = mid + 1;
        else return const_cast<PRUNTIME_FUNCTION>(&tab[mid]);
    }
    return nullptr;
}
// ONE STACK, TAKEN WHILE THE THREAD IS STOPPED. System calls, image reads and
// RtlVirtualUnwind (which only computes): no lock, no heap, no log in here --
// and no flesh.cpp Readable either: the guard for the raw [Rsp] read must be
// the truth NOW (an uncached VirtualQuery), not what this thread remembered.
int WalkSuspended(CONTEXT& ctx, std::uintptr_t* pcs, int maxFrames)
{
    int n = 0;
    while (n < maxFrames && ctx.Rip) {
        pcs[n++] = std::uintptr_t(ctx.Rip);
        const DWORD64 rspBefore = ctx.Rsp;
        if (!DefaultReadable(reinterpret_cast<const void*>(ctx.Rsp), 8)) break;
        std::uintptr_t base = 0;
        PRUNTIME_FUNCTION rf = PeFunctionEntry(std::uintptr_t(ctx.Rip), &base);
        if (rf && g_rtlVirtualUnwind) {
            PVOID handlerData = nullptr; DWORD64 establisher = 0;
            g_rtlVirtualUnwind(UNW_FLAG_NHANDLER, base, ctx.Rip, rf, &ctx, &handlerData, &establisher, nullptr);
        } else {
            // A leaf, or code no image owns (Ultralight's JIT in PrismaUI): the return address is at [Rsp].
            ctx.Rip = *reinterpret_cast<const DWORD64*>(ctx.Rsp);
            ctx.Rsp += 8;
        }
        if (ctx.Rsp <= rspBefore) break;   // no progress: a frame the unwinder could not read
    }
    return n;
}
// The thread's CPU clock and its delta since the previous sample of the same
// thread: a stuck thread BURNING cpu (a shader compile, a spin) and one BLOCKED
// (a wait, a lock) read the same to the heartbeat and differently here.
struct ThreadClock { DWORD tid; ULONGLONG kernel100ns, user100ns; };
ThreadClock g_clocks[8]; int g_clockN = 0;
void CpuDelta(DWORD tid, ULONGLONG k, ULONGLONG u, double* dk, double* du)
{
    *dk = *du = 0.0;
    for (int i = 0; i < g_clockN; ++i) if (g_clocks[i].tid == tid) {
        *dk = double(k - g_clocks[i].kernel100ns) / 10000.0; *du = double(u - g_clocks[i].user100ns) / 10000.0;
        g_clocks[i].kernel100ns = k; g_clocks[i].user100ns = u; return;
    }
    if (g_clockN < 8) g_clocks[g_clockN++] = ThreadClock{ tid, k, u };
}
std::uintptr_t g_pcs[32];   // poller thread only
volatile long g_walksThisStall = 0;    // poller increments, the ticker's OnRecovered reads and zeroes: Interlocked both ways

// Suspend, capture, walk, RESUME -- and only then name anything or write anything.
// compact = the 10 s sweep: four frames, one line per thread in both logs.
// idSlot = the global the id came from (one of this file's own), so a stale id is forgotten and
// never tried again; nullptr for flesh.cpp's ids and the sweep's.
void SampleOneThread(DWORD tid, const char* role, DWORD ageMs, int maxFrames, bool compact, volatile long* idSlot)
{
    if (!tid || tid == GetCurrentThreadId()) return;
    HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, tid);
    if (!h) {
        const DWORD err = GetLastError();
        if (idSlot) InterlockedCompareExchange(idSlot, 0, long(tid));
        if (!compact) LogF("[STALL] thread %lu (%s): OpenThread failed (%lu) -- it has exited, or it never was ours%s", (unsigned long)tid, role, err, idSlot ? "; the id is forgotten" : "");
        return;
    }
    // THE ID WAS RIGHT WHEN IT WAS NAMED OR SNAPSHOTTED. Windows hands an exited
    // thread's id to the next thread created anywhere on the machine, and
    // OpenThread opens that stranger just as well; so ask the OBJECT the handle
    // names which process owns it and whether it is still running. A thread
    // never changes process, so the test is race-free, and both are bare system
    // calls (NtQueryInformationThread) made before anything is suspended.
    const DWORD ownerPid = GetProcessIdOfThread(h);          // 0 = the query itself failed
    const DWORD qErr = ownerPid ? 0 : GetLastError();
    DWORD exitCode = STILL_ACTIVE;
    const bool alive = GetExitCodeThread(h, &exitCode) && exitCode == STILL_ACTIVE;
    if (ownerPid != GetCurrentProcessId() || !alive) {
        CloseHandle(h);
        if (idSlot) InterlockedCompareExchange(idSlot, 0, long(tid));
        if (!compact) {
            const char* forgot = idSlot ? "; the id is forgotten" : "";
            if (!ownerPid)                            LogF("[STALL] thread %lu (%s): GetProcessIdOfThread failed (%lu) -- cannot confirm the id is ours; not suspended%s", (unsigned long)tid, role, (unsigned long)qErr, forgot);
            else if (ownerPid != GetCurrentProcessId()) LogF("[STALL] thread %lu (%s): that id now belongs to process %lu -- ours has exited since it was named; not suspended%s", (unsigned long)tid, role, (unsigned long)ownerPid, forgot);
            else                                      LogF("[STALL] thread %lu (%s): has exited (exit code %lu) -- not suspended%s", (unsigned long)tid, role, (unsigned long)exitCode, forgot);
        }
        return;
    }
    CONTEXT ctx; std::memset(&ctx, 0, sizeof ctx); ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    int n = 0; bool gotCtx = false; DWORD err = 0;
    DWORD64 rip0 = 0, rsp0 = 0;                             // the walk unwinds ctx to nothing; these are the thread's own
    const LONGLONG q0 = Qpc();
    const DWORD prevCount = SuspendThread(h);
    if (prevCount == DWORD(-1)) err = GetLastError();
    else {
        gotCtx = GetThreadContext(h, &ctx) != FALSE;        // returns only once the thread is really stopped
        if (gotCtx) { rip0 = ctx.Rip; rsp0 = ctx.Rsp; n = WalkSuspended(ctx, g_pcs, maxFrames); }
        ResumeThread(h);                                    // ALWAYS, whatever GetThreadContext said
    }
    const double heldMs = QpcToMs(Qpc() - q0);
    InterlockedIncrement(&g_walksThisStall);
    // ---- the thread runs again; now it is safe to name, format and write ----
    FILETIME ct{}, et{}, kt{}, ut{}; ULONGLONG k = 0, u = 0;
    if (GetThreadTimes(h, &ct, &et, &kt, &ut)) { k = (ULONGLONG(kt.dwHighDateTime) << 32) | kt.dwLowDateTime; u = (ULONGLONG(ut.dwHighDateTime) << 32) | ut.dwLowDateTime; }
    char desc[40] = "";
    if (g_threadDesc) {
        PWSTR w = nullptr;
        if (SUCCEEDED(g_threadDesc(h, &w)) && w) {
            if (w[0]) { std::size_t i = 0; for (; w[i] && i + 1 < sizeof desc; ++i) desc[i] = (w[i] < 128) ? char(w[i]) : '?'; desc[i] = 0; }
            LocalFree(w);
        }
    }
    CloseHandle(h);
    if (prevCount == DWORD(-1)) { if (!compact) LogF("[STALL] thread %lu (%s): SuspendThread failed (%lu)", (unsigned long)tid, role, err); return; }
    if (!gotCtx) { if (!compact) LogF("[STALL] thread %lu (%s): suspended (count %lu) but GetThreadContext failed -- resumed", (unsigned long)tid, role, prevCount); return; }
    double dk = 0.0, du = 0.0;
    if (!compact) CpuDelta(tid, k, u, &dk, &du);
    // The top frames inline: "ntdll.dll+0x9F0A4 < KERNELBASE.dll+0x3C7E8 < ..."
    char top[400]; std::size_t used = 0; top[0] = 0;
    const int inline_n = compact ? n : (n < 4 ? n : 4);
    for (int i = 0; i < inline_n && used + 60 < sizeof top; ++i) {
        char f[80]; FormatAddr(g_pcs[i], true, f, sizeof f);
        used += std::size_t(std::snprintf(top + used, sizeof top - used, "%s%s", i ? " < " : "", f));
    }
    if (compact) {
        LogF("[STALL] sweep: thread %lu%s%s%s k %.0f u %.0f ms, %d frame(s), held %.2f ms: %s%s",
             (unsigned long)tid, desc[0] ? " '" : "", desc, desc[0] ? "'" : "", double(k) / 10000.0, double(u) / 10000.0, n, heldMs, top,
             prevCount ? " (was ALREADY suspended by someone else)" : "");
        ProfF("[STALL] sweep: thread %lu%s%s%s k %.0f u %.0f ms: %s", (unsigned long)tid, desc[0] ? " '" : "", desc, desc[0] ? "'" : "", double(k) / 10000.0, double(u) / 10000.0, top);
        return;
    }
    LogF("[STALL] %.1f s stale: thread %lu (%s)%s%s%s -- %d frame(s), suspended %.2f ms, rip 0x%016llX rsp 0x%016llX, cpu kernel %.0f ms (+%.1f since the last sample) user %.0f ms (+%.1f)%s; top: %s%s",
         double(ageMs) / 1000.0, (unsigned long)tid, role, desc[0] ? " '" : "", desc, desc[0] ? "'" : "", n, heldMs,
         (unsigned long long)rip0, (unsigned long long)rsp0, double(k) / 10000.0, dk, double(u) / 10000.0, du,
         prevCount ? " (it was ALREADY suspended by someone else)" : "", top, n > inline_n ? " < ... (the rest in the profiler log)" : "");
    ProfF("[STALL] %.1f s stale: thread %lu (%s)%s%s%s %d frame(s), suspended %.2f ms, kernel %.0f ms (+%.1f) user %.0f ms (+%.1f):",
          double(ageMs) / 1000.0, (unsigned long)tid, role, desc[0] ? " '" : "", desc, desc[0] ? "'" : "", n, heldMs, double(k) / 10000.0, dk, double(u) / 10000.0, du);
    for (int i = 0; i < n; ++i) {
        char f[80]; FormatAddr(g_pcs[i], true, f, sizeof f);
        ProfF("    #%02d  %s  (0x%016llX)", i, f, (unsigned long long)g_pcs[i]);
    }
}
// THE EMUTLS WARM-UP. flesh.cpp's Readable keeps its VirtualQuery cache in
// thread_locals (g_run, g_bigRuns, g_bigRunCursor, g_lastRun, g_runEpoch,
// g_runAsk, g_runMiss), and GCC emutls mallocs the first time each is touched
// on a thread. Touched here, on the poller, once, before anything is ever
// suspended: a readable address in the exe's .text (a >= 256 KB region, so the
// big-run slots are touched too), a small region (this stack), and this TU's
// own code. The suspended-window reads themselves no longer use this cache
// (DefaultReadable); the warm-up only guarantees that any later Readable on
// this thread cannot malloc -- a second safeguard, not required.
void WarmReadable()
{
    static bool warmed = false;
    if (warmed) return;
    warmed = true;
    if (g_env.exeBase) (void)Readable(reinterpret_cast<const void*>(g_env.exeBase + 0x1000), 16);
    int onStack = 0; (void)Readable(&onStack, sizeof onStack);
    (void)Readable(reinterpret_cast<const void*>(&WarmReadable), 16);
}
// The named targets, then (at the 10 s stage) every thread of the process.
// The snapshot allocates, so it is taken BEFORE anything is suspended.
volatile long g_stallOn      = 0;   // the heartbeat says the task thread is stale
volatile long g_stallAgeMs   = 0;
volatile long g_stallSeenTick = 0;  // GetTickCount at the last OnStall: a stall nobody has reported for a while is over (a load screen silences HeartbeatTick)
volatile long g_stallTickGap  = 0;  // the interval between the last two OnStall calls (the ticker's cadence, 100..10000 ms by config)
volatile long g_sampleReq    = 0;   // HeartbeatTick -> poller: a sample is due; bits 0-27 the age in ms, bits 28-30 the stage
volatile long g_sampleStage  = 0;   // 1 = 3 s, 2 = 10 s, 3 = 30 s, 4 = 60 s (ticker thread only)
constexpr long kReqAgeMask   = 0x0FFFFFFFL;
volatile long g_samplesThisStall = 0;   // poller increments, OnRecovered (ticker) reads and zeroes
DWORD g_sweepTids[512];             // poller thread only
void SampleAll(DWORD ageMs, int stage)
{
    const DWORD self = GetCurrentThreadId();
    struct Target { DWORD tid; const char* role; volatile long* slot; } t[5] = {
        { g_env.taskThread ? g_env.taskThread() : 0, "task thread -- runs our tasks; ITS stamp is the stale one", nullptr },
        { DWORD(InterlockedCompareExchange(&g_d3dInitThread, 0, 0)), "D3D-init thread -- created the device", &g_d3dInitThread },
        { DWORD(InterlockedCompareExchange(&g_wndThread, 0, 0)), "window owner thread -- pumps the messages", &g_wndThread },
        { DWORD(InterlockedCompareExchange(&g_presentThread, 0, 0)), "Present thread -- renders the frames", &g_presentThread },
        { g_env.mainThread ? g_env.mainThread() : 0, "DataLoaded thread", nullptr } };
    const LONGLONG q0 = Qpc();
    const long sampleNo = InterlockedIncrement(&g_samplesThisStall);
    RefreshModuleTable();                       // BEFORE any suspension
    int nSweep = 0;
    if (stage == 2) {
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if (snap == INVALID_HANDLE_VALUE) LogF("[STALL] thread snapshot failed (%lu) -- no all-thread sweep", GetLastError());
        else {
            THREADENTRY32 te{}; te.dwSize = sizeof te;
            const DWORD me = GetCurrentProcessId();
            int total = 0;
            BOOL ok = Thread32First(snap, &te);
            const DWORD firstErr = ok ? 0 : GetLastError();
            for (; ok && nSweep < 512; ok = Thread32Next(snap, &te)) {
                ++total;
                if (te.th32OwnerProcessID == me && te.th32ThreadID != self) g_sweepTids[nSweep++] = te.th32ThreadID;
            }
            CloseHandle(snap);
            LogF("[STALL] thread snapshot: %d thread(s) system-wide, %d of this process besides the poller (Thread32First error %lu)", total, nSweep, firstErr);
        }
    }
    LogF("[STALL] sample %ld at %.1f s stale (stage %d of 4: 3/10/30/60 s): walking the named threads%s; module table %d entries",
         sampleNo, double(ageMs) / 1000.0, stage, stage == 2 ? " and then EVERY thread of the process (four frames each)" : "", g_modCount);
    DWORD seen[5] = {}; int nSeen = 0;
    for (int i = 0; i < 5; ++i) {
        bool dup = !t[i].tid || t[i].tid == self;
        for (int j = 0; j < nSeen && !dup; ++j) dup = (seen[j] == t[i].tid);
        if (dup) continue;
        seen[nSeen++] = t[i].tid;
        SampleOneThread(t[i].tid, t[i].role, ageMs, 32, false, t[i].slot);
    }
    if (!nSeen) LogF("[STALL] %.1f s stale and no named thread to sample yet (no task has run, no device created, no window found, no frame presented)", double(ageMs) / 1000.0);
    int swept = 0;
    for (int i = 0; i < nSweep; ++i) {
        bool named = false; for (int j = 0; j < nSeen && !named; ++j) named = (seen[j] == g_sweepTids[i]);
        if (named) continue;
        SampleOneThread(g_sweepTids[i], "process thread", ageMs, 4, true, nullptr);   // the snapshot filtered by owner pid; the pre-suspend check re-confirms it
        ++swept;
    }
    LogF("[STALL] sample %ld done: %d named thread(s) walked (32 frames max), %d swept (4 frames), cost %.1f ms on the poller thread",
         sampleNo, nSeen, swept, QpcToMs(Qpc() - q0));
}

// ======================================================================= THE POLLER
// EVERY 200 MS, ON ITS OWN THREAD (plain CreateThread: this TU throws nothing).
// The heartbeat ticker runs at rereadMs (500 ms by default, 100..10000 by
// config) and is the WATCHDOG; this thread is the one that may do slow things
// -- sample stacks, sweep threads -- without ever delaying a [HEARTBEAT] line.
struct WndSnap { int fg, iconic, visible, hung, stale; RECT win, cli; LONG style, ex; DWORD gui; HWND fgWnd; };
bool SameSnap(const WndSnap& a, const WndSnap& b)
{
    return a.fg == b.fg && a.iconic == b.iconic && a.visible == b.visible && a.hung == b.hung && a.stale == b.stale &&
           std::memcmp(&a.win, &b.win, sizeof(RECT)) == 0 && std::memcmp(&a.cli, &b.cli, sizeof(RECT)) == 0 &&
           a.style == b.style && a.ex == b.ex && a.gui == b.gui;
}
void TakeSnap(HWND h, DWORD owner, WndSnap& s)
{
    s = WndSnap{};
    GetWindowRect(h, &s.win); GetClientRect(h, &s.cli);
    s.fgWnd = GetForegroundWindow(); s.fg = (s.fgWnd == h) ? 1 : 0;
    s.iconic = IsIconic(h) ? 1 : 0; s.visible = IsWindowVisible(h) ? 1 : 0; s.hung = IsHungAppWindow(h) ? 1 : 0;
    s.style = LONG(GetWindowLongPtrA(h, GWL_STYLE)); s.ex = LONG(GetWindowLongPtrA(h, GWL_EXSTYLE));
    GUITHREADINFO gti{}; gti.cbSize = sizeof gti;
    s.gui = (owner && GetGUIThreadInfo(owner, &gti)) ? gti.flags : 0xFFFFFFFFu;
    s.stale = InterlockedCompareExchange(&g_stallOn, 0, 0) ? 1 : 0;
}
HANDLE g_poller = nullptr;
DWORD WINAPI PollerBody(LPVOID)
{
    WndSnap last{}; bool have = false;
    LONGLONG lastChange = Qpc(), lastLine = 0;
    long lastTotal = 0, lastCursor = 0, lastPresent = 0;
    DWORD lastFind = 0, installRetryAt = GetTickCount();
    for (;;) {
        Sleep(200);
        // (a) A due sample first: during a stall it is the thing that matters.
        const long req = InterlockedExchange(&g_sampleReq, 0);
        if (req) { WarmReadable(); SampleAll(DWORD(req & kReqAgeMask), int((req >> 28) & 7)); }
        bool stall = InterlockedCompareExchange(&g_stallOn, 0, 0) != 0;
        if (stall) {
            // A LOAD SCREEN SILENCES THE HEARTBEAT (HeartbeatTick returns before
            // OnStall / OnRecovered while LoadScreenUp()), so a stall followed by
            // a load would stay 'on' here with a frozen age for the whole load.
            // No OnStall for four of the ticker's intervals (at least 2 s) means
            // the heartbeat stopped reporting it: treat it as over, once.
            const DWORD sinceMs = GetTickCount() - DWORD(InterlockedCompareExchange(&g_stallSeenTick, 0, 0));
            const long gap = InterlockedCompareExchange(&g_stallTickGap, 0, 0);
            const DWORD limitMs = DWORD(gap > 500 ? gap * 4 : 2000);
            if (sinceMs > limitMs && InterlockedCompareExchange(&g_stallOn, 0, 1) == 1) {
                LogF("[WND] stall state aged out after %.1f s without a heartbeat report (age was %.1f s): the heartbeat stopped reporting it -- a load screen"
                     " blocks HeartbeatTick -- so the window state is normal again until the next alarm",
                     double(sinceMs) / 1000.0, double(InterlockedCompareExchange(&g_stallAgeMs, 0, 0)) / 1000.0);
                stall = false;
            }
        }
        const LONGLONG now = Qpc();
        // (b) The window.
        HWND h = GameHwnd();
        if (!h || !IsWindow(h)) {
            if (have) {
                LogF("[WND] the window 0x%llX is GONE (IsWindow says no) -- looking for its successor; the subclass will be re-installed on it",
                     (unsigned long long)reinterpret_cast<std::uintptr_t>(h));
                have = false;
                InterlockedExchange64(&g_hwnd, 0);
                InterlockedExchange(&g_subclassed, 0);
            }
            const DWORD tick = GetTickCount();
            if (DWORD(tick - lastFind) >= 1000u) {
                lastFind = tick;
                const char* how = nullptr;
                h = FindGameWindow(&how);
                if (h) {
                    char cls[64] = {}; GetClassNameA(h, cls, sizeof cls);
                    LogF("[WND] found the game window 0x%llX by %s: class '%s', owner thread %lu, %s", (unsigned long long)reinterpret_cast<std::uintptr_t>(h), how, cls,
                         (unsigned long)GetWindowThreadProcessId(h, nullptr), IsWindowVisible(h) ? "visible" : "hidden");
                }
            }
            if (!h) {
                if (stall && QpcToMs(now - lastLine) >= 5000.0) {
                    LogF("[WND] stall %.1f s: no game window known yet; %ld Present call(s) since the last line",
                         double(InterlockedCompareExchange(&g_stallAgeMs, 0, 0)) / 1000.0, InterlockedCompareExchange(&g_presentCalls, 0, 0) - lastPresent);
                    lastPresent = InterlockedCompareExchange(&g_presentCalls, 0, 0); lastLine = now;
                }
                continue;
            }
        }
        if (!InterlockedCompareExchange(&g_subclassed, 0, 0) && DWORD(GetTickCount() - installRetryAt) < 0x80000000u) {
            if (!InstallSubclass(h, "from the poller thread (cross-thread: no code of ours runs on the owner thread unless it created the device)"))
                installRetryAt = GetTickCount() + 5000u;   // a failure is logged inside; try again in five seconds, not every tick
        }
        DrainRing();
        // (c) The state, edge-triggered; at least every 5 s while a stall is on,
        // so the stall window is never silent.
        WndSnap s; TakeSnap(h, g_subclassOwner ? g_subclassOwner : DWORD(InterlockedCompareExchange(&g_wndThread, 0, 0)), s);
        const bool changed = !have || !SameSnap(s, last);
        if (!changed && !(stall && QpcToMs(now - lastLine) >= 5000.0)) continue;
        char fgText[96] = "ours";
        if (!s.fg) {
            char cls[48] = {}; DWORD pid = 0;
            if (s.fgWnd) { GetClassNameA(s.fgWnd, cls, sizeof cls); GetWindowThreadProcessId(s.fgWnd, &pid); }
            std::snprintf(fgText, sizeof fgText, "0x%llX class '%s' pid %lu", (unsigned long long)reinterpret_cast<std::uintptr_t>(s.fgWnd), cls, (unsigned long)pid);
        }
        char guiText[64];
        if (s.gui == 0xFFFFFFFFu) std::snprintf(guiText, sizeof guiText, "n/a");
        else std::snprintf(guiText, sizeof guiText, "0x%lX%s%s%s", (unsigned long)s.gui, (s.gui & GUI_INMOVESIZE) ? " INMOVESIZE" : "",
                           (s.gui & GUI_INMENUMODE) ? " INMENUMODE" : "", (s.gui & GUI_SYSTEMMENUMODE) ? " SYSTEMMENU" : "");
        const long total = InterlockedCompareExchange(&g_msgTotal, 0, 0), cursor = InterlockedCompareExchange(&g_setCursor, 0, 0), present = InterlockedCompareExchange(&g_presentCalls, 0, 0);
        char slowest[96] = "";
        if (g_slowestSeq) { WndRec probeRec{}; probeRec.msg = g_slowestMsg; char nm[256]; DescribeMsg(probeRec, nm, sizeof nm); char* sp = std::strchr(nm, ' '); if (sp) *sp = 0;
                            std::snprintf(slowest, sizeof slowest, "; slowest chained message so far #%ld %s at %.1f ms", g_slowestSeq, nm, g_slowestMs); }
        LogF("[WND] %s window 0x%llX %ldx%ld at %ld,%ld client %ldx%ld, foreground %d (%s), iconic %d, visible %d, hung-by-OS %d, style 0x%08lX ex 0x%08lX, gui %s,"
             " task thread stale %d; %.1f s since the last change; since the last line %ld message(s) through the subclass (%ld WM_SETCURSOR), %ld Present call(s)%s",
             changed ? (have ? "CHANGED:" : "state:") : "stall:", (unsigned long long)reinterpret_cast<std::uintptr_t>(h),
             long(s.win.right - s.win.left), long(s.win.bottom - s.win.top), long(s.win.left), long(s.win.top), long(s.cli.right), long(s.cli.bottom),
             s.fg, fgText, s.iconic, s.visible, s.hung, (unsigned long)s.style, (unsigned long)s.ex, guiText, s.stale,
             QpcToMs(now - lastChange) / 1000.0, total - lastTotal, cursor - lastCursor, present - lastPresent, slowest);
        lastTotal = total; lastCursor = cursor; lastPresent = present; lastLine = now;
        if (changed) lastChange = now;
        last = s; have = true;
    }
    return 0;
}

} // namespace

// ======================================================================= THE INTERFACE
void Install(const Env& env)
{
    if (InterlockedCompareExchange(&g_installed, 1, 0) != 0) return;
    g_env = env;
    (void)QpcPerMs();
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    HMODULE nt  = GetModuleHandleA("ntdll.dll");
    g_enumModules      = Proc<FnEnumProcessModules>(k32, "K32EnumProcessModules");
    g_moduleInfo       = Proc<FnGetModuleInformation>(k32, "K32GetModuleInformation");
    g_moduleName       = Proc<FnGetModuleBaseNameA>(k32, "K32GetModuleBaseNameA");
    g_mappedName       = Proc<FnGetMappedFileNameA>(k32, "K32GetMappedFileNameA");
    g_threadDesc       = Proc<FnGetThreadDescription>(k32, "GetThreadDescription");
    g_rtlVirtualUnwind = Proc<FnRtlVirtualUnwind>(nt, "RtlVirtualUnwind");
    RefreshModuleTable();
    LogF("installed on thread %lu: module table %d entries (K32EnumProcessModules %s), K32GetMappedFileNameA %s, RtlVirtualUnwind %s (no dbghelp, ever),"
         " GetThreadDescription %s; the stall sampler walks the task, D3D-init, window-owner, Present and DataLoaded threads at 3/10/30/60 s and every thread at 10 s",
         (unsigned long)GetCurrentThreadId(), g_modCount, g_enumModules ? "ok" : "MISSING", g_mappedName ? "ok" : "MISSING",
         g_rtlVirtualUnwind ? "ok" : "MISSING (leaf-only walks)", g_threadDesc ? "ok" : "absent");
    InstallD3dProbe();
    g_poller = CreateThread(nullptr, 0, PollerBody, nullptr, 0, nullptr);
    if (!g_poller) LogF("CreateThread for the poller failed (%lu) -- no window log, no stack samples this session", GetLastError());
    else LogF("the poller runs every 200 ms: it finds and subclasses the game window, logs every change of its size, place, focus or activation, drains the message ring, and takes the stall samples");
}

void RecheckIatSlot(const char* when)
{
    if (!g_d3dSlot) return;
    if (!Readable(g_d3dSlot, sizeof(ULONGLONG))) { LogF("[D3D] at %s the IAT slot is unreadable", when); return; }
    const ULONGLONG cur = *g_d3dSlot;
    if (cur == g_slotLastSeen) return;
    char now[80], was[80];
    FormatAddr(std::uintptr_t(cur), false, now, sizeof now);
    FormatAddr(std::uintptr_t(g_slotLastSeen), false, was, sizeof was);
    if (cur == g_slotWritten)
        LogF("[D3D] at %s the D3D11CreateDeviceAndSwapChain slot holds the probe again: slot now 0x%llX (%s), was 0x%llX (%s)", when, (unsigned long long)cur, now, (unsigned long long)g_slotLastSeen, was);
    else
        LogF("[D3D] at %s the D3D11CreateDeviceAndSwapChain slot changed hands: slot now 0x%llX (%s), was 0x%llX (%s) -- NOT re-wrapped: the new holder saved what it found"
             " as its original, so re-writing ours would make the two call each other forever; if it chains, the probe still runs behind it, if not, device creation goes unmeasured",
             when, (unsigned long long)cur, now, (unsigned long long)g_slotLastSeen, was);
    g_slotLastSeen = cur;
}

void OnInputLoaded()
{
    if (!g_d3dSlot) return;
    const long calls = InterlockedCompareExchange(&g_d3dCalls, 0, 0);
    if (calls == 0)
        LogF("[D3D] InputLoaded and the device-creation probe NEVER FIRED: the game's call reached d3d11 without passing through the IAT slot (a call-site hook that"
             " captured the slot's contents before the probe was armed, or a device created before SKSEPlugin_Load). Device creation is unmeasured and the swap-chain probe is unarmed this session");
    else {
        // The slot COUNT is what was actually patched (set after the fact), not
        // the claim on the vtable: a VirtualProtect failure part-way leaves 0-3.
        const long slots = InterlockedCompareExchange(&g_scSlots, 0, 0);
        char sc[96];
        if (slots > 0)                                      std::snprintf(sc, sizeof sc, "armed (%ld of 4 slots)", slots);
        else if (InterlockedCompareExchange(&g_scArmed, 0, 0)) std::snprintf(sc, sizeof sc, "NOT armed (the vtable was claimed but no slot could be patched)");
        else                                                std::snprintf(sc, sizeof sc, "NOT armed (no swap chain came back)");
        LogF("[D3D] InputLoaded: the device-creation probe fired %ld time(s); the swap-chain probe is %s", calls, sc);
    }
}

void OnStall(DWORD ageMs)
{
    const long tick = long(GetTickCount());
    const long prevTick = InterlockedExchange(&g_stallSeenTick, tick ? tick : 1);
    if (prevTick && InterlockedCompareExchange(&g_stallOn, 0, 0)) InterlockedExchange(&g_stallTickGap, tick - prevTick);   // the ticker's cadence, measured
    InterlockedExchange(&g_stallOn, 1);
    InterlockedExchange(&g_stallAgeMs, long(ageMs));
    static const DWORD kAt[4] = { 3000u, 10000u, 30000u, 60000u };
    const long stage = InterlockedCompareExchange(&g_sampleStage, 0, 0);   // ticker thread only writes it
    if (stage >= 4 || ageMs < kAt[stage]) return;
    InterlockedExchange(&g_sampleStage, stage + 1);
    const long age = long(ageMs) & kReqAgeMask;
    InterlockedExchange(&g_sampleReq, (age ? age : 1L) | ((stage + 1) << 28));
}

void OnRecovered(DWORD ageMs)
{
    const bool was = InterlockedExchange(&g_stallOn, 0) != 0;
    InterlockedExchange(&g_sampleReq, 0);
    InterlockedExchange(&g_sampleStage, 0);
    const long samples = InterlockedExchange(&g_samplesThisStall, 0);   // the poller increments these; read-and-zero atomically so the line stays consistent
    const long walks   = InterlockedExchange(&g_walksThisStall, 0);
    if (was || samples)
        LogF("[STALL] stall over after %.1f s: %ld sample(s) taken, %ld thread walk(s); the 3/10/30/60 s schedule is re-armed for the next one",
             double(ageMs) / 1000.0, samples, walks);
}

void OnGameThread()
{
    if (InterlockedCompareExchange(&g_subclassed, 0, 0)) return;
    HWND h = GameHwnd();
    if (!h || !IsWindow(h)) return;
    if (GetWindowThreadProcessId(h, nullptr) == GetCurrentThreadId())
        InstallSubclass(h, "from the heartbeat task, on the window's own thread");
}

void DescribeAddress(const void* p, char* out, std::size_t n)
{
    FormatAddr(reinterpret_cast<std::uintptr_t>(p), false, out, n);
}

std::uint32_t IatSlotRva(const void* image, std::size_t size, bool fileLayout, const char* dll, const char* func)
{
    if (!image || !dll || !func) return 0;
    ImageView v; v.base = static_cast<const std::uint8_t*>(image); v.size = size; v.fileLayout = fileLayout;
    return FindIatSlotRva(v, dll, func);
}

} // namespace windiag
