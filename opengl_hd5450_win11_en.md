# Getting OpenGL 4.5 Working on a Radeon HD 5450 under Windows 11: A Registry Forensics Story

**Symptoms:** every attempt to create an OpenGL context on a legacy AMD Radeon HD 5450 (kernel driver 15.201.1151, 2015) fails with error 126 (`ERROR_MOD_NOT_FOUND`, "The specified module could not be found"), and applications silently fall back to `GDI Generic` (OpenGL 1.1). The same system has an NVIDIA Tesla that renders GL perfectly, which makes the failure look even more absurd.

**Result of this write-up:** hardware **OpenGL 4.5.13399 Compatibility Profile** running on a 2010-era card under Windows 11, achieved without changing the driver — purely by fixing the registry and the ICD chain.

---

## 1. Background: how opengl32 picks an ICD

On Windows, `opengl32.dll` never talks to the GPU itself. It dispatches into an **ICD** (Installable Client Driver) — a vendor DLL that implements the actual GL API. The dispatch chain looks like this:

1. `opengl32.dll` reads `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers` — value names are ICD names (without `.dll`), value data is the DLL file name. This is what GPU-Z and many diagnostics read.
2. The kernel-mode display driver state is described under `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000X` — the `OpenGLDriverName` value points to the ICD file, `OpenGLDriverNameWoW` to the 32-bit one, and `OpenGLVersion` is the magic number passed to the ICD's `DrvValidateVersion` export.
3. There is also a per-adapter area under `HKLM\SYSTEM\CurrentControlSet\Control\Video\{GUID}\000X`, where the same values may be duplicated.

**Critical practical detail:** the kernel caches the resolved ICD until the display driver is restarted. Registry edits do not take effect until you run:

```
pnputil /restart-device "PCI\VEN_1002&DEV_XXXX&..."
```

or reboot. Editing the registry and wondering why nothing changed is the classic trap.

Error 126 during context creation almost always means: `opengl32` resolved an ICD path, tried to load it (or its helper stubs), and the load failed. In our case the registry pointed not at the real ICD but at **stub placeholder DLLs** — renamed dummy files — and at one point the 32/64-bit paths were crossed.

## 2. Diagnostic toolkit

### 2.1. A minimal GL context test with full logging

A tiny PowerShell harness that creates a window, requests a pixel format, creates a context, makes it current, then dumps the loaded graphics modules and the GL vendor strings. Logging every Win32 error code is what makes it useful — without `GetLastWin32Error` you are guessing.

Key milestones to log: `DescribePixelFormat` count, `ChoosePixelFormat` result, the **dwFlags of the chosen format**, `wglCreateContext` result + error code, `wglMakeCurrent` result + error code, `glGetString` for `GL_VENDOR/GL_RENDERER/GL_VERSION`.

### 2.2. Module dump with a live context

When the strings still say `GDI Generic`, dump the process modules **while the context is alive** (`Get-Process -Id $PID` from inside the test). In our case `opengl32.dll` and `atio6axx.dll` were loaded — meaning the ICD itself starts fine and the failure is later, at context/pointer-format binding.

### 2.3. Probing DrvValidateVersion directly

Classic ICDs export `DrvValidateVersion(uint version)`: `opengl32` passes the number stored in `OpenGLVersion`, and a `false` reply triggers the silent fallback to GDI Generic. You can probe it yourself:

```powershell
# LoadLibrary + GetProcAddress on the ICD, call it with candidate values
# DrvValidateVersion(1) -> TRUE  confirmed OpenGLVersion=1 is correct for this ICD
```

In our case the registry already held the correct value — validation was not the problem. But this probe is a fast way to rule version mismatch in or out.

## 3. The failure modes we actually found

- **Stub placeholders in the registry chain.** Values pointing at renamed dummy `.dll` files instead of the real ICD path.
- **Mismatched ICD package.** The modern `amdogl.inf` (SoftwareComponent, 2026) ships an ICD whose build is not compatible with the 2015 kernel driver — it must never be the one referenced.
- **The silent GDI Generic fallback.** Even with the ICD loaded and version-validated, `opengl32` rejected the *chosen pixel format* (index 155 in our logs) and silently fell back. Requesting the format with a minimal PFD (dwFlags 0x25) produced format index 7 — and the hardware ICD accepted it. The lesson: **log the format flags**. `PFD_GENERIC_FORMAT` (0x40) means the system never considered hardware formats at all.
- **GPU-Z checkboxes are cosmetic.** GPU-Z marks the *current API provider*, read from the registry key in §1. A card can run hardware GL while the checkbox sits on the other GPU. Trust `glGetString`, not the checkbox. Toggling cards in GPU-Z merely *views* each GPU; it does not switch anything in the system.

## 4. The fix

1. Point the class keys (both `0000` and other display subkeys) at the **direct ICD**:
   - `OpenGLDriverName` = `atio6axx.dll` (64-bit)
   - `OpenGLDriverNameWoW` = `atioglxx.dll` (32-bit)
2. Ensure `OpenGLVersion` = `1` in the per-adapter `Control\Video` keys (verified via `DrvValidateVersion`).
3. Restore registrations in `OpenGLDrivers` (both 64-bit and `WOW6432Node`), value name = DLL name without extension.
4. Restart the display driver: `pnputil /restart-device <InstanceId>` — **this step is mandatory**, otherwise all edits are invisible until reboot.

The full scripts (registry fix with automatic AMD adapter detection, and the GL test harness) are in this repository: `fix/fix_ogl.ps1` and `fix/t_gditest4.ps1`. The expected success line:

```
GL: ATI Technologies Inc.
GL: AMD Radeon HD 5450
GL: 4.5.13399 Compatibility Profile Context
```

## 5. What NOT to do

- Do **not** reference the modern `amdogl` ICD with the 2015 kernel driver — versions must come from the same package.
- Do not leave stub placeholder DLLs in the resolution chain.
- Do not expect registry edits to apply without a driver restart.
- Do not chase GPU-Z checkboxes; they describe the active provider, not the capability.

## 6. Portability

The whole state is reproducible from a saved driver package (`DriverStore` copy of the legacy INF) plus the fix script and test: install via `pnputil /add-driver`, run the fix, run the test. Works on a clean system — see `install_radeon_hd5450.bat`.

---

**TL;DR:** OpenGL 4.5 hardware rendering works on a Radeon HD 5450 under Windows 11. The driver never needed reinstalling — the registry resolution chain for the ICD did.
