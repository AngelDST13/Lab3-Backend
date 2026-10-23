@echo off
REM Inicia el servidor MySQL del laboratorio (puerto 3307, solo localhost).
start "MySQL Lab3" /min "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqld.exe" --defaults-file="%~dp0my.ini"
echo MySQL del Laboratorio 3 iniciado en localhost:3307
