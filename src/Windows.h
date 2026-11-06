// A SHIM, AND ONLY A SHIM.
//
// PrismaUI_API.h is vendored byte-identical from the framework's own example
// plugin and includes <Windows.h> with a capital W, which is right on MSVC and
// on Windows' case-insensitive filesystem. This DLL cross-compiles with
// mingw-w64 on Linux, where the header is windows.h and the lookup is case
// SENSITIVE, so the include fails.
//
// The vendor header is the authority on PrismaUI's interface and is not edited
// here for any reason: a one-line forwarder costs nothing and keeps that file
// diffable against upstream forever. flesh.cpp has already included
// <windows.h> long before this point, so in practice this resolves to nothing
// at all -- the include guards in the real header see to that.
#pragma once
#include_next <windows.h>
