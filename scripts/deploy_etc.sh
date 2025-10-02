#!/usr/bin/env bash
# scripts/deploy_etc.sh
#
# Copia los ficheros de etc/ del repo a los directorios del sistema:
#  - /etc/safepath/ (env files)
#  - /etc/systemd/system/ (units)
#  - /etc/nginx/sites-available/ (opcional)
#
# Hace backups seguros de archivos previos, fija permisos y propietarios,
# recarga systemd y habilita/arranca las unidades. Ejecutar como root.
#
# USO:
#   sudo ./scripts/deploy_etc.sh
#
set -euo pipefail

# -----------------------
# Configuración (personalizar si hace falta)
# -----------------------
REPO_ETC_DIR="$(dirname "$(realpath "$0")")/../etc"
ETC_SAFEPATH="/etc/safepath"
SYSTEMD_DIR="/etc/systemd/system"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
SAFEPATH_USER="safepath"
SAFEPATH_GROUP="safepath"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
# Lista de ficheros esperados relativos a REPO_ETC_DIR
SFILE_SAFEPATH=("safepath/backend.env" "safepath/dashboard.env" "safepath/scanner.env")
SFILE_SYSTEMD=("systemd/safepath-backend.service" "systemd/safepath-dashboard.service" "systemd/safepath-scanner.service" "systemd/safepath-scanner.timer")
# archivo nginx opcional (si existe en repo)
NGINX_CONF="nginx/safepath.conf"

# -----------------------
# Helpers
# -----------------------
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[OK]\e[0m $*"; }

# must be root
if [ "$(id -u)" -ne 0 ]; then
  die "Este script debe ejecutarse como root. Usa: sudo $0"
fi

# sanity checks
if [ ! -d "$REPO_ETC_DIR" ]; then
  die "No encuentro $REPO_ETC_DIR. Asegúrate de ejecutar el script desde el repo clonado."
fi

# crear destino /etc/safepath
if [ ! -d "$ETC_SAFEPATH" ]; then
  info "Creando directorio $ETC_SAFEPATH"
  mkdir -p "$ETC_SAFEPATH"
  chown root:"$SAFEPATH_GROUP" "$ETC_SAFEPATH" || true
  chmod 750 "$ETC_SAFEPATH"
fi

# function: backup and copy
backup_and_copy() {
  local src="$1"
  local dst="$2"
  if [ -e "$dst" ]; then
    info "Haciendo backup de $dst -> ${dst}.bak.$BACKUP_SUFFIX"
    mv "$dst" "${dst}.bak.$BACKUP_SUFFIX"
  fi
  cp -a "$src" "$dst"
}

# Deploy env files to /etc/safepath
info "Instalando env files en $ETC_SAFEPATH ..."
for rel in "${SFILE_SAFEPATH[@]}"; do
  SRC="$REPO_ETC_DIR/$rel"
  BASENAME="$(basename "$rel")"
  DST="$ETC_SAFEPATH/$BASENAME"
  if [ ! -f "$SRC" ]; then
    die "Fichero requerido no encontrado en repo: $SRC"
  fi
  backup_and_copy "$SRC" "$DST"
  # permisos: root:safepath 640
  chown root:"$SAFEPATH_GROUP" "$DST" || true
  chmod 640 "$DST"
  info " -> $DST"
done
ok "Env files instalados."

# Deploy systemd units
info "Instalando units systemd en $SYSTEMD_DIR ..."
for rel in "${SFILE_SYSTEMD[@]}"; do
  SRC="$REPO_ETC_DIR/$rel"
  FNAME="$(basename "$rel")"
  DST="$SYSTEMD_DIR/$FNAME"
  if [ ! -f "$SRC" ]; then
    die "Unit systemd requerida no encontrada en repo: $SRC"
  fi
  backup_and_copy "$SRC" "$DST"
  chown root:root "$DST"
  chmod 644 "$DST"
  info " -> $DST"
done
ok "Units systemd instaladas."

# Optional: nginx conf
if [ -f "$REPO_ETC_DIR/$NGINX_CONF" ]; then
  info "Instalando nginx conf..."
  SRC="$REPO_ETC_DIR/$NGINX_CONF"
  DST="$NGINX_SITES_AVAILABLE/$(basename "$NGINX_CONF")"
  backup_and_copy "$SRC" "$DST"
  chown root:root "$DST"
  chmod 644 "$DST"
  info " -> $DST"
  # enable symlink in sites-enabled
  if [ ! -L "/etc/nginx/sites-enabled/$(basename "$NGINX_CONF")" ]; then
    ln -s "$DST" "/etc/nginx/sites-enabled/$(basename "$NGINX_CONF")" || true
    info " -> enabled in sites-enabled"
  fi
  ok "nginx conf instalada."
else
  info "No se encontró $REPO_ETC_DIR/$NGINX_CONF — se omite nginx."
fi

# ensure user/group exists (non-fatal)
if ! id "$SAFEPATH_USER" >/dev/null 2>&1; then
  info "Usuario $SAFEPATH_USER no existe — se crea (sin shell)."
  useradd -r -s /usr/sbin/nologin "$SAFEPATH_USER" || die "Fallo creando usuario $SAFEPATH_USER"
fi

# ownership for /etc/safepath should be root:safepath
chown root:"$SAFEPATH_GROUP" "$ETC_SAFEPATH" || true
chmod 750 "$ETC_SAFEPATH" || true

# reload systemd, enable & start units
info "Recargando systemd daemon..."
systemctl daemon-reload

# enable + start backend & dashboard services and enable timer
info "Habilitando unidades..."
systemctl enable safepath-backend.service || true
systemctl enable safepath-dashboard.service || true
systemctl enable safepath-scanner.timer || true

info "Arrancando/rehabilitando servicios..."
systemctl restart safepath-backend.service || systemctl start safepath-backend.service || true
systemctl restart safepath-dashboard.service || systemctl start safepath-dashboard.service || true
systemctl restart safepath-scanner.timer || systemctl start safepath-scanner.timer || true

ok "Units habilitadas y arrancadas (o encoladas)."

# nginx reload if present
if command -v nginx >/dev/null 2>&1 && [ -f "$NGINX_SITES_AVAILABLE/$(basename "$NGINX_CONF")" ]; then
  info "Comprobando configuración nginx..."
  nginx -t && systemctl reload nginx || info "nginx recarga fallida (revisa la configuración)."
fi

# final checks
echo
ok "Despliegue de /etc completado."
echo "Backups (si existían archivos previos) terminan en *.bak.$BACKUP_SUFFIX"
echo "Comprueba el estado de los servicios:"
echo "  sudo systemctl status safepath-backend safepath-dashboard safepath-scanner.timer"
echo "Ver logs en journalctl:"
echo "  sudo journalctl -u safepath-backend -f"
echo "  sudo journalctl -u safepath-dashboard -f"
echo "  sudo journalctl -u safepath-scanner -f"
