@echo off
REM 使用 DevEco Studio 自带的 Node 与 hvigor 构建 HarmonyOS 应用
REM 用法（在 harmony 目录）: hvigor.bat assembleApp
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
cd /d "%ROOT%"

REM 尝试在指定路径查找 DevEco Studio
set "DEVECO_STUDIO="
for %%d in (
    "%ProgramFiles%\Huawei\DevEco Studio"
    "%ProgramFiles(x86)%\Huawei\DevEco Studio"
    "%LOCALAPPDATA%\Programs\Huawei\DevEco Studio"
) do (
    if exist "%%d" set "DEVECO_STUDIO=%%d"
)

REM 如果设置了环境变量则优先使用
if defined DEVECO_NODE (
    set "NODE=%DEVECO_NODE%"
) else (
    if defined DEVECO_STUDIO (
        set "NODE=%DEVECO_STUDIO%\tools\node\bin\node.exe"
    )
)

if defined DEVECO_HVIGORW (
    set "HVIGORW=%DEVECO_HVIGORW%"
) else (
    if defined DEVECO_STUDIO (
        set "HVIGORW=%DEVECO_STUDIO%\tools\hvigor\bin\hvigorw.js"
    )
)

REM 检查 Node
if not defined NODE (
    echo error: NODE not found. Set DEVECO_NODE or install DevEco Studio. >&2
    exit /b 1
)
if not exist "%NODE%" (
    echo error: Node not found at %NODE% >&2
    exit /b 1
)

REM 检查 hvigorw.js
if not defined HVIGORW (
    echo error: HVIGORW not found. Set DEVECO_HVIGORW. >&2
    exit /b 1
)
if not exist "%HVIGORW%" (
    echo error: hvigorw.js not found at %HVIGORW% >&2
    exit /b 1
)

REM 设置 DevEco SDK Home
if defined DEVECO_STUDIO (
    set "DEVECO_SDK_HOME=%DEVECO_STUDIO%\sdk"
    set "DEVECO_SDK_HOME=%DEVECO_SDK_HOME:\=\\%
)

endlocal & (
    set "DEVECO_SDK_HOME=%DEVECO_SDK_HOME%"
    set "DEVECO_NODE=%DEVECO_NODE%"
    set "DEVECO_HVIGORW=%DEVECO_HVIGORW%"
) & "%NODE%" "%HVIGORW%" %*
