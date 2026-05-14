#!/bin/bash

# ===================================================================================
# Git Backup Script v3.1
# Descripción:
# v3.1: Corrige un error de sintaxis con '>&2' en algunas versiones de Bash
#       cambiando la forma en que el menú devuelve la selección del usuario.
# ===================================================================================

# --- Configuración ---
MAX_SIZE_MB=100

# --- Colores para la Salida ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Variable Global para el resultado del menú ---
PUSH_STRATEGY_RESULT=""

# --- Funciones de Utilidad ---
print_info() { echo -e "${CYAN}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# --- Funciones Principales ---

check_repository_ownership() {
    local git_output
    git_output=$(git status 2>&1)
    if echo "$git_output" | grep -q "dubious ownership"; then
        print_error "Error Crítico: Se detectó un problema de propiedad con este repositorio Git."
        local safe_dir_command
        safe_dir_command=$(echo "$git_output" | grep "git config --global --add safe.directory")
        if [[ -n "$safe_dir_command" ]]; then
            print_info "\nPor favor, ejecuta el siguiente comando y vuelve a correr este script:"
            echo -e "${YELLOW}$(echo "$safe_dir_command" | sed 's/^[ \t]*//')${NC}"
        fi
        exit 1
    fi
}

check_git_status() {
    if git rev-parse --verify main &>/dev/null; then
        git checkout main
    elif git rev-parse --verify master &>/dev/null; then
        git checkout master
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
        print_error "Error: Tienes cambios sin confirmar en tu repositorio."
        print_warning "Por favor, haz 'git commit' o 'git stash' con tus cambios antes de ejecutar este script."
        exit 1
    fi
    print_success "✅ Repositorio limpio, continuando..."
}

setup_remote() {
    if ! git remote get-url origin &>/dev/null; then
        print_warning "No se encontró un repositorio remoto 'origin'."
        read -p "Ingrese la URL del repositorio GitLab: " repo_url
        git remote add origin "$repo_url"
        print_success "✓ Remoto 'origin' agregado."
    fi
}

setup_lfs() {
    local remote_url=$(git remote get-url origin)
    if [[ -n "$remote_url" ]]; then
        git config lfs."$remote_url/info/lfs".locksverify true
        print_success "✓ Verificación de bloqueos LFS habilitada."
    fi
}

manage_gitignore() {
    print_info "📌 Verificando .gitignore..."
    local ignore_list=("[Ll]ibrary/" "[Tt]emp/" "[Bb]uild/" "[Bb]uilds/" "[Ll]ogs/" "[Mm]emoryCaptures/" "Crashes/" "_TRASH_*/")
    local changes_made=false
    for item in "${ignore_list[@]}"; do
        if ! grep -q "^$item$" .gitignore &>/dev/null; then
            echo "$item" >> .gitignore; changes_made=true
        fi
    done
    [[ "$changes_made" == true ]] && git add .gitignore
}

track_large_files() {
    print_info "🔍 Buscando archivos mayores a ${MAX_SIZE_MB}MB para LFS..."
    find . -type f -size "+${MAX_SIZE_MB}M" \
        -not -path "./.git/*" \
        -not -path "./[Ll]ibrary/*" \
        -not -path "./[Tt]emp/*" \
        -not -path "./[Bb]uild/*" \
        -not -path "./[Bb]uilds/*" \
        -not -path "./[Ll]ogs/*" \
    | while read -r file; do
        if ! git lfs ls-files | grep -qF "$file"; then
            git lfs track "$file"; git add "$file"
        fi
    done
    [[ -f ".gitattributes" ]] && git add .gitattributes
}

commit_changes() {
    print_info "📌 Agregando archivos al commit..."
    git add .
    if git diff --cached --quiet; then
        print_success "✅ No hay nuevos cambios para respaldar."
        return 1
    else
        local commit_message="Respaldo automático $(date +'%Y-%m-%d %H:%M:%S')"
        git commit -m "$commit_message"
        return 0
    fi
}

# FUNCIÓN CORREGIDA: Ahora guarda la elección en una variable global.
choose_push_strategy() {
    print_info "\n--- ¿Cómo deseas subir este respaldo? ---"
    local folder_name=$(basename "$PWD" | sed 's/[^a-zA-Z0-9._-]//g')
    local main_branch_name="main"
    if git rev-parse --verify master &>/dev/null; then main_branch_name="master"; fi
    
    local options=(
        "Subir directamente a la rama '$main_branch_name'"
        "Crear una nueva rama de respaldo (ej. backup/FECHA)"
        "Crear/Actualizar una rama con el nombre de esta carpeta ('$folder_name')"
        "Ingresar un nombre de rama personalizado"
        "Cancelar y no subir"
    )

    PS3=$(echo -e "${YELLOW}Elige una opción: ${NC}")
    select opt in "${options[@]}"; do
        case $REPLY in
            1) PUSH_STRATEGY_RESULT="main"; break ;;
            2) PUSH_STRATEGY_RESULT="backup"; break ;;
            3) PUSH_STRATEGY_RESULT="folder"; break ;;
            4) PUSH_STRATEGY_RESULT="custom"; break ;;
            5) PUSH_STRATEGY_RESULT="cancel"; break ;;
            *) print_error "Opción inválida." ;;
        esac
    done
}

# La función push_changes no necesita cambios.
push_changes() {
    local strategy=$1
    local branch_name

    local main_branch_name="main"
    if git rev-parse --verify master &>/dev/null; then main_branch_name="master"; fi

    case "$strategy" in
        "main")
            branch_name="$main_branch_name"
            print_warning "ATENCIÓN: Estás a punto de subir directamente a '$branch_name'."
            read -p "¿Continuar? (s/n): " confirm
            if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
                print_warning "Subida cancelada."; return
            fi
            print_info "☁️ Subiendo cambios a '$branch_name'..."
            git push origin "$branch_name"
            ;;
        "backup")
            branch_name="backup/$(date +'%Y-%m-%d_%H-%M-%S')"
            print_info "🚀 Creando rama remota de respaldo: $branch_name"
            git push origin HEAD:"refs/heads/$branch_name"
            ;;
        "folder")
            branch_name=$(basename "$PWD" | sed 's/[^a-zA-Z0-9._-]//g')
            print_info "🚀 Creando/Actualizando la rama remota '$branch_name'..."
            git push --force origin HEAD:"refs/heads/$branch_name"
            ;;
        "custom")
            read -p "Ingrese el nombre de la nueva rama: " custom_name
            branch_name=$(echo "$custom_name" | sed 's/[^a-zA-Z0-9._-]//g')
            if [[ -z "$branch_name" ]]; then
                print_error "Nombre inválido."; return
            fi
            print_info "🚀 Creando/Actualizando la rama remota '$branch_name'..."
            git push --force origin HEAD:"refs/heads/$branch_name"
            ;;
    esac

    print_info "📦 Subiendo archivos LFS a '$branch_name'..."
    git lfs push --all origin "$branch_name"
}

# --- Flujo Principal de Ejecución (CORREGIDO) ---
main() {
    
    print_info "--- Iniciando Proceso de Respaldo Git ---"
    
    check_repository_ownership
    check_git_status
    setup_remote
    setup_lfs
    manage_gitignore
    track_large_files

    if commit_changes; then
        # Llama a la función del menú
        choose_push_strategy
        
        # Usa la variable global para decidir qué hacer
        if [[ "$PUSH_STRATEGY_RESULT" != "cancel" ]]; then
            push_changes "$PUSH_STRATEGY_RESULT"
        else
            print_warning "Operación de subida cancelada por el usuario."
        fi
    fi

    print_success "--- Proceso de Respaldo Completado ---"
}

main