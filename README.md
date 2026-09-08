# Camaleon Billboard

Digital menu board for Camaleon POS. Renders `bb_arrangement` screens from **MySQL** the same way Classic `loadorderscuentas` / `fillclassview` / `loadpicturesand` did.

## Platforms

Windows · Android · macOS · Linux (FVM Flutter **3.47.2**)

```bash
fvm use 3.47.2
fvm flutter pub get
fvm flutter run -d windows   # or macos / linux / android
```

## Architecture

```
lib/
  domain/          entities, repository contracts, use cases
  data/            MySQL + SharedPreferences implementations
  core/            QBColor, QR pairing, MysqlClient
  presentation/    connection UI + absolute-position board canvas
```

## First launch

1. Shows a short **connect** screen.
2. **Escanear QR** (or load image / shared file on desktop).
3. After a valid QR, Billboard fills MySQL and connects.
4. Optional **Ajustes manuales** for host/user/password/device.
5. Returning users with saved prefs auto-connect; on failure they land back on settings.

## Device id (`bb_arrangement.comp_name`)

Not the same table as POS registers, but related:

| | POS `it_tregister` | Billboard `bb_arrangement` |
|---|---|---|
| Key | `Regi_Name`, `Regi_Code`, `reg_deviceid` | `comp_name` |
| Windows | `Regi_Code` ≈ computer name | Default = Windows computer name (Classic `Xregister`) |
| Android / others | `reg_deviceid` = hardware id; `Regi_Name` = station label | Detected device name, or pick a `Regi_Name` / existing `comp_name` |

On connect, if no rows exist for that `comp_name`, Billboard creates a starter screen (or copies another device’s layout).

## Connection (same DB as POS)

POS **local SQLite cache cannot be shared** across apps (sandbox). Billboard must talk to the **same MySQL** POS uses.

1. **QR** — escanea el QR del POS (cargar imagen o tomar foto). Payload: `__cmlnconn__:host:port:user:password:database`
2. **Manual** — host / port / user / password / database (same preference keys as POS: `host`, `port`, `user`, `password`, `db`)
3. **Shared file** (desktop) — optional:
   - `%APPDATA%/Camaleon/db_connection.json`
   - `{Documents parent}/Camaleon/db_connection.json`

```json
{ "host": "192.168.1.10", "port": 3306, "user": "root", "password": "...", "db": "camaleon" }
```

## Computer name

Must match `bb_arrangement.comp_name` configured in **Camaleon POS → Devices & Registers → Billboard**.

Double-tap the board to show/hide reload & settings chrome.
