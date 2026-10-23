@echo off
REM Detiene de forma ordenada el servidor MySQL del laboratorio.
"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqladmin.exe" --defaults-file="%~dp0my.ini" -u root shutdown
echo MySQL del Laboratorio 3 detenido
