#!/bin/bash
# =========================================================
#  Descripción: Integra Snort (snort-server) con Wazuh
#  - Instala/configura Wazuh Agent en la instancia de Snort
#  - Configura lectura de logs de Snort en Wazuh
#  - Idempotente, sin hardcodear IPs
# =========================================================

SCRIPT_START=$(date +%s)

format_time() {
    local total=$1
    local minutes=$((total / 60))
    local seconds=$((total % 60))
    echo "${minutes} minutos y ${seconds} segundos"
}

echo "===================================================="
echo " Integración Snort 3  ➜  Wazuh Manager (OpenStack) "
echo "===================================================="

# ===== Activar entorno virtual =====
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
    echo "[✔] Variables de OpenStack cargadas correctamente."
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
WAZUH_INSTANCE_NAME="wazuh-manager"

SSH_USER="debian"
SSH_KEY_PATH="$HOME/nics-cyberlab-A/my_key.pem"
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

SNORT_LOG_PATH="/var/log/snort/alert_fast.txt"

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

WAZUH_EXISTS=$(openstack server list -f value -c Name | grep -w "$WAZUH_INSTANCE_NAME" || true)
if [[ -z "$WAZUH_EXISTS" ]]; then
    echo "[✖] No se ha encontrado la instancia de Wazuh: '$WAZUH_INSTANCE_NAME'"
    echo "    Asegúrate de haber ejecutado op+wazuh.sh antes."
    exit 1
fi

echo "[✔] Instancias de Snort y Wazuh detectadas."
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

get_first_ip_from_addresses() {
    local server_name="$1"
    local addrs
    addrs=$(openstack server show "$server_name" -f value -c addresses)
    echo "$addrs" | grep -oE '([0-9]+\.){3}[0-9]+' | head -n1
}

# --- SNORT ---
SNORT_ID=$(get_server_id "$SNORT_INSTANCE_NAME")
SNORT_PORT_ID=$(get_first_port_id_for_server "$SNORT_ID")
SNORT_FLOATING_IP=$(get_floating_ip_for_port "$SNORT_PORT_ID")
SNORT_PRIVATE_IP=$(get_first_ip_from_addresses "$SNORT_INSTANCE_NAME")

# --- WAZUH ---
WAZUH_ID=$(get_server_id "$WAZUH_INSTANCE_NAME")
WAZUH_PORT_ID=$(get_first_port_id_for_server "$WAZUH_ID")
WAZUH_FLOATING_IP=$(get_floating_ip_for_port "$WAZUH_PORT_ID")
WAZUH_PRIVATE_IP=$(get_first_ip_from_addresses "$WAZUH_INSTANCE_NAME")

if [[ -z "$SNORT_PORT_ID" ]]; then
    echo "[✖] No se ha encontrado ningún puerto para la instancia '$SNORT_INSTANCE_NAME'"
    openstack port list --device-id "$SNORT_ID"
    exit 1
fi

if [[ -z "$SNORT_FLOATING_IP" ]]; then
    echo "[✖] No se ha encontrado ninguna Floating IP asociada al puerto $SNORT_PORT_ID (Snort)."
    echo "    Salida de 'openstack floating ip list' para depuración:"
    openstack floating ip list
    exit 1
fi

if [[ -z "$WAZUH_PORT_ID" ]]; then
    echo "[✖] No se ha encontrado ningún puerto para la instancia '$WAZUH_INSTANCE_NAME'"
    openstack port list --device-id "$WAZUH_ID"
    exit 1
fi

if [[ -z "$WAZUH_FLOATING_IP" ]]; then
    echo "[✖] No se ha encontrado ninguna Floating IP asociada al puerto $WAZUH_PORT_ID (Wazuh)."
    echo "    Salida de 'openstack floating ip list' para depuración:"
    openstack floating ip list
    exit 1
fi

echo "[✔] SNORT  - ID: $SNORT_ID  | Port: $SNORT_PORT_ID  | IP fija: $SNORT_PRIVATE_IP  | IP flotante: $SNORT_FLOATING_IP"
echo "[✔] WAZUH  - ID: $WAZUH_ID  | Port: $WAZUH_PORT_ID  | IP fija: $WAZUH_PRIVATE_IP  | IP flotante: $WAZUH_FLOATING_IP"
echo "-------------------------------------------"

# =========================
# ESPERA SSH A SNORT
# =========================
echo "[+] Comprobando conexión SSH con Snort ($SNORT_FLOATING_IP)..."
SSH_TIMEOUT=60
SSH_START=$(date +%s)

ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "$SNORT_FLOATING_IP" >/dev/null 2>&1

until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" \
          "$SSH_USER@$SNORT_FLOATING_IP" "echo ok" >/dev/null 2>&1; do
    sleep 5
    echo -n "."
    NOW=$(date +%s)
    if (( NOW - SSH_START > SSH_TIMEOUT )); then
        echo
        echo "[✖] Timeout al intentar conectar por SSH con Snort ($SNORT_FLOATING_IP)"
        exit 1
    fi
done

echo
echo "[✔] SSH disponible en Snort ($SNORT_FLOATING_IP)"
echo "-------------------------------------------"

# ===========================================
# INSTALAR / CONFIGURAR WAZUH AGENT EN SNORT
# ===========================================
echo "🔹 Integrando Snort con Wazuh (instalación/configuración de Wazuh agent)..."

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$SSH_USER@$SNORT_FLOATING_IP" <<EOF
set -e

WAZUH_MANAGER_IP="$WAZUH_FLOATING_IP"
SNORT_LOG_PATH="$SNORT_LOG_PATH"
AGENT_NAME="$SNORT_INSTANCE_NAME"

echo "[+] Actualizando paquetes base..."
sudo apt-get update -y

echo "[+] Instalando dependencias necesarias para repositorio Wazuh..."
sudo apt-get install -y curl gnupg apt-transport-https

# --- Añadir clave GPG de Wazuh (idempotente) ---
if [ ! -f /usr/share/keyrings/wazuh.gpg ]; then
  echo "[+] Añadiendo clave GPG de Wazuh..."
  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
    | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
  sudo chmod 644 /usr/share/keyrings/wazuh.gpg
else
  echo "[i] Clave GPG de Wazuh ya presente."
fi

# --- Añadir repositorio Wazuh (idempotente) ---
if [ ! -f /etc/apt/sources.list.d/wazuh.list ]; then
  echo "[+] Añadiendo repositorio APT de Wazuh..."
  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
    | sudo tee /etc/apt/sources.list.d/wazuh.list >/dev/null
else
  echo "[i] Repositorio Wazuh ya definido."
fi

echo "[+] Actualizando índices APT..."
sudo apt-get update -y

# --- Instalar Wazuh agent (idempotente) ---
echo "[+] Instalando / actualizando Wazuh agent..."
sudo WAZUH_MANAGER="\$WAZUH_MANAGER_IP" WAZUH_AGENT_NAME="\$AGENT_NAME" apt-get install -y wazuh-agent

# --- Asegurar configuración del manager en ossec.conf ---
OSSEC_CONF="/var/ossec/etc/ossec.conf"
if [ -f "\$OSSEC_CONF" ]; then
  echo "[+] Ajustando <address> del manager en ossec.conf a \$WAZUH_MANAGER_IP..."
  sudo sed -i '0,/<address>/{s#<address>.*</address>#<address>'"\$WAZUH_MANAGER_IP"'</address>#}' "\$OSSEC_CONF"
else
  echo "[!] No se encuentra \$OSSEC_CONF. Revisa instalación del agente."
fi

# --- Asegurar bloque <localfile> para logs de Snort ---
if [ -f "\$OSSEC_CONF" ]; then
  if ! grep -q "\$SNORT_LOG_PATH" "\$OSSEC_CONF"; then
    echo "[+] Añadiendo bloque <localfile> para logs de Snort a ossec.conf..."
    sudo tee -a "\$OSSEC_CONF" >/dev/null <<'EOSNORT'
  <localfile>
    <log_format>snort-full</log_format>
    <location>/var/log/snort/alert_fast.txt</location>
  </localfile>
EOSNORT
  else
    echo "[i] Bloque de Snort ya presente en ossec.conf. No se duplica."
  fi
fi

# --- Asegurar existencia del fichero de logs de Snort ---
echo "[+] Asegurando que existe el fichero de logs de Snort: \$SNORT_LOG_PATH"
sudo mkdir -p /var/log/snort
sudo touch "\$SNORT_LOG_PATH"
sudo chown -R debian:debian /var/log/snort || true

# --- Reiniciar Wazuh agent ---
echo "[+] Reiniciando Wazuh agent..."
sudo systemctl daemon-reload || true
sudo systemctl enable wazuh-agent >/dev/null 2>&1 || true
sudo systemctl restart wazuh-agent

echo "[+] Estado actual de wazuh-agent:"
sudo systemctl status wazuh-agent --no-pager | head -n 10 || true

EOF

echo "-------------------------------------------"
echo "[✔] Integración Snort ➜ Wazuh completada."
echo "[✔] Snort envía logs a: $SNORT_LOG_PATH"
echo "[✔] Wazuh agent configurado hacia manager: $WAZUH_FLOATING_IP"

SCRIPT_END=$(date +%s)
SCRIPT_TIME=$((SCRIPT_END - SCRIPT_START))

echo "===================================================="
echo "[⏱] Tiempo TOTAL del script: $(format_time $SCRIPT_TIME)"
echo "===================================================="

echo
echo "Resumen de integración:"
echo "  - Instancia Snort : $SNORT_INSTANCE_NAME  ($SNORT_FLOATING_IP)"
echo "  - Instancia Wazuh : $WAZUH_INSTANCE_NAME ($WAZUH_FLOATING_IP)"
echo "  - Fichero de logs : $SNORT_LOG_PATH"
echo
echo "Comprobaciones recomendadas:"
echo
echo " Terminal 1 (en snort-server) – Snort capturando tráfico:"
echo "   ssh -i $SSH_KEY_PATH $SSH_USER@$SNORT_FLOATING_IP"
echo "   sudo snort -i ens3 -c /etc/snort/snort.lua -A alert_fast -k none -l /var/log/snort"
echo
echo " Terminal 2 (en snort-server) – Ver los logs que leerá Wazuh:"
echo "   sudo tail -f /var/log/snort/alert_fast.txt"
echo
echo " Terminal 3 (cliente externo) – Generar tráfico ICMP contra la IP de Snort:"
echo "   ping -c 4 <IP_tarjeta_snort>"
echo
echo " En Wazuh Manager (UI):"
echo "   - Accede al dashboard (https://$WAZUH_FLOATING_IP)"
echo "   - Ve a Threat Intelligence ➜ Threat Hunting"
echo "   - Selecciona el agente correspondiente (snort-server) y revisa Events."
echo
echo "Si reinstalas Snort o cambian las IPs, puedes volver a lanzar este script sin romper nada."
