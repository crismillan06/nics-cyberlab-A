#!/bin/bash
# ============================================================
# Script completo: Instalación OpenStack + Kolla-Ansible
# ============================================================

set -euo pipefail
trap 'echo "⚠️  Error en la línea $LINENO. Abortando."; exit 1;' ERR

echo "🔹 Iniciando despliegue automatizado de OpenStack..."

START_TIME=$(date +%s)

# ============================================================
# 1️⃣ CREAR ENTORNO VIRTUAL
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="$SCRIPT_DIR/openstack_venv"

echo "🔹 Creando entorno virtual en $VENV_PATH..."
sudo apt update -y
sudo apt install -y python3.12 python3.12-venv python3.12-dev libffi-dev gcc libssl-dev

python3.12 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"
export PATH="$VENV_PATH/bin:$PATH"

python -m ensurepip --upgrade
python -m pip install --upgrade pip setuptools wheel

# ============================================================
# 2️⃣ DEPENDENCIAS DEL SISTEMA
# ============================================================
echo "🔹 Instalando dependencias..."
sudo apt install -y git iptables bridge-utils wget curl dbus pkg-config \
cmake build-essential libdbus-1-dev libglib2.0-dev sudo gnupg \
apt-transport-https ca-certificates software-properties-common

python -m pip install dbus-python docker

# ============================================================
# 3️⃣ CONFIGURACIÓN DOCKER
# ============================================================
echo "🔹 Configurando Docker..."

# Crear carpeta para keyrings si no existe
sudo mkdir -p /etc/apt/keyrings

DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"

# Descargar la clave GPG solo si no existe
if [ ! -f "$DOCKER_KEYRING" ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$DOCKER_KEYRING"
    echo "[✔] Clave GPG de Docker descargada."
else
    echo "[✔] Clave GPG de Docker ya existe, se omite descarga."
fi

# Configurar el repositorio usando la clave correcta
ARCH=$(dpkg --print-architecture)
DISTRO=$(lsb_release -cs)
REPO_FILE="/etc/apt/sources.list.d/docker.list"

if [ ! -f "$REPO_FILE" ]; then
    echo "deb [arch=$ARCH signed-by=$DOCKER_KEYRING] https://download.docker.com/linux/ubuntu $DISTRO stable" | \
    sudo tee "$REPO_FILE"
    echo "[✔] Repositorio Docker añadido."
else
    echo "[✔] Repositorio Docker ya existe, se omite."
fi

# Actualizar apt y instalar Docker
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Activar Docker y añadir usuario al grupo
sudo systemctl enable docker --now
sudo usermod -aG docker "$USER"

echo "[✔] Docker configurado correctamente."

# ============================================================
# 4️⃣ KOLLA-ANSIBLE Y DEPENDENCIAS PYTHON
# ============================================================
echo "🔹 Instalando dependencias Python y Kolla-Ansible..."
REQ_FILE="requirements.txt"
cat << 'EOF' > "$REQ_FILE"
ansible==11.5.0
ansible-core==2.18.5
docker==7.1.0
kolla-ansible @ git+https://opendev.org/openstack/kolla-ansible@master
openstacksdk==4.5.0
python-openstackclient==8.0.0
EOF

pip install -r "$REQ_FILE" --no-cache-dir
echo "[✔] Dependencias Python instaladas."

# ============================================================
# 5️⃣ ARCHIVOS KOLLA
# ============================================================
KOLLA_EXAMPLES="$VENV_PATH/share/kolla-ansible/etc_examples/kolla"
KOLLA_INVENTORY="$VENV_PATH/share/kolla-ansible/ansible/inventory"

sudo mkdir -p /etc/kolla/ansible/inventory
sudo cp -r "$KOLLA_EXAMPLES"/* /etc/kolla/
sudo cp "$KOLLA_INVENTORY/all-in-one" /etc/kolla/ansible/inventory/
sudo chown -R "$USER:$USER" /etc/kolla

# ============================================================
# 6️⃣ PASSWORDS Y GLOBALS
# ============================================================
sudo chown "$USER:$USER" /etc/kolla/passwords.yml
kolla-genpwd || true

LOCAL_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo "$LOCAL_IP" | awk -F. '{print $1"."$2"."$3}')
VIP=$(for i in $(seq 10 200); do IP="$SUBNET.$i"; ping -c1 -W1 "$IP" &>/dev/null || { echo "$IP"; break; }; done)

DEFAULT_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {print $5; exit}')

sudo tee /etc/kolla/globals.yml > /dev/null <<EOF
kolla_base_distro: "ubuntu"
network_interface: "$DEFAULT_IFACE"
neutron_external_interface: "veth1"
kolla_internal_vip_address: "$VIP"
EOF

sudo chown "$USER:$USER" /etc/kolla/globals.yml

# ============================================================
# 7️⃣ COLECCIONES ANSIBLE
# ============================================================
echo "🔹 Instalando colecciones..."
kolla-ansible install-deps

ansible-galaxy collection install \
  ansible.posix \
  community.general \
  community.docker \
  openstack.cloud

# ============================================================
# 8️⃣ DESPLIEGUE OPENSTACK
# ============================================================
echo "🔹 Desplegando OpenStack..."
kolla-ansible bootstrap-servers -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible prechecks -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible deploy -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible post-deploy

sudo chown -R "$USER:$USER" "$VENV_PATH"

# ============================================================
# 9️⃣ PERMISOS Y FINALIZACIÓN
# ============================================================
sudo chown -R root:root /etc/kolla
sudo chmod -R 640 /etc/kolla/*.yml

END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))
MIN=$((TOTAL / 60))
SEC=$((TOTAL % 60))

echo "[✔] Despliegue completado."
echo "[⏱] Tiempo total: ${MIN} min ${SEC} s"
