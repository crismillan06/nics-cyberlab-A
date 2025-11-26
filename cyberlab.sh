#!/bin/bash
# ==================================================
# Script de despliegue automático de NICS | CyberLab
# ==================================================

set -e  # Detener el script ante cualquier error

# Función para medir el tiempo de ejecución de cada tarea
function timer() {
    local start_time=$1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    printf "%02d min %02d seg\n" $((duration / 60)) $((duration % 60))
}

# Marca de inicio general
overall_start=$(date +%s)

echo "============================================="
echo "🚀 Iniciando despliegue de NICS | CyberLab..."
echo "============================================="
sleep 1

# Paso 1: Instalación de OpenStack
echo "🔹 Iniciando instalador de OpenStack..."
step_start=$(date +%s)
bash openstack-installer/openstack-installer.sh
echo "[✔] Instalación de OpenStack completada en $(timer $step_start)"
echo "-------------------------------------------"
sleep 2

# ===== Activar entorno virtual =====
echo "🔹 Activando entorno virtual de OpenStack..."
step_start=$(date +%s)
if [[ -d "openstack-installer/openstack_venv" ]]; then
    source openstack-installer/openstack_venv/bin/activate
    echo "[✔] Entorno virtual 'openstack_venv' activado correctamente."
else
    echo "[✖] No se encontró el entorno 'openstack_venv'."
    exit 1
fi
echo "-------------------------------------------"
sleep 2

# Cargar variables de entorno OpenStack
if [[ -f "admin-openrc.sh" ]]; then
    echo "[+] Cargando variables del entorno OpenStack (admin-openrc.sh)..."
    source admin-openrc.sh
    echo "[✔] Variables cargadas correctamente."
    echo "-------------------------------------------"
fi
sleep 1

#Paso 2: Levantar infraestructura de la red
echo "🔹 Construyendo reglas de iptables para el correcto funcionamiento de la red..."
sudo bash openstack-installer/setup-veth.sh

# Paso 3: Generación de credenciales
echo "🔹 Generando credenciales OpenStack..."
step_start=$(date +%s)
bash generate_app_cred_openrc_from_clouds.sh
echo "[✔] Credenciales generadas correctamente en $(timer $step_start)"
echo "-------------------------------------------"
sleep 2

# Paso 4: Arranque del dashboard (en segundo plano)
echo "🔹 Iniciando dashboard de NICS | CyberLab..."
step_start=$(date +%s)

# Se lanza el dashboard en segundo plano y guardamos el PID
bash start_dashboard.sh > dashboard_log.log 2>&1 &
DASH_PID=$!

sleep 5  # espera para que el servicio levante
echo "[✔] Dashboard iniciado en $(timer $step_start)"
echo "-------------------------------------------"
sleep 1

# Información del proceso
echo
echo "Accede al dashboard desde tu navegador:"
echo "👉 http://localhost:5001"
echo
echo "⚙️  El dashboard se está ejecutando en segundo plano."
echo "PID del proceso: $DASH_PID"
echo "Para detenerlo, ejecuta el siguiente comando:"
echo "[!] kill $DASH_PID"
echo
echo "Log en tiempo real: tail -f dashboard_log.log"
echo "============================================="

# Extraer valores desde clouds.yaml
AUTH_URL=$(grep -m1 "auth_url:" /etc/kolla/clouds.yaml | awk '{print $2}' | sed 's/:5000//')
USERNAME=$(grep -m1 "username:" /etc/kolla/clouds.yaml | awk '{print $2}')
PASSWORD=$(grep -m1 "password:" /etc/kolla/clouds.yaml | awk '{print $2}')

echo "Si quiere acceder manualmente al dashboard de OpenStack:"
echo "[➜] URL del Dashboard:   ${AUTH_URL}"
echo "[➜] Usuario:             ${USERNAME}"
echo "[➜] Contraseña:          ${PASSWORD}"
echo "----------------------------------------------------------"
echo "A continuación se desactivará el entorno, si quiere activarlo manualmente ejecute en el siguiente orden:"
echo "[➜] source openstack-installer/openstack_venv/bin/activate"
echo "[➜] source admin-openrc.sh"
echo "----------------------------------------------------------"

# Desactivar entorno al salir del script
deactivate 2>/dev/null || true

echo "[⏱] Tiempo total de despliegue: $(timer $overall_start)"
