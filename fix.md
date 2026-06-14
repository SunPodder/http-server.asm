# Bugs & Vulnerabilities Found

## Fixed

### 1. Path Traversal (Critical)
**File:** `main.asm:196-225`
**Problem:** The request path was used directly in `SYS_OPEN` with no validation. A request like `GET /../../../etc/passwd` would serve any file on the filesystem.
**Fix:** Added two checks after extracting the path:
- Reject paths starting with `/` (absolute paths)
- Reject paths containing `..` (directory traversal)
Only files relative to the CWD and its children can be served.

### 2. Denial of Service — Server exits on client disconnect (Critical)
**File:** `main.asm:191-192`
**Problem:** `SYS_READ` returning 0 (client disconnected without sending data) caused `jle _read_err` → `exit 1`, killing the entire server. Any client could terminate the server by connecting and closing.
**Fix:** Changed to `jl _read_err` (actual errors) / `je _close` (EOF → close connection and continue).

### 3. No HTTP method validation (Critical)
**File:** `main.asm:196-209`
**Problem:** The code unconditionally skipped 5 bytes (`"GET /"`) regardless of the actual request method. `POST /`, `PUT /`, etc. would parse garbage and potentially crash.
**Fix:** Added a `dword` comparison against `"GET "` before parsing. Non-GET requests receive a `405 Method Not Allowed` response.

## Unfixed (Minor)

### 4. `SO_REUSEADDR` not actually set (`main.asm:141`)
`SO_REUSEADDR | SO_REUSEPORT` = `2 | 15` = `15` (only `SO_REUSEPORT`). Two separate `setsockopt` calls are needed.

### 5. Wrong error message in `_listen_err` (`main.asm:398`)
Prints `bind_err_msg` instead of `listen_err_msg` — copy-paste bug.

### 6. Missing `Content-Type` in 200 response (`main.asm:61`)
200 OK sends no `Content-Type` header. Browsers may misrender.

### 7. Potential close of fd 0 (stdin) in `_500_error` (`main.asm:324-328`)
If reached before opening the file, `file_fd` is 0 (BSS), closing stdin.
