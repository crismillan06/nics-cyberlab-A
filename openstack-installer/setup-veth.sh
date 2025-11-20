#!/bin/bash
# uplinkbridge.sh - Bridge uplink + veth + NAT con autodetección de interfaz física
set -e

detect_phys_iface() {
  # 1) Ruta por defecto (más fiable)
  local dev
  dev=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){ if($i=="dev"){ print $(i+1); exit } }}')
  # 2) Fallback: primera interfaz global IPv4 “real” (excluye virtuales/túneles)
  if [ -z "$dev" ]; then
    dev=$(ip -o -4 addr show up scope global | awk '{print $2}' \
      | grep -Ev '^(lo|docker.*|br-.*|veth.*|virbr.*|vnet.*|tap.*|tun.*|tailscale.*|wg.*|vmnet.*|cali.*|flannel.*)$' \
      | head -n1)
  fi
  echo "$dev"
}

echo "[+] Verificando si existen interfaces antiguas..."

# Limpiar restos previos (idempotente)
ip link del veth0 2>/dev/null || true
ip link del veth1 2>/dev/null || true
ip link set uplinkbridge down 2>/dev/null || true
brctl delbr uplinkbridge 2>/dev/null || true

echo "[+] Creando cable virtual (veth0 <-> veth1)..."
ip link add veth0 type veth peer name veth1

echo "[+] Activando interfaces veth..."
ip link set dev veth0 up
ip link set dev veth1 up

echo "[+] Creando bridge uplinkbridge y conectando veth0..."
brctl addbr uplinkbridge
brctl addif uplinkbridge veth0
ip link set dev uplinkbridge up

echo "[+] Asignando IP 10.0.2.1/24 al bridge..."
# Evitar error si ya está asignada
ip addr add 10.0.2.1/24 dev uplinkbridge 2>/dev/null || ip addr replace 10.0.2.1/24 dev uplinkbridge

echo "[+] Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Detectar interfaz física
PHYS_IF="$(detect_phys_iface)"
if [ -z "${PHYS_IF}" ]; then
  echo "[✖] No se pudo detectar una interfaz física válida."
  ip -o -4 addr show || true
  exit 1
fi
echo "[+] Usando interfaz física: ${PHYS_IF}"

echo "[+] Configurando reglas iptables NAT y FORWARD..."

# Limpieza de posibles reglas previas (no falla si no existen)
iptables -t nat -D POSTROUTING -o "${PHYS_IF}" -s 10.0.2.0/24 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -o "${PHYS_IF}" -s 192.168.250.0/24 -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -s 10.0.2.0/24 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 192.168.250.0/24 -j ACCEPT 2>/dev/null || true

# Reglas correctas (una sola vez)
iptables -t nat -A POSTROUTING -o "${PHYS_IF}" -s 10.0.2.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o "${PHYS_IF}" -s 192.168.250.0/24 -j MASQUERADE
iptables -I FORWARD -s 10.0.2.0/24 -j ACCEPT
iptables -I FORWARD -s 192.168.250.0/24 -j ACCEPT

echo "[✓] uplinkbridge configurado."
echo "    - Bridge: uplinkbridge (10.0.2.1/24)"
echo "    - Veth:   veth0 (en bridge) <-> veth1 (para Neutron)"
echo "    - NAT a través de: ${PHYS_IF}"
