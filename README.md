# safepath

Proyecto: servicio que escanea redes (nmap), guarda hallazgos en PostgreSQL y muestra un dashboard (Streamlit).

## Componentes
- backend (FastAPI) -> `/api/*`
- scanner (nmap) -> ejecutado periódicamente por `systemd` timer
- dashboard (Streamlit)
- PostgreSQL (host)

## Instalación (resumen)
1. Copia el repo a `/opt/safepath` (o cambia rutas en `install.sh`).
2. Edita `scripts/install.sh` y configura `DB_PASSWORD` y `DOMAIN` (si usas nginx).
3. Ejecuta: `sudo /opt/safepath/scripts/install.sh`
4. Revisa logs:
   - `sudo journalctl -u safepath-backend -f`
   - `sudo journalctl -u safepath-dashboard -f`
   - `sudo journalctl -u safepath-scanner -f`
   - `sudo systemctl list-timers | grep safepath`

## Notas de seguridad
- No escanear redes sin permiso.
- Protege `/etc/safepath/*.env` (permisos 640).
- Añade autenticación (JWT / API key) antes de exponer el backend públicamente.
- Usa nginx + TLS para publicar dashboard/API.
