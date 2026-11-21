# Ejecuta comandos de Ansible dentro del contenedor gestor-ansible (Ansible no corre nativo en Windows).
# Ejemplos:
#   .\ejecutar.ps1 ansible gestor -m ping
#   .\ejecutar.ps1 ansible-playbook site.yml
#   .\ejecutar.ps1 ansible-playbook site.yml --tags app
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Comando)

$ErrorActionPreference = "Stop"
$raiz   = Split-Path -Parent $PSScriptRoot                                   # Infraestructura-IaC
$bdSql  = Join-Path (Split-Path -Parent $raiz) "Microservicio-BD\sql"        # repo hermano
$llave  = Join-Path $HOME ".ssh\id_ed25519_gestor_azure"
$vault  = Join-Path $HOME ".ansible\gestor_vault_pass"
$imagen = "gestor-ansible:2.21"

foreach ($r in @($bdSql, $llave, $vault)) {
    if (-not (Test-Path $r)) { throw "No se encontró $r" }
}
if (-not (docker images -q $imagen)) {
    docker build -t $imagen $PSScriptRoot
}

# Las advertencias de Ansible salen por stderr; con "Stop" PowerShell las trataría como error fatal
$ErrorActionPreference = "Continue"
docker run --rm `
    -e ANSIBLE_CONFIG=/work/ansible/ansible.cfg `
    -e ANSIBLE_FORCE_COLOR=1 `
    -v "${raiz}:/work" `
    -v "${bdSql}:/bd-sql:ro" `
    -v "${llave}:/llaves/id_gestor:ro" `
    -v "${vault}:/secretos/vault_pass:ro" `
    $imagen @Comando
exit $LASTEXITCODE
