@echo off
title TripSplit Public Server (Cloudflare Tunnel)
cd /d "%~dp0"

echo ===================================================================
echo Starting TripSplit Server for Friends Anywhere in the World
echo ===================================================================
echo.

echo 1. Starting Backend API...
start "TripSplit Backend API" cmd /k "cd /d ""%~dp0backend"" && venv\Scripts\python.exe app.py"

timeout /t 2 >nul

echo 2. Starting Public Cloudflare Tunnel...
echo.
echo Look for the URL ending with '.trycloudflare.com' below.
echo Share that URL with your friend!
echo.
"C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel --url http://127.0.0.1:5000
pause
