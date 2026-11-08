# AMD Radeon HD 5450: Hardware OpenGL 4.5 on Windows 11 — Fix for error 126 / GDI Generic

A complete, reproducible fix for the classic `error 126` / `GDI Generic` silent-fallback
problem that prevents hardware OpenGL contexts on the AMD Radeon HD 5450 (and other
TeraScale-era cards) under Windows 11 with the legacy Crimson driver stack.

Result after applying this kit:

```
GL_VENDOR:  ATI Technologies Inc.
GL_RENDERER: AMD Radeon HD 5450
GL_VERSION:  4.5.13399 Compatibility Profile Context
```

**Keywords:** Radeon HD 5450, OpenGL, Windows 11, error 126, GDI Generic, legacy Crimson driver, TeraScale 2, atio6axx.dll

- Russian version of the full write-up: [`opengl_hd5450_win11.md`](opengl_hd5450_win11.md)
- English version of the full write-up: [`opengl_hd5450_win11_en.md`](opengl_hd5450_win11_en.md)

## Supported hardware

The bundled legacy driver package (15.201.1151.1008) accepts a wide range of devices —
285 unique hardware IDs total, from HD 2000 up to R9 380 and AMD APUs. To find your own
ID: Device Manager -> your video adapter -> Properties -> Details -> Hardware Ids.

**Verified on real hardware:**

| GPU | Hardware ID |
|---|---|
| AMD Radeon HD 5450 | `PCI\VEN_1002&DEV_68F9` |

**Same TeraScale 2/3 GL stack — expected to work, not individually verified:**

| Family | Hardware IDs (DEV_) |
|---|---|
| HD 5800 (Evergreen) | 6898, 6899, 689B, 689C, 689E |
| HD 5700 (Juniper) | 68B8, 68B9, 68BA, 68BE, 68BF |
| HD 5500/5600 (Redwood) | 68D8, 68D9, 68DA, 68FA |
| HD 5400 / 6300 (Cedar, incl. APU) | 68A0, 68A1, 68A8, 68C0, 68C1, 68C7, 68E0, 68E1, 68E4, 68E5 |
| HD 6800 (Barts) | 6738, 6739, 673E |
| HD 6500/6600 (Turks) | 6750, 6751, 6758, 6759, 675B, 675D, 675F |
| HD 6400 (Caicos) | 6770, 6771, 6772, 6778, 6779, 677B |
| Mobile (Whistler/Vancouver) | 6720, 6740, 6741, 6742, 6743, 6760, 6761, 6763 |
| HD 6900 (Cayman, TeraScale 3) | 6718, 6719, 671D, 671F, 6704, 6707, 6749, 674A |
| FirePro / workstation Evergreen | 6888, 6889, 688A, 68A9, 68C8, 68C9, 68F1, 68F2 |

**Also present in the INF, but a different GL stack — the driver installs, yet the
registry fix was NOT verified there:**

| Family | Hardware IDs (DEV_) |
|---|---|
| GCN dGPU (Tahiti, Hawaii, Pitcairn, Tonga, Bonaire, Oland) | 6600-6607, 6610-6613, 6640-6647, 6658-665F, 6660-666F, 6780, 678A, 6798, 679A, 679B, 679E, 67B0, 67B1, 67B9, 6808, 6809, 6810, 6811, 6818, 6819, 6828, 682C, 6835, 6837, 683D, 683F, 6921, 6938, 6939, 6900, 6901, 6907, 7300 |
| GCN mobile (Thames, Venus, Oland mobile) | 6800, 6801, 6806, 6820-6823, 6825, 6827, 682B, 682D, 682F, 6840-6843, 6858, 6859 |
| APU (Trinity/Richland, Kabini, Kaveri, Carrizo, Mullins) | 1309-1318, 9830-983D, 9850-9856, 9874, 9900-990F, 9990-999D |
| TeraScale 1 (HD 2000/3000/4000, tag "Legacy") | 9400-950F, 9511-9519, 9540-9598, 95C0-95CF, 9610-9616, 9710-9715 |

Full ID list straight from the INF:

```powershell
Select-String -Path .\legacy-driver\c0296217.inf -Pattern 'PCI\\VEN_1002&DEV_'
```

Notes on the INF:
- Lines with `SUBSYS_...` bind an entry to a specific board vendor (Sapphire, HIS, etc.);
  only the `VEN_1002&DEV_xxxx` part matters for device matching.
- A handful of `ExcludeID` lines exclude specific Apple iMac/Mac Pro subsystems
  (vendor 106B) — irrelevant for PC hardware.

## Repository layout

```
.
├── README.md                        <- you are here
├── opengl_hd5450_win11.md           <- article (RU)
├── opengl_hd5450_win11_en.md        <- article (EN)
├── install_radeon_hd5450.bat        <- one-click installer (asks for admin, runs everything)
├── legacy-driver\                   <- full copy of the legacy driver package (c0296217.inf)
│   ├── c0296217.inf
│   └── B296168\                     <- kernel driver + ICD binaries
│       ├── atio6axx.dll             (64-bit ICD, 6.14.10.13399)
│       ├── atioglxx.dll             (32-bit ICD)
│       └── ...                      (kernel driver stack, 15.201.1151.1008)
└── fix\
    ├── fix_ogl.ps1                  <- registry fix + driver restart (auto-detects adapters)
    ├── t_gditest4.ps1               <- minimal OpenGL context test with full logging
    └── GetGL.cs                     <- C# P/Invoke wrapper used by the test
```

## Quick start

1. Copy the whole folder to the target machine.
2. Run `install_radeon_hd5450.bat` (double-click; it self-elevates via UAC).
3. The script:
   - installs the legacy driver package via `pnputil /add-driver legacy-driver\c0296217.inf /install`;
   - applies the registry fix (`fix\fix_ogl.ps1`);
   - runs the OpenGL test and prints the `GL:` lines.
4. If you see `ATI Technologies Inc.` / `4.5.13399` — done.

## What the fix does (short version)

The legacy driver's ICD (`atio6axx.dll`) loads fine and passes `DrvValidateVersion`,
but the stock registry points `OpenGLDriverName` at stub DLLs, and `opengl32` silently
falls back to GDI Generic when the ICD fails to claim the pixel format. The fix:

1. Points `OpenGLDriverName` / `OpenGLDriverNameWoW` directly at the real ICD
   (`atio6axx.dll` / `atioglxx.dll`) in the display class keys (`0000`..`0003`).
2. Ensures `OpenGLVersion` / `OpenGLVersionWoW` = `1` in every
   `HKLM\SYSTEM\CurrentControlSet\Control\Video\{GUID}\000x` key for AMD adapters
   (this is the value `DrvValidateVersion` expects — verified by direct probing).
3. Registers the ICDs in
   `HKLM\SOFTWARE[...\WOW6432Node]\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers`
   so tools like GPU-Z (and anything else that reads the registry) see the truth.
4. Restarts every detected AMD display adapter via `pnputil /restart-device`
   — mandatory, because the kernel caches the ICD until the video driver restarts.
   No reboot needed afterwards.

## Diagnostics (for the curious)

- `t_gditest4.ps1` creates a hidden window, logs `DescribePixelFormat` count,
  the chosen pixel format's flags (generic / accelerated), `wglCreateContext` /
  `wglMakeCurrent` error codes, dumps loaded GL-related modules while the context
  is alive, and prints the GL vendor/renderer/version strings.
- `DrvValidateVersion` can be probed directly with `LoadLibrary` + `GetProcAddress`
  to discover which `OpenGLVersion` value the ICD accepts (for this ICD it is `1`).

## What NOT to do

- Do **not** install the modern `amdogl.inf` SoftwareComponent alongside the legacy
  kernel driver — its ICD (26.10.x) is incompatible with the 15.201.x kernel and
  silently breaks context creation.
- Do not chase GPU-Z checkboxes: the checkbox shows the *current* provider for the
  API, not per-card capability. It may disappear when you switch the selected card
  in the dropdown — that is cosmetic, not a failure.

## Notes

- Tested on Windows 11 with a Radeon HD 5450 (TeraScale 2) + NVIDIA Tesla side by side;
  the Tesla card is unrelated to the OpenGL failure and can stay enabled throughout.
- Re-tested on my machine — YMMV. If the fix works (or fails) on another TeraScale 2
  card, please report it in Issues so the table above can be updated.
- The kit is self-contained: after a clean Windows install, one batch file restores
  the whole working configuration.

## License

### Files created by the author (MIT)

Applies to: `README.md`, `opengl_hd5450_win11.md`, `opengl_hd5450_win11_en.md`,
`install_radeon_hd5450.bat`, `fix\fix_ogl.ps1`, `fix\t_gditest4.ps1`, `fix\GetGL.cs`.

```
MIT License

Copyright (c) 2026 GrideAiGen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Files in `legacy-driver\` (AMD property)

This repository is a modification of the official AMD legacy driver. All rights to the
original driver binaries (`c0296217.inf`, `B296168\` kernel driver and ICDs) belong to
AMD / Advanced Micro Devices, Inc. and remain governed by the
[AMD Software EULA](https://www.amd.com/en/legal/eula/amd-software-eula.html), which
prohibits modification and redistribution. The package is included here solely as a
compatibility reference for owners of legacy hardware, at their own risk. It must not
be sold or commercially redistributed and will be removed upon a rights-holder request.

## Disclaimer

Provided "as is", without warranty of any kind. Installing kernel drivers can crash
your system (BSOD). Create a system restore point before running the installer.
