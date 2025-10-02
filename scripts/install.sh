#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG (edita estas variables) ---
SAFEPATH_HOME="/opt/safepath"
SAFEPATH_USER="safepath"
DB_NAME="safepath_db"
DB_USER="safepath"
DB_PASSWORD="PUT_STRONG_DB_PASSWORD"   # <<< CAMBIAR
DOMAIN="example.com"                   # <<< CAMBIAR (opcional para nginx/certbot)
UVICORN_WORKERS=2
# -------------------------------------

# check root
if [ "$EUID" -ne 0 ]; then
  echo "Ejecuta este script como root (sudo)."
  exit 1
fi

echo "Instalando paquetes del sistema..."
apt update
apt install -y python3 python3-venv python3-pip build-essential libpq-dev postgresql postgresql-contrib nmap nginx certbot python3-certbot-nginx

# crear usuario sistema si no existe
if ! id "$SAFEPATH_USER" >/dev/null 2>&1; then
  echo "Creando usuario $SAFEPATH_USER..."
  useradd -r -s /usr/sbin/nologin "$SAFEPATH_USER"
fi

# preparar directorios
mkdir -p "$SAFEPATH_HOME"
chown -R "$SAFEPATH_USER":"$SAFEPATH_USER" "$SAFEPATH_HOME"
chmod 750 "$SAFEPATH_HOME"

# AQUI se asume que ya has copiado los ficheros del repo en $SAFEPATH_HOME
# Crear venvs e instalar requirements si existen requirements.txt
echo "Creando virtualenvs e instalando dependencias..."
for comp in backend scanner dashboard; do
  if [ -f "$SAFEPATH_HOME/$comp/requirements.txt" ]; then
    echo " -> $comp"
    sudo -u "$SAFEPATH_USER" bash -lc "python3 -m venv $SAFEPATH_HOME/$comp/venv"
    sudo -u "$SAFEPATH_USER" bash -lc "$SAFEPATH_HOME/$comp/venv/bin/python -m pip install --upgrade pip"
    sudo -u "$SAFEPATH_USER" bash -lc "$SAFEPATH_HOME/$comp/venv/bin/pip install -r $SAFEPATH_HOME/$comp/requirements.txt"
  else
    echo "    (no se encuentra $SAFEPATH_HOME/$comp/requirements.txt, saltando instalación)"
  fi
done

# crear /etc/safepath y escribir env files
mkdir -p /etc/safepath
chown root:"$SAFEPATH_USER" /etc/safepath
chmod 750 /etc/safepath

cat > /etc/safepath/backend.env <<EOF
DATABASE_URL=postgresql+psycopg2://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
UVICORN_WORKERS=$UVICORN_WORKERS
EOF
chmod 640 /etc/safepath/backend.env
chown root:"$SAFEPATH_USER" /etc/safepath/backend.env

cat > /etc/safepath/scanner.env <<EOF
BACKEND_URL=http://127.0.0.1:8000
TARGETS=127.0.0.1
NMAP_TIMEOUT=120
RETRY_POST=3
RETRY_DELAY=2
EOF
chmod 640 /etc/safepath/scanner.env
chown root:"$SAFEPATH_USER" /etc/safepath/scanner.env

cat > /etc/safepath/dashboard.env <<EOF
BACKEND_URL=http://127.0.0.1:8000
EOF
chmod 640 /etc/safepath/dashboard.env
chown root:"$SAFEPATH_USER" /etc/safepath/dashboard.env

# Crear DB / usuario postgres si no existen
echo "Configurando PostgreSQL..."
ROLE_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")
if [ "$ROLE_EXISTS" != "1" ]; then
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
  echo "Usuario postgres $DB_USER creado."
else
  echo "Usuario postgres $DB_USER ya existe. (no creado)"
fi

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
if [ "$DB_EXISTS" != "1" ]; then
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  echo "Base de datos $DB_NAME creada."
else
  echo "Base de datos $DB_NAME ya existe. (no creada)"
fi

# escribir systemd unit files
echo "Escribiendo units systemd..."
cat > /etc/systemd/system/safepath-backend.service <<'EOF'
[Unit]
Description=safepath - Backend (FastAPI + Uvicorn)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=safepath
Group=safepath
WorkingDirectory=/opt/safepath/backend
EnvironmentFile=/etc/safepath/backend.env
ExecStart=/opt/safepath/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers ${UVICORN_WORKERS:-1}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safepath-dashboard.service <<'EOF'
[Unit]
Description=safepath - Dashboard (Streamlit)
After=network.target safepath-backend.service
Requires=safepath-backend.service

[Service]
Type=simple
User=safepath
Group=safepath
WorkingDirectory=/opt/safepath/dashboard
EnvironmentFile=/etc/safepath/dashboard.env
ExecStart=/opt/safepath/dashboard/venv/bin/streamlit run app.py --server.port 8501 --server.address 127.0.0.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safepath-scanner.service <<'EOF'
[Unit]
Description=safepath - Scanner (nmap single run)
After=network.target safepath-backend.service
Requires=safepath-backend.service

[Service]
Type=oneshot
User=safepath
Group=safepath
WorkingDirectory=/opt/safepath/scanner
EnvironmentFile=/etc/safepath/scanner.env
ExecStart=/opt/safepath/scanner/venv/bin/python scanner.py
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safepath-scanner.timer <<'EOF'
[Unit]
Description=safepath - Timer para ejecutar scanner cada 5 minutos

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# recargar systemd y habilitar servicios
systemctl daemon-reload
systemctl enable --now safepath-backend.service || true
systemctl enable --now safepath-dashboard.service || true
systemctl enable --now safepath-scanner.timer || true
systemctl start safepath-scanner.timer || true

echo ""
echo "INSTALACIÓN COMPLETADA (parcial). Revisa mensajes arriba."
echo "Siguientes pasos recomendados:"
echo " - Edita /etc/safepath/backend.env y reemplaza DB_PASSWORD si no lo hiciste"
echo " - Asegúrate de haber llenado TARGETS en /etc/safepath/scanner.env"
echo " - Comprueba estado: sudo systemctl status safepath-backend safepath-dashboard safepath-scanner.timer"
echo " - Si usas nginx: coloca el fichero en /etc/nginx/sites-available/safepath.conf y habilita, luego ejecuta certbot si quieres TLS"
