// windiag.h -- FleshCore: WHERE the game's thread is stuck, not just WHETHER.
//
// The [HEARTBEAT] worker can prove the game's thread stale for
// a minute or more at startup or at the main menu after
// an Alt-Tab, and say nothing else: not which thread was
// wedged in what module, not what the window does, not how long the D3D
// device takes to create (a minute and a half can pass between another plugin's hook and
// InputLoaded, and nothing times the gap). This translation unit holds the
// three probes that settle those:
//
//   (1) an IAT probe on SkyrimSE.exe's import of d3d11!D3D11CreateDeviceAndSwapChain
//       (the call's arguments, its HRESULT and its duration; the swap chain's
//       OutputWindow is how the probe learns the game's HWND and the D3D-init thread),
//       and, on the IDXGISwapChain it returns, a vtable probe on Present,
//       SetFullscreenState, ResizeBuffers and ResizeTarget -- the renderer path
//       an Alt-Tab freeze takes (the engine re-creating its render targets), which the
//       device-creation probe alone can never see;
//   (2) a WndProc subclass on the game window plus a 200 ms poller of its state
//       (every message that can move, size, focus or activate the window, with
//       the time the REST of the chain took to handle it);
//   (3) a stall stack sampler, requested from the heartbeat's stale branch and
//       run on the poller thread, that suspends each candidate thread for well
//       under a millisecond, walks its stack, resumes it, and only then names
//       the frames module+RVA; at the 10 s mark it sweeps every thread of the
//       process, because the Present thread was none of
//       the four threads anyone had named.
//
// flesh.cpp owns the log files, the locks, the thread identities and the
// image base; it hands them over in Env and calls the six functions below.
// Nothing here takes a FleshCore lock or touches a FleshCore global.
#pragma once
#include <windows.h>
#include <cstddef>
#include <cstdint>

namespace windiag {

struct Env {
    // One fully formatted line to FleshCore.log. flesh.cpp's adapter is
    // NON-BLOCKING (TryEnterCriticalSection on the log lock; a held lock drops
    // the line), so it is safe from any thread, including the watchdog while
    // the game's thread is stuck inside Log.
    void (*log)(const char* line);
    // Same contract, FleshCore.loading_profiler.log (the long dumps go here).
    void (*profLog)(const char* line);
    // flesh.cpp's cached RangeOK: for reads made while NOTHING is suspended (the
    // D3D/DXGI probes, the WndProc ring, RecheckIatSlot, the import-table walk).
    // The sampler's reads inside the suspended window use an uncached
    // VirtualQuery of their own (windiag.cpp's DefaultReadable): this cache is
    // per-thread and only ForgetMemory, never called on the poller, resets it.
    bool (*readable)(const void* p, std::size_t n);
    // The thread that runs FleshCore's tasks (the one the heartbeat times);
    // 0 until the first task ran.
    DWORD (*taskThread)();
    // The DataLoaded thread; 0 before DataLoaded.
    DWORD (*mainThread)();
    // SkyrimSE.exe's image base (flesh.cpp's g_base).
    std::uintptr_t exeBase;
};

// Called once from SKSEPlugin_Load, BEFORE device creation
// (well before it): installs the D3D IAT probe and starts the
// 200 ms poller thread. A second call is ignored.
void Install(const Env& env);

// PostLoad / PostPostLoad / InputLoaded / DataLoaded: logs if the d3d11 IAT
// slot changed hands since Install. NEVER re-wraps: a hook installed later saved this probe's pointer
// as its own original, and writing the probe in again would make the two call each other forever.
void RecheckIatSlot(const char* when);

// InputLoaded (SKSE message type 6 -- after the
// device exists): the probe's self-check. A slot that was armed and a probe
// that counted zero calls means the game's call never passed through the IAT
// slot (a call-site hook that captured the slot's contents before the probe, or a
// device created before SKSEPlugin_Load); the exe's .text is Steam-DRM
// encrypted on disk, so this cannot be settled offline -- only here.
void OnInputLoaded();

// From HeartbeatTick's stale branch (the watchdog thread, every ~500 ms while
// the task thread is stale). It only RECORDS: the stall state for the window
// poller, and a sample request once each when the age crosses 3 s, 10 s, 30 s
// and 60 s. The poller thread performs the sampling, so a walk that wedges can
// never stop the [HEARTBEAT] lines.
void OnStall(DWORD ageMs);

// From HeartbeatTick's recovery branch: one-line stall summary, schedule reset.
void OnRecovered(DWORD ageMs);

// From HeartbeatRunBody, ON the task thread, each beat: if that thread owns
// the game window and nobody has subclassed it yet, the subclass goes in here
// (the one race-free place); otherwise a few instructions and out.
void OnGameThread();

// "module.dll+0xRVA" for any address -- the stall sampler's own formatter,
// on its lock-free route (VirtualQuery + K32GetMappedFileNameA): any thread,
// never while another thread is held suspended.
void DescribeAddress(const void* p, char* out, std::size_t n);

// ---- test helper, not used by flesh.cpp ----------------------------------
// The import-table walk the D3D probe uses, exposed so it can also run
// it against SkyrimSE.exe read from DISK (fileLayout = true: RVAs are mapped
// through the section table) or against a loaded module (fileLayout = false,
// size 0: RVAs are offsets from the image base, every read checked with
// Env::readable or, before Install, with a VirtualQuery fallback). Returns
// the RVA of the IAT slot for dll!func, or 0 when the image does not import it
// by that name.
std::uint32_t IatSlotRva(const void* image, std::size_t size, bool fileLayout,
                         const char* dll, const char* func);

} // namespace windiag
