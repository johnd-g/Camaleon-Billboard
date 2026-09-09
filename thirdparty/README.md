# Third-party installer payloads

Required by `installer.iss` (same VC++ Redistributable as CamaleonPOS):

| File | Purpose |
|------|---------|
| `VC_redist.x64.exe` | Visual C++ 2015–2022 Redistributable (x64) |
| `VC_redist.x86.exe` | Visual C++ 2015–2022 Redistributable (x86) |
| `vcruntime140_1.dll` | Fallback copy if redist install leaves DLL missing |

Copy from CamaleonPOS `thirdparty/` or download from Microsoft.

Billboard does **not** bundle MariaDB, Java, VB6, or MySQL ODBC — it connects to the POS MySQL via QR/manual settings (`mysql1`).
