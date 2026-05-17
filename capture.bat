@echo off
if "%~1"=="--hidden" goto :start
echo CreateObject("WScript.Shell").Run Chr(34)^&WScript.Arguments(0)^&Chr(34)^&" --hidden",0 > "%TEMP%\~cap.vbs"
wscript //nologo "%TEMP%\~cap.vbs" "%~f0"
exit /b 0

:start
title Screenshot Capture
setlocal enabledelayedexpansion


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

try:
    ctypes.windll.user32.SetProcessDpiAwarenessContext(-4)
except Exception:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass

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



class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize",          wintypes.DWORD),
        ("biWidth",         wintypes.LONG),
        ("biHeight",        wintypes.LONG),
        ("biPlanes",        wintypes.WORD),
        ("biBitCount",      wintypes.WORD),
        ("biCompression",   wintypes.DWORD),
        ("biSizeImage",     wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed",       wintypes.DWORD),
        ("biClrImportant",  wintypes.DWORD),
    ]


def capture_screen():
    hdesktop = user32.GetDC(None)
    if not hdesktop:
        raise RuntimeError("Failed to get desktop DC")
    width  = gdi32.GetDeviceCaps(hdesktop, 118)  # DESKTOPHORZRES
    height = gdi32.GetDeviceCaps(hdesktop, 117)  # DESKTOPVERTRES

    bmi = BITMAPINFOHEADER()
    bmi.biSize        = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.biWidth       = width
    bmi.biHeight      = -height  # negative = top-down bitmap
    bmi.biPlanes      = 1
    bmi.biBitCount    = 32
    bmi.biCompression = 0  # BI_RGB

    pbits = ctypes.c_void_p()
    hdc   = gdi32.CreateCompatibleDC(hdesktop)
    if not hdc:
        user32.ReleaseDC(None, hdesktop)
        raise RuntimeError("Failed to create compatible DC")
    hbmp = gdi32.CreateDIBSection(hdesktop, ctypes.byref(bmi), 0, ctypes.byref(pbits), None, 0)
    if not hbmp:
        gdi32.DeleteDC(hdc)
        user32.ReleaseDC(None, hdesktop)
        raise RuntimeError("Failed to create DIB section")
    old_obj = gdi32.SelectObject(hdc, hbmp)
    SRCCOPY = 0x00CC0020
    ok = gdi32.BitBlt(hdc, 0, 0, width, height, hdesktop, 0, 0, SRCCOPY)
    gdi32.SelectObject(hdc, old_obj)
    gdi32.DeleteDC(hdc)
    user32.ReleaseDC(None, hdesktop)
    if not ok:
        gdi32.DeleteObject(hbmp)
        raise RuntimeError("BitBlt failed")
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


SERVICE_ACCOUNT_INFO = {
    "type": "service_account",
    "project_id": "third-eye-63ae9",
    "private_key_id": "fb8d019bc3a167782689c2083a9decfc8be0b2b7",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDP3GJuYJgyUPRM\nwoIRzf1OcL8YwtdK+r0Doii5DXW53ksdYPd9lBzW0sCMtWEvv4cikU+Inef3M00E\nsWjVQXLIGmigOmPwz+u0AfoC6K6oJ6OY3BE0GKhe6DXwZ7tb4OgntF30EM8uphF1\nje9pcpOZWcSnsfb3p9MQGINVfNpVULJVKh3yvwQKMZrCsw+IOtxfSADiE6EuNhK1\nLFbh04BD0zKw31WRDwvBY7O/iQcOUcHGs6ySjQ+UU0k8RcveMH0BoZI52rCwicgr\nPxNOdjIUmWm0z/qLP6BIy7/EZQRWBzaMCjf94RhoWEOTA3MHuqhjaYZQJGowdUBf\nLyrW8NVLAgMBAAECggEAGVt+Wo7IImND2lVkPr3NaBNTDLdAQnJiOp4+r4yXzwvy\nR+w7ZQN7nS1qtf+ukn+gAbSOalExKjQE8kyeSF3KneSy3NEivg7vZy9Si6ZNIFBt\nock/BAb6C1Hyupg9ABFo4OcdCxg93if+O0QMb+W9YdjUp8yLH11G31DOPNCVZhDQ\n0ajhCahu7HSPOu2xyT0ics3YwRsLGdAFzppmaR7cRbe7VUUbudErYrXOAUG/Qwne\nQUj3fZOy2yqSgWevruoN7ewN08UCg5WWzU5KydwPegm2rn+v04K1c1jtAopURKNS\nQkkStCLPemuiMjBKhwIUjCUO7xmKDsFOjrcsD0jp8QKBgQDtv7YTSgHbicAMrm5L\nuaeOGssJbM1r0BtDdUpkWIPJq7OXtztIBpDI1NMFwgw1Cz/fnRhglVU8jHrBFqNO\n2yJpHL/ca/oBQ2vVItQYs7QqEV+1Fh6CIeqD+nFHZRNN4HYMKw/xiPcyOIFkd0E1\n/KNeMt7BTidYTl8qRke4QbF9KQKBgQDf0U7wrHhcUE1Rg4IwOpTaSwLCqJva+s6E\nn3SppGRB7UO46e/YKoAk5KZuLB3dSjbTPH3IFM+Npclty5abJ9KGhsaATe5RE4WN\nwcdaiBhYsytWaQQSU0katAlyuM3keRo26Ua1FELEXcjTtwpK5f4KTW/OYnMfYtvt\njymj4RJZUwKBgB8gLjIwSjX3vtDqNT5su+b60wIU4H/w6uDWBjtE61wHwqdmMbio\nQ2RHmKj0UqzPIDmiU4Kxiks3CQsmb5LvVX31aZjt+fkYXpG00Ze6TygCxkjq8GuR\nDSbiLtpt/S0A6fOF37x7dgF5LFd+1WbAAJNgjZE5LiV9fTAHq3QQBbChAoGAfyp5\nY51atXiatZm2uphOQskjxF3wT7b457mBm3Ff1WVteP7R20wqisuvFCHUxgqIo/RW\nsvvAAYcUr2FhLL6viufAmN2ubjpdQ3G6RuHUk3EZSntYaOERRC7Ov3Po58s27cQU\n/IWKee+fT0tMecm7UTc2M1kUd9y/gHY6/nW+6ykCgYAx/MRamYyzfqllqDjZmKxs\nIb+qfAHByKmeLv4U80i8oP306Uba3luD+CK/v308+B1WsB6vAX00DB6STERcx1eN\ns5acMYpOFxI12PTPU7qHp/sNszCgRT03ukI35K0eUW+ny+XZBg+27Qi7giXxS0Rv\ndSJrURpp4PYpBE0Cuw2ZDw==\n-----END PRIVATE KEY-----\n",
    "client_email": "screenshot-uploader@third-eye-63ae9.iam.gserviceaccount.com",
    "client_id": "117979167229048211786",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/screenshot-uploader%40third-eye-63ae9.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com",
}


def upload_to_gdrive(path, script_dir):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    scopes = ["https://www.googleapis.com/auth/drive.file"]
    creds = service_account.Credentials.from_service_account_info(SERVICE_ACCOUNT_INFO, scopes=scopes)
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


VK_CONTROL = 0x11
VK_SHIFT   = 0x10
VK_S       = 0x53
VK_X       = 0x58


def do_capture(script_dir):
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    path = os.path.join(tempfile.gettempdir(), f"screenshot_{timestamp}.png")
    try:
        save_screenshot(path)
        upload_to_gdrive(path, script_dir)
    except Exception:
        pass
    finally:
        if os.path.exists(path):
            os.remove(path)


def main():
    script_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))

    ctypes.windll.kernel32.SetPriorityClass(
        ctypes.windll.kernel32.GetCurrentProcess(), 0x00000080
    )

    MOD_CONTROL = 0x0002
    MOD_SHIFT   = 0x0004
    WM_HOTKEY   = 0x0312
    HOTKEY_CAPTURE = 1
    HOTKEY_EXIT    = 2

    capture_ok = user32.RegisterHotKey(None, HOTKEY_CAPTURE, MOD_CONTROL | MOD_SHIFT, VK_S)
    exit_ok    = user32.RegisterHotKey(None, HOTKEY_EXIT,    MOD_CONTROL | MOD_SHIFT, VK_X)

    stop_event = threading.Event()

    def poll_keys():
        prev_s = prev_x = False
        while not stop_event.is_set():
            ctrl  = bool(user32.GetAsyncKeyState(VK_CONTROL) & 0x8000)
            shift = bool(user32.GetAsyncKeyState(VK_SHIFT)   & 0x8000)
            s     = bool(user32.GetAsyncKeyState(VK_S)       & 0x8000)
            x     = bool(user32.GetAsyncKeyState(VK_X)       & 0x8000)
            if ctrl and shift:
                if s and not prev_s:
                    threading.Thread(target=do_capture, args=(script_dir,), daemon=True).start()
                if x and not prev_x:
                    stop_event.set()
                    user32.PostQuitMessage(0)
            prev_s, prev_x = s, x
            time.sleep(0.01)

    if not capture_ok or not exit_ok:
        threading.Thread(target=poll_keys, daemon=True).start()

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
        stop_event.set()
        if capture_ok:
            user32.UnregisterHotKey(None, HOTKEY_CAPTURE)
        if exit_ok:
            user32.UnregisterHotKey(None, HOTKEY_EXIT)
        shutdown_gdiplus(token)


if __name__ == "__main__":
    main()
