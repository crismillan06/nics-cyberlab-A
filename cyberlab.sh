#!/bin/bash
# ============================================
# Script de despliegue automático de CyberRange | CyberLab UMA 
# Fecha: $(date +%Y-%m-%d)
# ============================================

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

echo "=============================================="
echo "🚀 Iniciando despliegue de CyberLab de NICS..."
echo "=============================================="
sleep 1

# Paso 1: Instalación de OpenStack
echo "▶️  Ejecutando instalador de OpenStack..."
step_start=$(date +%s)
bash openstack-installer/openstack-installer.sh
echo "✅ Instalación de OpenStack completada en $(timer $step_start)"
echo "-------------------------------------------"
sleep 2

# ===== Activar entorno virtual =====
echo "🌍 Activando entorno virtual de OpenStack..."
step_start=$(date +%s)
if [[ -d "openstack-installer/openstack_venv" ]]; then
    source openstack-installer/openstack_venv/bin/activate
    echo "✅ Entorno virtual 'openstack_venv' activado correctamente."
else
    echo "❌ No se encontró el entorno 'openstack_venv'."
    exit 1
fi
echo "Entorno activado en $(timer $step_start)"
echo "-------------------------------------------"
sleep 2

echo "Configurado estructura de redes..."
sudo bash uplinkbridge.sh
sleep 1

# (Opcional) Cargar variables de entorno OpenStack
if [[ -f "admin-openrc.sh" ]]; then
    echo "🔐 Cargando variables del entorno OpenStack (admin-openrc.sh)..."
    source admin-openrc.sh
    echo "✅ Variables cargadas correctamente."
    echo "-------------------------------------------"
    sleep 1
fi

# Paso 2: Generación de credenciales
echo "▶️  Generando credenciales OpenStack..."
step_start=$(date +%s)
bash generate_app_cred_openrc_from_clouds.sh
echo "✅ Credenciales generadas correctamente en $(timer $step_start)"
echo "-------------------------------------------"
sleep 2

# Paso 3: Arranque del dashboard (en segundo plano con PID visible)
echo "▶️  Iniciando dashboard de CyberRange..."
step_start=$(date +%s)

# Lanzamos el dashboard en segundo plano y guardamos el PID
bash start_dashboard.sh > dashboard_log.log 2>&1 &
DASH_PID=$!

sleep 5  # espera breve para que el servicio levante
echo "✅ Dashboard iniciado en $(timer $step_start)"
echo "-------------------------------------------"
sleep 1

# Mostrar información del proceso
echo ""
echo "🌐 Accede al dashboard desde tu navegador:"
echo "👉 http://localhost:5001"
echo ""
echo "⚙️  El dashboard se está ejecutando en segundo plano."
echo "🔢  PID del proceso: $DASH_PID"
echo "🧩  Para detenerlo, ejecuta el siguiente comando:"
echo ""
echo "   kill $DASH_PID"
echo ""
echo "📜  Log en tiempo real: tail -f dashboard_log.log"
echo "==========================================="

# Desactivar entorno al salir del script
deactivate 2>/dev/null || true

# Tiempo total
echo ""
echo "🕒 Tiempo total de despliegue: $(timer $overall_start)"
echo ""
