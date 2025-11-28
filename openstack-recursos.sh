#!/bin/bash
# ==============================================
# Despliegue de parámetros para OpenStack
# Objetivo: Comprobar y crear recursos mínimos
# para poder lanzar una instancia
# ==============================================

# --------- CONFIGURACIÓN BÁSICA ---------------

# ===== Activar entorno virtual =====
echo "🔹 Activando primero el entorno virtual de OpenStack..."
step_start=$(date +%s)
if [[ -d "openstack-installer/openstack_venv" ]]; then
    source openstack-installer/openstack_venv/bin/activate
    echo "[✔] Entorno virtual 'openstack_venv' activado correctamente."
else
    echo "[✖] No se encontró el entorno 'openstack_venv'. Ejecuta primero openstack-installer.sh"
    exit 1
fi
step_end=$(date +%s)
echo "-------------------------------------------"
sleep 1

# ===== Cargar variables de entorno OpenStack =====
if [[ -f "admin-openrc.sh" ]]; then
    echo "[+] Cargando variables del entorno OpenStack (admin-openrc.sh)..."
    source admin-openrc.sh
    echo "[✔] Variables cargadas correctamente."
    echo "-------------------------------------------"
    sleep 1
else
    echo "[✖] No se encontró 'admin-openrc.sh'."
    exit 1
fi

# Flavors y sus recursos
declare -A FLAVORS_DEF=(
  [T_1CPU_2GB]="--ram 2048  --vcpus 1 --disk 20"
  [S_2CPU_4GB]="--ram 4096  --vcpus 2 --disk 40"
  [M_4CPU_8GB]="--ram 8192  --vcpus 4 --disk 80"
  [L_6CPU_12GB]="--ram 12288 --vcpus 6 --disk 120"
)

# Imágenes locales
UBUNTU_IMG="ubuntu-22.04.5-jammy.qcow2"
DEBIAN_IMG="debian-12-generic.qcow2"
KALI_IMG_RAW="disk.raw"
KALI_IMG_QCOW2="kali-linux-2025.2.qcow2"

# Redes
NETWORK_EXT_NAME="net_external_01"
SUBNET_EXT_NAME="subnet_net_external_01"
EXT_SUBNET_RANGE="10.0.2.0/24"
EXT_GATEWAY_IP="10.0.2.1"

NETWORK_PRIV="net_private_01"
SUBNET_PRIV="subnet_net_private_01"
PRIV_SUBNET_RANGE="192.168.100.0/24"
PRIV_GATEWAY_IP="192.168.100.1"

ROUTER_PRIV="router_private_01"

USE_EXTERNAL_NET=1

# Seguridad
SEC_GROUP="sg_basic"
RULES_TCP=(21 22 25 53 80 443 1514 1515 2222 5601 7443 8022 8834 8888 17443)
RULES_UDP=(1514 1515)

# Claves
KEYPAIR="my_key"
KEYPAIR_PRIV_FILE="${KEYPAIR}.pem"
KEYPAIR_PUB_FILE="${KEYPAIR}.pem.pub"

PASS_FILE="set-password.yml"

# --------- FUNCIONES AUXILIARES -------------

die() {
  echo "[✖] $*" >&2
  exit 1
}

run_or_die() {
  "$@" || die "Error ejecutando: $*"
}

find_existing_external_net() {
  openstack network list --external -f value -c Name || return 1
}

echo "🔹 Iniciando comprobación de recursos en OpenStack..."

# ==============================================
# FLAVORS
# ==============================================
echo "🔹 Comprobando flavors..."
for flavor in "${!FLAVORS_DEF[@]}"; do
  if openstack flavor show "$flavor" &>/dev/null; then
    echo "[✔] Flavor existente: $flavor"
  else
    echo "[+] Creando flavor: $flavor (${FLAVORS_DEF[$flavor]})"
    run_or_die openstack flavor create "$flavor" ${FLAVORS_DEF[$flavor]}
  fi
done

# ==============================================
# IMÁGENES
# ==============================================
echo "🔹 Comprobando y creando imágenes (Ubuntu + Debian + Kali)..."

IMG_LIST=("ubuntu-22.04" "debian-12" "kali-linux")

for img_name in "${IMG_LIST[@]}"; do
  if openstack image show "$img_name" &>/dev/null; then
    echo "[✔] Imagen existente en OpenStack: $img_name"
    continue
  fi

  case "$img_name" in
    "ubuntu-22.04")
      if [ ! -f "$UBUNTU_IMG" ]; then
        echo "[+] Descargando Ubuntu 22.04.5..."
        run_or_die wget -c \
          https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
          -O "$UBUNTU_IMG"
      fi
      IMG_FILE="$UBUNTU_IMG"
      ;;
    "debian-12")
      if [ ! -f "$DEBIAN_IMG" ]; then
        echo "[+] Descargando Debian 12..."
        run_or_die wget -c \
          https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
          -O "$DEBIAN_IMG"
      fi
      IMG_FILE="$DEBIAN_IMG"
      ;;
    "kali-linux")
      if [ ! -f "$KALI_IMG_QCOW2" ]; then
        echo "[+] Descargando Kali Linux 2025.2..."
        run_or_die wget -c \
          https://kali.download/cloud-images/kali-2025.2/kali-linux-2025.2-cloud-genericcloud-amd64.tar.xz \
          -O kali-linux-2025.2-cloud-genericcloud-amd64.tar.xz

        echo "[+] Extrayendo disk.raw..."
        run_or_die tar -xvf kali-linux-2025.2-cloud-genericcloud-amd64.tar.xz

        if ! command -v qemu-img &>/dev/null; then
          echo "[!] 'qemu-img' no está instalado. Instalando..."
          if [ "$(id -u)" -ne 0 ]; then
            sudo apt update && sudo apt install -y qemu-utils
          else
            apt update && apt install -y qemu-utils
          fi
        fi

        echo "[+] Convirtiendo disk.raw a QCOW2..."
        run_or_die qemu-img convert -f raw -O qcow2 "$KALI_IMG_RAW" "$KALI_IMG_QCOW2"
      fi
      IMG_FILE="$KALI_IMG_QCOW2"
      ;;
  esac

  echo "[+] Creando imagen en OpenStack: $img_name"
  run_or_die openstack image create "$img_name" \
    --file "$IMG_FILE" \
    --disk-format qcow2 \
    --container-format bare
done

# ==============================================
# RED EXTERNA
# ==============================================
echo "🔹 Comprobando red externa..."

NETWORK_EXT_ID=""
if openstack network show "$NETWORK_EXT_NAME" &>/dev/null; then
  echo "[✔] Red externa existente: $NETWORK_EXT_NAME"
  NETWORK_EXT_ID=$(openstack network show "$NETWORK_EXT_NAME" -f value -c id)
else
  echo "[+] Intentando crear red externa $NETWORK_EXT_NAME..."
  if openstack network create "$NETWORK_EXT_NAME" \
      --external \
      --provider-physical-network physnet1 \
      --provider-network-type flat >/tmp/net_create.log 2>&1; then
    NETWORK_EXT_ID=$(openstack network show "$NETWORK_EXT_NAME" -f value -c id)
    echo "[✔] Red externa creada: $NETWORK_EXT_NAME"
  else
    echo "[!] No se pudo crear la red externa (409 o physnet ocupado)."
    EXISTING_EXT_NETS=$(find_existing_external_net)

    if [ -z "$EXISTING_EXT_NETS" ]; then
      USE_EXTERNAL_NET=0
      NETWORK_EXT_ID=""
      echo "[!] No hay redes externas disponibles. Continuando sin red externa."
    else
      NETWORK_EXT_NAME=$(echo "$EXISTING_EXT_NETS" | head -n1)
      NETWORK_EXT_ID=$(openstack network show "$NETWORK_EXT_NAME" -f value -c id)
      echo "[✔] Usando red externa existente: $NETWORK_EXT_NAME"
    fi
  fi
fi

if [ "$USE_EXTERNAL_NET" -eq 1 ]; then
  if openstack subnet show "$SUBNET_EXT_NAME" &>/dev/null; then
    echo "[✔] Subred externa existente: $SUBNET_EXT_NAME"
  else
    echo "[+] Creando subred externa $SUBNET_EXT_NAME..."
    run_or_die openstack subnet create "$SUBNET_EXT_NAME" \
      --network "$NETWORK_EXT_ID" \
      --subnet-range "$EXT_SUBNET_RANGE" \
      --gateway "$EXT_GATEWAY_IP" \
      --dns-nameserver 8.8.8.8
  fi
else
  echo "[!] Saltando creación de subred externa."
fi

# ==============================================
# RED PRIVADA + ROUTER
# ==============================================
echo "🔹 Comprobando red privada..."

if openstack network show "$NETWORK_PRIV" &>/dev/null; then
  echo "[✔] Red privada existente: $NETWORK_PRIV"
else
  echo "[+] Creando red privada $NETWORK_PRIV..."
  run_or_die openstack network create "$NETWORK_PRIV"
fi

if openstack subnet show "$SUBNET_PRIV" &>/dev/null; then
  echo "[✔] Subred privada existente: $SUBNET_PRIV"
else
  echo "[+] Creando subred privada $SUBNET_PRIV..."
  run_or_die openstack subnet create "$SUBNET_PRIV" \
    --network "$NETWORK_PRIV" \
    --subnet-range "$PRIV_SUBNET_RANGE" \
    --gateway "$PRIV_GATEWAY_IP" \
    --dns-nameserver 8.8.8.8
fi

if openstack router show "$ROUTER_PRIV" &>/dev/null; then
  echo "[✔] Router existente: $ROUTER_PRIV"
else
  echo "[+] Creando router $ROUTER_PRIV..."
  run_or_die openstack router create "$ROUTER_PRIV"
fi

echo "[+] Configurando gateway e interfaz del router..."
if [ "$USE_EXTERNAL_NET" -eq 1 ]; then
  run_or_die openstack router set "$ROUTER_PRIV" --external-gateway "$NETWORK_EXT_ID"
fi

openstack router add subnet "$ROUTER_PRIV" "$SUBNET_PRIV" 2>/dev/null || \
  echo "[!] La interfaz ya estaba añadida."

# ==============================================
# SECURITY GROUP (BLOQUE MEJORADO)
# ==============================================
echo "🔹 Comprobando grupo de seguridad..."

if openstack security group show "$SEC_GROUP" &>/dev/null; then
  echo "[✔] Grupo existente: $SEC_GROUP"
else
  echo "[+] Creando security group $SEC_GROUP..."
  run_or_die openstack security group create "$SEC_GROUP"
fi

echo "[+] Configurando reglas de seguridad..."

# ===== Reglas TCP =====
for port in "${RULES_TCP[@]}"; do
  if ! openstack security group rule list "$SEC_GROUP" -f value \
      -c "Port Range" -c Protocol | grep -q "^$port:$port tcp$"; then

    echo "[+] Añadiendo regla TCP para puerto $port..."
    if openstack security group rule create --proto tcp --dst-port "$port" "$SEC_GROUP" &>/dev/null; then
      echo "[✔] Regla TCP $port añadida correctamente."
    else
      echo "[✖] Error al añadir regla TCP $port."
    fi

  else
    echo "[✔] Regla TCP ya existente para puerto $port."
  fi
done

# ===== Reglas UDP =====
for port in "${RULES_UDP[@]}"; do
  if ! openstack security group rule list "$SEC_GROUP" -f value \
      -c "Port Range" -c Protocol | grep -q "^$port:$port udp$"; then

    echo "[+] Añadiendo regla UDP para puerto $port..."
    if openstack security group rule create --proto udp --dst-port "$port" "$SEC_GROUP" &>/dev/null; then
      echo "[✔] Regla UDP $port añadida correctamente."
    else
      echo "[✖] Error al añadir regla UDP $port."
    fi

  else
    echo "[✔] Regla UDP ya existente para puerto $port."
  fi
done

# ===== Reglas ICMP =====
if ! openstack security group rule list "$SEC_GROUP" -f value -c Protocol | grep -q "^icmp$"; then
  echo "[+] Añadiendo regla ICMP..."
  if openstack security group rule create --proto icmp "$SEC_GROUP" &>/dev/null; then
    echo "[✔] Regla ICMP añadida correctamente."
  else
    echo "[✖] Error al añadir regla ICMP."
  fi
else
  echo "[✔] Regla ICMP ya existente."
fi

# ==============================================
# KEYPAIR (LIMPIAR Y GENERAR NUEVO)
# ==============================================
echo "🔹 Gestionando keypair..."

# Eliminar keypair existente en OpenStack
if openstack keypair show "$KEYPAIR" &>/dev/null; then
    echo "[!] Keypair '$KEYPAIR' ya existe en OpenStack. Eliminando..."
    openstack keypair delete "$KEYPAIR" \
        || die "No se pudo eliminar el keypair existente en OpenStack"
fi

# Eliminar archivos locales si existen
if [[ -f "$KEYPAIR" ]]; then
    echo "[!] Eliminando clave privada local '$KEYPAIR'"
    rm -f "$KEYPAIR"
fi
if [[ -f "${KEYPAIR}.pub" ]]; then
    echo "[!] Eliminando clave pública local '${KEYPAIR}.pub'"
    rm -f "${KEYPAIR}.pub"
fi

# Generar nuevo par de claves
echo "[+] Generando nuevo par de claves para repo..."
ssh-keygen -t rsa -b 4096 -f "$KEYPAIR" -N "" -C "key for OpenStack" \
    || die "No se pudo generar el keypair"

# Ajustar permisos
chmod 600 "$KEYPAIR"
chmod 644 "${KEYPAIR}.pub"

# Crear keypair en OpenStack usando la clave pública
openstack keypair create --public-key "${KEYPAIR}.pub" "$KEYPAIR" \
    || die "No se pudo registrar el keypair en OpenStack"

echo "[✔] Keypair '$KEYPAIR' generado y registrado correctamente."


# ==============================================
# CLOUD-INIT
# ==============================================
if [ ! -f "$PASS_FILE" ]; then
  echo "[+] Creando fichero cloud-init por defecto..."
  cat > "$PASS_FILE" << EOF
#cloud-config
password: nics2025!
chpasswd: { expire: False }
ssh_pwauth: True
EOF
fi

echo
echo "[✔] Comprobación y creación de recursos completada."
echo "Ejemplo para lanzar una instancia:"
echo "[➜] openstack server create \\"
echo "      --flavor T_1CPU_2GB \\"
echo "      --image ubuntu-22.04 \\"
echo "      --network $NETWORK_PRIV \\"
echo "      --security-group $SEC_GROUP \\"
echo "      --key-name $KEYPAIR \\"
echo "      --user-data $PASS_FILE \\"
echo "      mi_instancia_01"
