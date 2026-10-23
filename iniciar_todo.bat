@echo off
REM Laboratorio 3: inicia MySQL (puerto 3307) y n8n (http://localhost:5678)
call "%~dp0servidor_mysql\iniciar_mysql.bat"
timeout /t 5 /nobreak >nul
echo Iniciando n8n... (deje esta ventana abierta; Ctrl+C para detenerlo)
set N8N_DIAGNOSTICS_ENABLED=false
set N8N_PERSONALIZATION_ENABLED=false
start "" http://localhost:5678
"%USERPROFILE%\n8n-lab\node_modules\.bin\n8n.cmd" start
