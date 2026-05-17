@echo off
if "%~1"=="--hidden" goto :start
echo CreateObject("WScript.Shell").Run Chr(34)^&WScript.Arguments(0)^&Chr(34)^&" --hidden",0 > "%TEMP%\~cap.vbs"
wscript //nologo "%TEMP%\~cap.vbs" "%~f0"
exit /b 0

:start
title Screenshot Capture
setlocal enabledelayedexpansion

if not exist "%~dp0service_account.json" (
    echo.
    echo ERROR: service_account.json not found.
    echo Place service_account.json in the same folder as this file.
    echo.
    pause
    exit /b 1
)

set "PYTHON_EXE="
set "PYTHONW_EXE="

if exist "C:\Windows\pyw.exe" (
    call :test_python "C:\Windows\pyw.exe"
    if !errorlevel! equ 0 (
        set "PYTHONW_EXE=C:\Windows\pyw.exe"
        goto :found_python
    )
)
if exist "C:\Windows\py.exe" (
    call :test_python "C:\Windows\py.exe"
    if !errorlevel! equ 0 (
        set "PYTHON_EXE=C:\Windows\py.exe"
        goto :found_python
    )
)

for %%X in (pyw.exe pythonw.exe python.exe py.exe) do (
    where %%X >nul 2>nul
    if !errorlevel! equ 0 (
        for /f "usebackq delims=" %%P in (`where %%X 2^>nul`) do (
            if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
            if "%%X"=="pyw.exe" set "PYTHONW_EXE=%%P"
            if "%%X"=="pythonw.exe" set "PYTHONW_EXE=%%P"
            if defined PYTHON_EXE (
                call :test_python "%%P"
                if !errorlevel! equ 0 goto :found_python
                set "PYTHON_EXE="
                if "%%X"=="pyw.exe" set "PYTHONW_EXE="
                if "%%X"=="pythonw.exe" set "PYTHONW_EXE="
            )
        )
    )
)

echo Python is not installed. Installing now...
call :install_python
if errorlevel 1 (
    echo Python installation failed. Please install Python manually and rerun this script.
    pause
    exit /b 1
)

for %%X in (pyw.exe pythonw.exe python.exe py.exe) do (
    where %%X >nul 2>nul
    if !errorlevel! equ 0 (
        for /f "usebackq delims=" %%P in (`where %%X 2^>nul`) do (
            if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
            if "%%X"=="pyw.exe" set "PYTHONW_EXE=%%P"
            if "%%X"=="pythonw.exe" set "PYTHONW_EXE=%%P"
        )
        if defined PYTHON_EXE (
            call :test_python "%%P"
            if !errorlevel! equ 0 goto :found_python
            set "PYTHON_EXE="
            if "%%X"=="pyw.exe" set "PYTHONW_EXE="
            if "%%X"=="pythonw.exe" set "PYTHONW_EXE="
        )
    )
)

echo Python could not be detected after installation.
pause
exit /b 1

:found_python
echo Installing dependencies...
if defined PYTHONW_EXE (
    "%PYTHONW_EXE%" -m pip install -q google-api-python-client google-auth-oauthlib
) else (
    "%PYTHON_EXE%" -m pip install -q google-api-python-client google-auth-oauthlib
)

set "BATFILE=%~f0"
set "BASEDIR=%~dp0"
if "%BASEDIR:~-1%"=="\" set "BASEDIR=%BASEDIR:~0,-1%"
set "SCRIPT=%TEMP%\capture_gdrive.py"
powershell -NoProfile -Command "$f=[System.IO.File]::ReadAllText('%BATFILE%'); $m='::PY'+'THON::'; $i=$f.LastIndexOf($m); $s=$f.IndexOf([char]10,$i)+1; $enc=New-Object System.Text.UTF8Encoding($False); [System.IO.File]::WriteAllText('%SCRIPT%',$f.Substring($s),$enc)"

set "LAUNCH_EXE="
for /f "usebackq delims=" %%P in (`where python.exe 2^>nul`) do (
    if not defined LAUNCH_EXE (
        set "LAUNCH_EXE=%%P"
        set "TRY_PYTHONW=%%P"
        set "TRY_PYTHONW=!TRY_PYTHONW:python.exe=pythonw.exe!"
        if exist "!TRY_PYTHONW!" set "LAUNCH_EXE=!TRY_PYTHONW!"
    )
)
if not defined LAUNCH_EXE set "LAUNCH_EXE=%PYTHON_EXE%"
if not defined LAUNCH_EXE set "LAUNCH_EXE=%PYTHONW_EXE%"

start "" /high "!LAUNCH_EXE!" "%SCRIPT%" "%BASEDIR%"
exit /b 0

:test_python
"%~1" --version >nul 2>nul
exit /b %errorlevel%

:install_python
where winget >nul 2>nul
if !errorlevel! equ 0 (
    echo Installing Python using winget...
    winget install --id Python.Python.3 -e --silent --accept-source-agreements --accept-package-agreements >nul 2>nul
    if !errorlevel! equ 0 exit /b 0
    echo winget install failed, falling back to web installer...
)
set "PYTHON_INSTALLER=%TEMP%\python-install.exe"
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.14.5/python-3.14.5-amd64.exe' -OutFile '%PYTHON_INSTALLER%'"
if errorlevel 1 exit /b 1
powershell -NoProfile -Command "Start-Process -FilePath '%PYTHON_INSTALLER%' -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_test=0' -Wait"
if errorlevel 1 exit /b 1
exit /b 0

::PYTHON::
import ctypes
import os
import sys
import tempfile
import threading
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
gdiplus = ctypes.windll.gdiplus

GDRIVE_FOLDER_ID = "0AA9gDAs_1XxRUk9PVA"

class GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", wintypes.DWORD),
        ("Data2", wintypes.WORD),
        ("Data3", wintypes.WORD),
        ("Data4", wintypes.BYTE * 8),
    ]

class GdiplusStartupInput(ctypes.Structure):
    _fields_ = [
        ("GdiplusVersion", wintypes.ULONG),
        ("DebugEventCallback", ctypes.c_void_p),
        ("SuppressBackgroundThread", wintypes.BOOL),
        ("SuppressExternalCodecs", wintypes.BOOL),
    ]


def clsid_from_string(clsid_str):
    values = clsid_str.strip('{}').split('-')
    data1 = int(values[0], 16)
    data2 = int(values[1], 16)
    data3 = int(values[2], 16)
    data4 = bytes.fromhex(values[3] + values[4])
    guid = GUID()
    guid.Data1 = data1
    guid.Data2 = data2
    guid.Data3 = data3
    for i in range(8):
        guid.Data4[i] = data4[i]
    return guid


def init_gdiplus():
    token = ctypes.c_void_p()
    startup_input = GdiplusStartupInput(1, None, False, False)
    status = gdiplus.GdiplusStartup(ctypes.byref(token), ctypes.byref(startup_input), None)
    if status != 0:
        raise RuntimeError(f"GdiplusStartup failed: {status}")
    return token


def shutdown_gdiplus(token):
    if token:
        gdiplus.GdiplusShutdown(token)



def capture_screen():
    hdesktop = user32.GetDC(None)
    if not hdesktop:
        raise RuntimeError("Failed to get desktop DC")
    width = user32.GetSystemMetrics(0)
    height = user32.GetSystemMetrics(1)
    hdc = gdi32.CreateCompatibleDC(hdesktop)
    if not hdc:
        user32.ReleaseDC(None, hdesktop)
        raise RuntimeError("Failed to create compatible DC")
    hbmp = gdi32.CreateCompatibleBitmap(hdesktop, width, height)
    if not hbmp:
        gdi32.DeleteDC(hdc)
        user32.ReleaseDC(None, hdesktop)
        raise RuntimeError("Failed to create compatible bitmap")
    old_obj = gdi32.SelectObject(hdc, hbmp)
    SRCCOPY = 0x00CC0020
    if not gdi32.BitBlt(hdc, 0, 0, width, height, hdesktop, 0, 0, SRCCOPY):
        gdi32.SelectObject(hdc, old_obj)
        gdi32.DeleteObject(hbmp)
        gdi32.DeleteDC(hdc)
        user32.ReleaseDC(None, hdesktop)
        raise RuntimeError("BitBlt failed")
    gdi32.SelectObject(hdc, old_obj)
    gdi32.DeleteDC(hdc)
    user32.ReleaseDC(None, hdesktop)
    return hbmp


def save_bitmap(hbmp, path):
    pbitmap = ctypes.c_void_p()
    if gdiplus.GdipCreateBitmapFromHBITMAP(hbmp, 0, ctypes.byref(pbitmap)) != 0:
        gdi32.DeleteObject(hbmp)
        raise RuntimeError("GdipCreateBitmapFromHBITMAP failed")
    clsid_png = clsid_from_string("{557CF406-1A04-11D3-9A73-0000F81EF32E}")
    status = gdiplus.GdipSaveImageToFile(pbitmap, path, ctypes.byref(clsid_png), None)
    gdiplus.GdipDisposeImage(pbitmap)
    gdi32.DeleteObject(hbmp)
    if status != 0:
        raise RuntimeError(f"GdipSaveImageToFile failed: {status}")


def upload_to_gdrive(path, script_dir):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    scopes = ["https://www.googleapis.com/auth/drive.file"]
    key_path = os.path.join(script_dir, "service_account.json")

    creds = service_account.Credentials.from_service_account_file(key_path, scopes=scopes)
    service = build("drive", "v3", credentials=creds)
    file_metadata = {
        "name": os.path.basename(path),
        "parents": [GDRIVE_FOLDER_ID],
    }
    media = MediaFileUpload(path, mimetype="image/png")
    uploaded = service.files().create(
        body=file_metadata, media_body=media, fields="id",
        supportsAllDrives=True
    ).execute()
    file_id = uploaded.get("id")
    return f"https://drive.google.com/file/d/{file_id}/view"


def save_screenshot(path):
    hbmp = capture_screen()
    save_bitmap(hbmp, path)


def do_capture(script_dir):
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    path = os.path.join(tempfile.gettempdir(), f"screenshot_{timestamp}.png")
    try:
        save_screenshot(path)
        upload_to_gdrive(path, script_dir)
    except Exception as e:
        ctypes.windll.user32.MessageBoxW(0, str(e), "Error", 0)
    finally:
        if os.path.exists(path):
            os.remove(path)


def main():
    script_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))

    ctypes.windll.kernel32.SetPriorityClass(
        ctypes.windll.kernel32.GetCurrentProcess(), 0x00000080
    )

    MOD_CONTROL = 0x0002
    MOD_SHIFT = 0x0004
    WM_HOTKEY = 0x0312
    HOTKEY_CAPTURE = 1
    HOTKEY_EXIT = 2

    user32.RegisterHotKey(None, HOTKEY_CAPTURE, MOD_CONTROL | MOD_SHIFT, 0x53)
    user32.RegisterHotKey(None, HOTKEY_EXIT, MOD_CONTROL | MOD_SHIFT, 0x58)

    token = init_gdiplus()
    try:
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
            if msg.message == WM_HOTKEY:
                if msg.wParam == HOTKEY_CAPTURE:
                    threading.Thread(target=do_capture, args=(script_dir,), daemon=True).start()
                elif msg.wParam == HOTKEY_EXIT:
                    break
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
    finally:
        user32.UnregisterHotKey(None, HOTKEY_CAPTURE)
        user32.UnregisterHotKey(None, HOTKEY_EXIT)
        shutdown_gdiplus(token)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        ctypes.windll.user32.MessageBoxW(0, str(e), "Fatal Error", 0)
