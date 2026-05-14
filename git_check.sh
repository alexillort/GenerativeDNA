#!/bin/bash

# ===================================================================================
# Git & LFS Status Check Script v3.1 (Actualizado)
# Descripción:
# Compara el estado local con el remoto 'origin'.
# Detecta automáticamente la rama remota y muestra los detalles
# de los commits si no están sincronizados. Verifica LFS de forma robusta.
# ===================================================================================

# --- Colores ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Utilidad de Impresión ---
print_info() { echo -e "${CYAN}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# --- Flujo Principal ---
main() {
    print_info "--- Iniciando Verificación de Estado (Solo Lectura) ---"
    local REMOTE_NAME="origin"

    # 1. Limpieza preventiva y Fetch
    print_info "1. Actualizando estado del remoto ($REMOTE_NAME)..."
    # Redirigimos el error para ver qué pasa si falla
    if ! git fetch $REMOTE_NAME 2>&1; then
        print_error "Error: No se pudo contactar al remoto. Verifica tu URL con 'git remote -v'"
        exit 1
    fi
    print_success "✓ Estado del remoto actualizado."

    # 2. Determinar Ramas
    local LOCAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    print_info "Rama local actual: ${YELLOW}$LOCAL_BRANCH${NC}"

    # Forzar que Git reconozca la rama remota si existe
    local UPSTREAM_BRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    
    if [[ -z "$UPSTREAM_BRANCH" ]]; then
        print_warning "⚠️ Rama no vinculada. Intentando vincular a $REMOTE_NAME/$LOCAL_BRANCH..."
        git branch --set-upstream-to=$REMOTE_NAME/$LOCAL_BRANCH $LOCAL_BRANCH 2>/dev/null
        UPSTREAM_BRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    fi

    # 3. Comparar estados
    if [[ -z "$UPSTREAM_BRANCH" ]]; then
        print_error "\n❌ No se pudo encontrar una rama remota para comparar."
        print_warning "Tu rama '${LOCAL_BRANCH}' parece existir solo localmente."
        print_warning "No se puede verificar el estado de commits o LFS."
    else
        print_info "Comparando ${YELLOW}HEAD${NC} -> ${CYAN}$UPSTREAM_BRANCH${NC}"
        
        # --- 3a. Verificación de Commits ---
        print_info "\n--- Estado de Commits ---"
        local status_line=$(git status -sb | head -n 1)
        echo "   ($status_line)" # Muestra el estado resumido primero

        if echo "$status_line" | grep -q "ahead"; then
            print_warning "⚠️ Tienes commits locales pendientes de subir."
            print_info "Detalles de los commits pendientes:"
            git log $UPSTREAM_BRANCH..HEAD --stat
        elif echo "$status_line" | grep -q "behind"; then
            print_warning "⚠️ Tu rama local está desactualizada. (Haz 'git pull')"
            print_info "Detalles de los commits remotos que te faltan:"
            git log HEAD..$UPSTREAM_BRANCH --stat
        elif echo "$status_line" | grep -q "diverged"; then
            print_error "❌ Tu rama ha divergido del remoto."
            print_info "--- Commits remotos que te faltan ---"
            git log HEAD..$UPSTREAM_BRANCH --stat
            print_info "--- Commits locales pendientes de subir ---"
            git log $UPSTREAM_BRANCH..HEAD --stat
        else
            print_success "✅ Commits están sincronizados con '$UPSTREAM_BRANCH'."
        fi

        # --- 3b. Verificación de LFS (CORRECCIÓN APLICADA AQUÍ) ---
        print_info "\n--- Estado de LFS ---"
        if ! git lfs ls-files &>/dev/null; then
            print_success "Git LFS no está inicializado o no rastrea archivos."
        else
            REMOTE_BRANCH_NAME=${UPSTREAM_BRANCH#*/} 
            print_info "Verificando archivos LFS pendientes para '${REMOTE_BRANCH_NAME}' (simulación)..."
            
            local lfs_check_output
            lfs_check_output=$(git lfs push --dry-run origin "$LOCAL_BRANCH" 2>&1)

            # Nueva lógica que entiende mejor las respuestas vacías o diferentes de LFS
            if [[ -z "$lfs_check_output" ]] || echo "$lfs_check_output" | grep -qE "0/0|0 of 0 files"; then
                print_success "✅ Todos los archivos LFS están sincronizados con '$UPSTREAM_BRANCH'."
            elif echo "$lfs_check_output" | grep -qE "pushing|files\)"; then
                print_warning "⚠️ ¡Archivos LFS pendientes de subir!"
                echo "$lfs_check_output" | grep "files)" | sed 's/Git LFS: //'
            else
                print_error "No se pudo determinar el estado exacto, pero aquí está la respuesta de LFS:"
                echo "$lfs_check_output"
            fi
        fi
    fi
}

main
print_info "\n--- Verificación Completa ---"