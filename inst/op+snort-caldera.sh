#!/bin/bash
# =========================================================
#  Descripción: Integra Caldera (agente Sandcat)
#  en la instancia snort-server (Debian 12)
# =========================================================

SCRIPT_START=$(date +%s)

format_time() {
    local total=$1
    local minutes=$((total / 60))
    local seconds=$((total % 60))
    echo "${minutes} minutos y ${seconds} segundos"
}

echo "===================================================="
echo " Integración Caldera ➜ snort-server (agente)       "
echo "===================================================="

# ===== Activar entorno virtual de OpenStack =====
echo "🔹 Activando entorno virtual de OpenStack..."
if [[ -d "openstack-installer/openstack_venv" ]]; then
    # shellcheck disable=SC1091
    source openstack-installer/openstack_venv/bin/activate
    echo "[✔] Entorno virtual 'openstack_venv' activado correctamente."
else
    echo "[✖] No se encontró el entorno 'openstack_venv'. Ejecuta primero openstack-recursos.sh"
    exit 1
fi
echo "-------------------------------------------"
sleep 1

# ===== Cargar variables de entorno OpenStack =====
if [[ -f "admin-openrc.sh" ]]; then
    echo "[+] Cargando variables del entorno OpenStack (admin-openrc.sh)..."
    # shellcheck disable=SC1091
    source admin-openrc.sh
    echo "[✔] Credenciales OpenStack cargadas para admin ($OS_USERNAME)"
    echo "-------------------------------------------"
    sleep 1
else
    echo "[✖] No se encontró 'admin-openrc.sh'. Ejecuta primero openstack-recursos.sh"
    exit 1
fi

# =========================
# CONFIGURACIÓN GENERAL
# =========================
SNORT_INSTANCE_NAME="snort-server"
CALDERA_INSTANCE_NAME="caldera-server"

SSH_USER="debian"
SSH_KEY_PATH="$HOME/nics-cyberlab-A/my_key.pem"
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

AGENT_DIR="/opt/caldera"
AGENT_PATH="$AGENT_DIR/caldera-agent"
SERVICE_PATH="/etc/systemd/system/caldera-agent.service"
CALDERA_PORT="8888"
CALDERA_GROUP="red"   # grupo del agente en Caldera

# =========================
# COMPROBACIONES BÁSICAS
# =========================
echo "🔹 Verificando requisitos básicos..."

if ! command -v openstack >/dev/null 2>&1; then
    echo "[✖] No se encuentra el comando 'openstack'. Revisa tu entorno."
    exit 1
fi

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "[✖] No se encuentra la clave privada SSH: $SSH_KEY_PATH"
    exit 1
fi

SNORT_EXISTS=$(openstack server list -f value -c Name | grep -w "$SNORT_INSTANCE_NAME" || true)
if [[ -z "$SNORT_EXISTS" ]]; then
    echo "[✖] No se ha encontrado la instancia de Snort: '$SNORT_INSTANCE_NAME'"
    echo "    Asegúrate de haber ejecutado op+snort.sh antes."
    exit 1
fi

CALDERA_EXISTS=$(openstack server list -f value -c Name | grep -w "$CALDERA_INSTANCE_NAME" || true)
if [[ -z "$CALDERA_EXISTS" ]]; then
    echo "[✖] No se ha encontrado la instancia de Caldera: '$CALDERA_INSTANCE_NAME'"
    echo "    Asegúrate de haber ejecutado el script de Caldera antes."
    exit 1
fi

echo "[✔] Instancias de Snort y Caldera detectadas."
echo "-------------------------------------------"

# ===============================
# FUNCIONES PARA SACAR IPs
# ===============================
get_server_id() {
    local server_name="$1"
    openstack server show "$server_name" -f value -c id
}

get_first_port_id_for_server() {
    local server_id="$1"
    openstack port list --device-id "$server_id" -f value -c ID | head -n1
}

get_floating_ip_for_port() {
    local port_id="$1"
    openstack floating ip list -f value -c "Floating IP Address" -c Port \
      | awk -v port="$port_id" '$2==port {print $1; exit}'
}

get_private_ip_from_addresses() {
    local server_name="$1"
    local addrs
    addrs=$(openstack server show "$server_name" -f value -c addresses)
    # Coge la ÚLTIMA IP que aparezca (en tu entorno es la 192.168.100.X)
    echo "$addrs" | grep -oE '([0-9]+\.){3}[0-9]+' | tail -n1
}

# --- SNORT ---
SNORT_ID=$(get_server_id "$SNORT_INSTANCE_NAME")
SNORT_PORT_ID=$(get_first_port_id_for_server "$SNORT_ID")
SNORT_FLOATING_IP=$(get_floating_ip_for_port "$SNORT_PORT_ID")
SNORT_PRIVATE_IP=$(get_private_ip_from_addresses "$SNORT_INSTANCE_NAME")

# --- CALDERA ---
CALDERA_ID=$(get_server_id "$CALDERA_INSTANCE_NAME")
CALDERA_PORT_ID=$(get_first_port_id_for_server "$CALDERA_ID")
CALDERA_FLOATING_IP=$(get_floating_ip_for_port "$CALDERA_PORT_ID")
CALDERA_PRIVATE_IP=$(get_private_ip_from_addresses "$CALDERA_INSTANCE_NAME")

# Usaremos SIEMPRE la IP PRIVADA de Caldera para el agente
CALDERA_URL="http://$CALDERA_PRIVATE_IP:$CALDERA_PORT"

if [[ -z "$SNORT_PRIVATE_IP" ]]; then
    echo "[✖] No se ha podido determinar la IP privada de '$SNORT_INSTANCE_NAME'."
    openstack server show "$SNORT_INSTANCE_NAME" -f value -c addresses
    exit 1
fi

if [[ -z "$CALDERA_PRIVATE_IP" ]]; then
    echo "[✖] No se ha podido determinar la IP privada de '$CALDERA_INSTANCE_NAME'."
    openstack server show "$CALDERA_INSTANCE_NAME" -f value -c addresses
    exit 1
fi

echo "[✔] SNORT   - ID: $SNORT_ID    | IP privada: $SNORT_PRIVATE_IP    | IP flotante: ${SNORT_FLOATING_IP:-N/A}"
echo "[✔] CALDERA - ID: $CALDERA_ID  | IP privada: $CALDERA_PRIVATE_IP   | IP flotante: ${CALDERA_FLOATING_IP:-N/A}"
echo "[✔] URL Caldera usada por el agente: $CALDERA_URL"
echo "-------------------------------------------"

# =========================
# ESPERA SSH A SNORT
# =========================
# Para SSH usamos la flotante si existe; si no, la privada.
TARGET_SSH_IP="${SNORT_FLOATING_IP:-$SNORT_PRIVATE_IP}"

echo "[+] Comprobando conexión SSH con snort-server ($TARGET_SSH_IP)..."
SSH_TIMEOUT=60
SSH_START=$(date +%s)

ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "$TARGET_SSH_IP" >/dev/null 2>&1

until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" \
          "$SSH_USER@$TARGET_SSH_IP" "echo ok" >/dev/null 2>&1; do
    sleep 5
    echo -n "."
    NOW=$(date +%s)
    if (( NOW - SSH_START > SSH_TIMEOUT )); then
        echo
        echo "[✖] Timeout al intentar conectar por SSH con Snort ($TARGET_SSH_IP)"
        exit 1
    fi
done

echo
echo "[✔] SSH disponible en snort-server ($TARGET_SSH_IP)"
echo "-------------------------------------------"

# ===========================================
# INSTALAR / CONFIGURAR AGENTE CALDERA EN SNORT
# ===========================================
echo "🔹 Instalando / actualizando agente Caldera en snort-server..."

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$SSH_USER@$TARGET_SSH_IP" <<EOF
set -e

CALDERA_URL="$CALDERA_URL"
AGENT_DIR="$AGENT_DIR"
AGENT_PATH="$AGENT_PATH"
SERVICE_PATH="$SERVICE_PATH"
CALDERA_GROUP="$CALDERA_GROUP"

echo "[+] Actualizando paquetes base..."
sudo apt-get update -y

echo "[+] Instalando curl (si no está ya)..."
sudo apt-get install -y curl

echo "[+] Probando conectividad HTTP con Caldera en \$CALDERA_URL..."
if curl -s --connect-timeout 5 "\$CALDERA_URL" >/dev/null 2>&1; then
  echo "[✔] Caldera responde en \$CALDERA_URL"
else
  echo "[!] No se ha podido contactar con \$CALDERA_URL ahora mismo."
  echo "    El agente igualmente intentará reconectar periódicamente."
fi

echo "[+] Creando directorio para el agente: \$AGENT_DIR"
sudo mkdir -p "\$AGENT_DIR"

echo "[+] Descargando/actualizando agente Sandcat desde Caldera..."
sudo curl -s -X POST -H "file:sandcat.go" -H "platform:linux" "\$CALDERA_URL/file/download" -o "\$AGENT_PATH"
sudo chmod +x "\$AGENT_PATH"

echo "[+] Creando/actualizando servicio systemd para el agente..."

sudo tee "\$SERVICE_PATH" >/dev/null <<EOSVC
[Unit]
Description=Caldera Sandcat Agent (snort-server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=\$AGENT_PATH -server \$CALDERA_URL -group \$CALDERA_GROUP -v
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSVC

echo "[+] Recargando systemd y habilitando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable caldera-agent.service >/dev/null 2>&1 || true
sudo systemctl restart caldera-agent.service

echo "[+] Estado del servicio caldera-agent:"
sudo systemctl status caldera-agent.service --no-pager | head -n 15 || true

EOF

SCRIPT_END=$(date +%s)
SCRIPT_TIME=$((SCRIPT_END - SCRIPT_START))

echo "-------------------------------------------"
echo "[✔] Agente Caldera desplegado en snort-server."
echo "[✔] Conectando contra: $CALDERA_URL  (grupo: $CALDERA_GROUP)"
echo "===================================================="
echo "[⏱] Tiempo TOTAL del script: $(format_time $SCRIPT_TIME)"
echo "===================================================="

echo
echo "Resumen:"
echo "  - Instancia Snort : $SNORT_INSTANCE_NAME  (SSH: $SSH_USER@${SNORT_FLOATING_IP:-$SNORT_PRIVATE_IP})"
echo "  - Servidor Caldera: $CALDERA_INSTANCE_NAME (URL interna: $CALDERA_URL)"
echo
echo "Comprobaciones recomendadas en snort-server:"
echo
echo "  ssh -i $SSH_KEY_PATH $SSH_USER@${SNORT_FLOATING_IP:-$SNORT_PRIVATE_IP}"
echo "  sudo systemctl status caldera-agent.service"
echo "  sudo journalctl -u caldera-agent.service -f"
echo
echo "En la GUI de Caldera deberías ver el nuevo agente (grupo '$CALDERA_GROUP') conectado."
