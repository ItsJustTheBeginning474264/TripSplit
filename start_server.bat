@echo off
title TripSplit Backend Server
cd /d "%~dp0backend"
echo ========================================================
echo Starting TripSplit Backend Server...
echo ========================================================
echo.
venv\Scripts\python.exe app.py
pause
