#!/usr/bin/env bash
# Despliegue continuo desde Jenkins: ejecuta el rol "app" de Ansible contra la VM de Azure.
# Uso: ci/desplegar.sh <api|cliente> <etiqueta>
# Variables de entorno requeridas (las inyecta Jenkins con withCredentials):
#   VM_HOST                      nombre DNS público de la VM (URL de la app)
#   VM_SSH_HOST (opcional)       IP para SSH; en la VM de CI es la IP privada de la app (red interna de Azure)
#   ANSIBLE_PRIVATE_KEY_FILE     llave SSH (credencial "azure-vm-ssh")
#   ANSIBLE_VAULT_PASSWORD_FILE  contraseña de Ansible Vault (credencial "ansible-vault-gestor")
#   BD_SQL_DIR                   checkout de Microservicio-BD/sql
set -euo pipefail

servicio="$1"
etiqueta="$2"
case "$servicio" in
  api|cliente) ;;
  *) echo "Servicio no válido: $servicio (usa api o cliente)"; exit 2 ;;
esac
: "${VM_HOST:?Falta VM_HOST}" "${ANSIBLE_PRIVATE_KEY_FILE:?}" "${ANSIBLE_VAULT_PASSWORD_FILE:?}" "${BD_SQL_DIR:?}"

VERSION_ANSIBLE="2.21.6"
VENV="${JENKINS_HOME:-$HOME}/venvs/ansible-${VERSION_ANSIBLE}"
if [ ! -x "$VENV/bin/ansible-playbook" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "ansible-core==${VERSION_ANSIBLE}"
fi

raiz="$(cd "$(dirname "$0")/.." && pwd)"
cd "$raiz/ansible"

# Inventario efímero (el de Terraform no se versiona)
inventario="$(mktemp)"
trap 'rm -f "$inventario"' EXIT
cat > "$inventario" <<EOF
[gestor]
vm-gestor ansible_host=${VM_SSH_HOST:-$VM_HOST} ansible_user=azureuser
[gestor:vars]
fqdn_publico=${VM_HOST}
EOF

echo "Desplegando ${servicio}:${etiqueta} en ${VM_HOST} (SSH a ${VM_SSH_HOST:-$VM_HOST})"
export ANSIBLE_CONFIG="$raiz/ansible/ansible.cfg"
export ANSIBLE_HOST_KEY_CHECKING=False
"$VENV/bin/ansible-playbook" site.yml -i "$inventario" --tags app \
  -e "${servicio}_tag=${etiqueta}" \
  -e "bd_sql_origen=${BD_SQL_DIR%/}/"
