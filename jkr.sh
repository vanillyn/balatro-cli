#!/usr/bin/env bash
set -euo pipefail
#                           ---.
#                         -,JOOOJ=.
#                       -,OKKKKOEEK:
#                      :OKKKKKKJrrrJ
#                     :OKKKKKKKO,O=
#             -=JJJJ/=OKKKKKKKKKJ:=JJJJ=-             jkrsh (joker shell)
#            /ERRRRRREKKKKKKKKKKKERRRRRRE/            a tool by vanillyn
#           /EREKERREKKKKKOKOKKKKKERREERRE/
#          .ORO=..JEKKKKOKEEEKOKKKKEJ..=KRO.
#          Oekj-  /KKKRkerrrrrekRKKK=  :okeO
#          /oeK- :OKKEjokkrrrkkoREKKO: -Eeo/          modifies and runs Balatro on Linux natively
#            .   =OEoojE[JOKER]EjkeKJ:   .
#                .Jjkrrrrrrrrrrrrrro,.
#                =jejKRjkojjjokjRKoro:
#                 =EkoKOKjooojKOKkeR=
#                   JekEKERRREKRerJ
#              .--//JjerekjjjkerroJ,,/:.
#           -=,JOOEERokookeerkoojoojREKOJ=:          WIP 
#         .,JOEEjjoooRKOOEjjooEOORjjooojRKO/.        TODO:
#         /JJOKRjoojOJOEREKOKjojOJKjjjojKOKK,        Entirely rewrite repositories to match something like BMM. This isn't working
#         /JJJ,JKREOJKKOJJ,,,JJERKJORRO,,JJO=        Add a comment to most functions or confusing things to explain functionality
#         =OO,/-.=JJJKJ,J,:-:,,,OEJJJ:.-/,,=         Implement Balamod installation
#         =OO=   =JOOJJJ/.   ./JJJOOJ:   =/=         Try to centralize everything I guess, make it less of a mess
#                -,JJJ/-       -/JJO,-
#                :,,,:           :JKO:
#                 ---             -::

CONF_DIR="$HOME/.config/balatro"
CONF="$HOME/.config/balatro/config"
REPO_DIR="$CONF_DIR/repos"

LOCKFILE="/tmp/balatro.lock"
ver="v0.5"
ARGS=()
MODDED_LAUNCH=0
SHOW_HELP=0
SHOW_VERSION=0
# --- Logging
SILENT=0
ERROR=1
WARNING=2
INFO=3
VERBOSE=4
DEBUGGING=5

DEBUG=3

log() {
    local level_name="$1"
    local message="$2"
    local caller_func="${3:-}"
    local caller_line="${4:-}"
    local dlv

    case "$level_name" in
        SILENT)  dlv=$SILENT ;;
        ERROR)   dlv=$ERROR ;;
        WARNING) dlv=$WARNING ;;
        INFO)    dlv=$INFO ;;
        VERBOSE) dlv=$VERBOSE ;;
        DEBUG)   dlv=$DEBUGGING ;;
        *)       dlv=$INFO
                 message="[!!] $level_name: $message" ;;
    esac

    if [[ "$dlv" -le "$DEBUG" ]]; then
        local msgout="$message"
        if [[ "$dlv" -eq "$ERROR" ]]; then
            if [[ -n "$caller_func" && -n "$caller_line" ]]; then
                msgout="$message (in $caller_func at line $caller_line)"
            fi
            echo "[ERROR] $msgout" >&2
            if [[ "$DEBUG" -ge "$DEBUGGING" ]]; then
                echo "[DEBUG] Stack Trace:" >&2
                local i=1
                while caller "$i" &>/dev/null; do
                    local call_info=$(caller "$i")
                    echo "[DEBUG]   $call_info" >&2
                    ((i++))
                done
            fi
        elif [[ "$dlv" -eq "$WARNING" ]]; then
            echo "[WARNING] $msgout" >&2
        elif [[ "$dlv" -eq "$INFO" ]]; then
            echo "$msgout"
        else
            echo "[${level_name^^}] $msgout"
        fi
    fi
}

# --- Configs
# Creates the default config file and necessary directories if missing.
mkconf() {
    log VERBOSE "Creating default config and directories..."
    mkdir -p "$CONF_DIR" || { log ERROR "Could not create config directory '$CONF_DIR'." "${FUNCNAME[0]}" "${BASH_LINENO[0]}"; return 1; }
    mkdir -p "$REPO_DIR" || { log ERROR "Could not create repository directory '$REPO_DIR'." "${FUNCNAME[0]}" "${BASH_LINENO[0]}"; return 1; }
    
    local dldef="$HOME/.config/balatro/mods"
    local modsdef="$HOME/.config/love/Mods"
    local modsddef="$modsdef/disabled"
    local userdef="$HOME/.local/share/love/Balatro"

    cat <<EOF >"$CONF"
# config file for jkrsh

GAME_PATH="/usr/share/balatro"
DOWNLOAD_DIR="$dldef"
MODS_DIR="$modsdef"
USER_DIR="$userdef"
LOVE_BIN="$(which love)"
WINE_BIN="$(which wine)"
GAME_BIN="$(which balatro-native)"
WINEPREFIX="/opt/Balatro"
MODE="native"
NOINSTALL="0"
EOF
    log VERBOSE "Default config file created at '$CONF'."
    return 0
}

mkrepo() {
    log VERBOSE "Checking for default core repository."
    local core="$REPO_DIR/core.json"
    if [[ ! -f "$core" ]]; then
        log VERBOSE "Default core mod repository '$core' not found. Downloading"
        wget -P $REPO_DIR https://raw.githubusercontent.com/vanillyn/jkrsh/main/scripts/core.json
        return 1
    fi
    log VERBOSE "Default core mod repository found at '$core_repo_file'."
    return 0
}

# Loads the config vars
load_config() {
    log VERBOSE "Loading configuration."
    if [[ -f "$CONF" ]]; then
        source "$CONF"
        log VERBOSE "Configuration loaded from '$CONF'."
    else
        log WARNING "Config file '$CONF' not found during load_config. Using default values."
        GAME_PATH="/usr/share/balatro"
        DOWNLOAD_DIR="$HOME/.config/balatro/mods"
        MODS_DIR="$HOME/.config/love"
        USER_DIR="$HOME/.local/share/love/Balatro"
        LOVE_BIN="love"
        WINE_BIN="wine"
        WINEPREFIX="/opt/Balatro"
        MODE="native"
        NOINSTALL="0"
    fi

    GAME_BIN=$(eval echo "$GAME_BIN")
    GAME_PATH=$(eval echo "$GAME_PATH")
    DOWNLOAD_DIR=$(eval echo "$DOWNLOAD_DIR")
    MODS_DIR=$(eval echo "$MODS_DIR")
    USER_DIR=$(eval echo "$USER_DIR")
    LOVE_BIN=$(eval echo "$LOVE_BIN")
    WINE_BIN=$(eval echo "$WINE_BIN")
    WINEPREFIX=$(eval echo "$WINEPREFIX")
    DISABLED_DIR=$(eval echo "$MODS_DIR/disabled")

    mkdir -p "$REPO_DIR" || { log ERROR "Could not create repository directory '$REPO_DIR'."; return 1; }
    mkdir -p "$DOWNLOAD_DIR" || { log ERROR "Could not create download directory '$DOWNLOAD_DIR'."; return 1; }
    mkdir -p "$MODS_DIR" || { log ERROR "Could not create mods directory '$MODS_DIR'."; return 1; }
    mkdir -p "$DISABLED_DIR" || { log ERROR "Could not create disabled mods directory '$DISABLED_DIR'."; return 1; }
    mkdir -p "$USER_DIR" || { log ERROR "Could not create user data directory '$USER_DIR'."; return 1; }
    return 0
}

# --- Checks
# Determines the package manager.
if [[ -f /etc/arch-release ]]; then
    PKG="pacman -S"
elif [[ -f /etc/debian_version ]]; then
    PKG="apt-get install"
elif [[ -f /etc/redhat-release ]]; then
    PKG="yum install"
elif [[ -f /etc/gentoo-release ]]; then
    PKG="emerge install"
elif [[ -f /etc/SuSE-release ]]; then
    PKG="zypper install"
elif [[ -f /etc/alpine-release ]]; then
    PKG="apk add"
else
    PKG=""
fi

# Checks if something exists (doesnt work on all distros currently)
check() {
    local b="$1"
    log VERBOSE "Checking for command: $b"
    if ! command -v "$b" &>/dev/null; then
        if [[ "$PKG" == "" ]]; then
            log ERROR "Package manager incompatible, install $b manually."
            return 1
        fi
        read -rp "$b not found. Install it with $PKG? [Y/n] " yn
        if [[ "$yn" == [Yy]* ]]; then
            sudo $PKG "$b"
        else
            log WARNING "Skipping $b install."
            return 1
        fi
    fi
    log VERBOSE "Command '$b' found."
    return 0
}

# Balatro install directory
steam_check() {
    if [[ -z "$GAME_PATH" ]]; then
        if command -v steam &>/dev/null; then
            if [[ -d "$HOME/.steam/steam/steamapps/common/Balatro" ]]; then
                DEFAULT_PATH="$HOME/.steam/steam/steamapps/common/Balatro"
                return 0
            fi
        else
            echo "Can't find Balatro directory, please specify with --dir"
            return 1
        fi
    fi
}
# Gets latest release from github
get_releases() {
    local repo="$1"
    local pattern="$2"
    log VERBOSE "Fetching latest release for repo: $repo with pattern: $pattern"
    local url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" |
        grep "browser_download_url" |
        grep "$pattern" |
        cut -d '"' -f 4 |
        head -n 1)
    log DEBUG "Release URL found: $url"
    echo "$url"
}

# --- cli flags parsing
flags() {
    log VERBOSE "Parsing command line flags."
    while [[ $# -gt 0 ]]; do
        local arg="$1"
        log DEBUG "Processing flag/arg: $arg"
        if [[ "$arg" == --* ]]; then
            case "$arg" in
            --native) MODE="native"; log DEBUG "Set MODE to native." ;;
            --wine) MODE="wine"; log DEBUG "Set MODE to wine." ;;
            --steam) MODE="steam"; log DEBUG "Set MODE to steam." ;;
            --noinstall) NOINSTALL=1; log DEBUG "Set NOINSTALL to 1." ;;
            --modded) MODDED_LAUNCH=1; log DEBUG "Set MODDED_LAUNCH to 1." ;;
            --dir)
                shift
                GAME_PATH="$1"; log DEBUG "Set GAME_PATH to $GAME_PATH."
                ;;
            --mod_dir)
                shift
                MODS_DIR="$1"; log DEBUG "Set MODS_DIR to $MODS_DIR."
                ;;
            --love_path)
                shift
                LOVE_BIN="$1"; log DEBUG "Set LOVE_BIN to $LOVE_BIN."
                ;;
            --wine_path)
                shift
                WINE_BIN="$1"; log DEBUG "Set WINE_BIN to $WINE_BIN."
                ;;
            --wineprefix)
                shift
                WINEPREFIX="$1"; log DEBUG "Set WINEPREFIX to $WINEPREFIX."
                ;;
            --user_dir)
                shift
                USER_DIR="$1"; log DEBUG "Set USER_DIR to $USER_DIR."
                ;;
            --config)
                shift
                CONF="$1"; log DEBUG "Set CONF to $CONF."
                ;;
            --log-level)
                shift
                local level_str=$(echo "$1" | tr '[:upper:]' '[:lower:]')
                case "$level_str" in
                    silent) DEBUG=$SILENT ;;
                    error) DEBUG=$ERROR ;;
                    warning) DEBUG=$WARNING ;;
                    info) DEBUG=$INFO ;;
                    verbose) DEBUG=$VERBOSE ;;
                    debug) DEBUG=$DEBUGINGG ;;
                    *) log ERROR "Invalid log level: $1. Using default (info).";;
                esac
                log DEBUG "Set DEBUG to $level_str ($DEBUG)."LOG_LEVEL_
                ;;
            --help) SHOW_HELP=1; log DEBUG "Set SHOW_HELP to 1." ;;
            --version) SHOW_VERSION=1; log DEBUG "Set SHOW_VERSION to 1." ;;
            *)
                log ERROR "Unknown flag: $arg"
                return 1
                ;;
            esac
        elif [[ "$arg" == -* && "$arg" != "--" ]]; then
            local short_flags="${arg:1}"
            local i=0
            while [[ $i -lt ${#short_flags} ]]; do
                local flag="${short_flags:$i:1}"
                ((i++))
                log DEBUG "Processing short flag: -$flag"
                case "$flag" in
                n) MODE="native"; log DEBUG "Set MODE to native." ;;
                w) MODE="wine"; log DEBUG "Set MODE to wine." ;;
                s) MODE="steam"; log DEBUG "Set MODE to steam." ;;
                h) SHOW_HELP=1; log DEBUG "Set SHOW_HELP to 1." ;;
                v) SHOW_VERSION=1; log DEBUG "Set SHOW_VERSION to 1." ;;
                V) DEBUG=$DEBUG; log DEBUG "Set DEBUG to DEBUG." ;;
                m) MODDED_LAUNCH=1; log DEBUG "Set MODDED_LAUNCH to 1." ;;
                l)
                    if [[ $# -gt 1 ]]; then
                        shift
                        local level_str=$(echo "$1" | tr '[:upper:]' '[:lower:]')
                        case "$level_str" in
                            silent) DEBUG=$SILENT ;;
                            error) DEBUG=$ERROR ;;
                            warning) DEBUG=$WARNING ;;
                            info) DEBUG=$INFO ;;
                            verbose) DEBUG=$VERBOSE ;;
                            debug) DEBUG=$DEBUGGING ;;
                            *) log ERROR "Invalid log level: $1. Using default.";;
                        esac
                        log DEBUG "Set DEBUG to $level_str ($DEBUG)."
                    else
                        log ERROR "-l requires an argument."
                        return 1
                    fi
                    ;;
                *)
                    log ERROR "Unknown flag: -$flag"
                    return 1
                    ;;
                esac
            done
        else
            ARGS+=("$arg")
        fi
        shift
    done
    log DEBUG "Finished parsing flags."
    return 0
}

# Links subcommands to the functions
subcommand() {
    log VERBOSE "Dispatching subcommand: $1"
    case "$1" in
    launch) launch ;;
    backup) backup "$2" ;;
    mods)
        shift
        m_command "$@"
        ;;
    install)
        shift
        i_command "$@"
        ;;
    repo)
        shift
        r_command "$@"
        ;;
    help) help ;;
    version) version ;;
    *)
        log ERROR "Unknown command: $1"
        help
        ;;
    esac
}

# Displays the main help message.
help() {
    log INFO "jkrsh: launcher and mod manager for Balatro on Linux"
    log INFO "usage: jkrsh [subcommand] [args...] [--flags]"
    log INFO "example: balatro launch -mn (launches modded native Balatro)"
    log INFO ""
    log INFO "commands:"
    log INFO "  help           display this help message"
    log INFO "  launch         launch balatro"
    log INFO "  backup         backs up balatro save data to a file"
    log INFO "  mods           manage installed mods (install, remove, list, search, etc.)"
    log INFO "  install        install core Balatro components (native, wine, lovely, smods)"
    log INFO "  repo           manage mod repositories (add, delete, list, sync)"
    log INFO ""
    log INFO "flags:"
    log INFO "  -h, --help           display this help message"
    log INFO "  -v, --version        display version information."
    log INFO "  -l, --log-level      set logging verbosity"
    log INFO "  -n, --native         force native mode"
    log INFO "  -w, --wine           force wine mode"
    log INFO "  -s, --steam          force steam/proton mode"
    log INFO "  -m, --modded         launches balatro with mods"
    log INFO ""
    log INFO "  --config             use custom config file"
    log INFO "  --dir                specify balatro directory"
    log INFO "  --mod_dir            specify mod installation directory"
    log INFO "  --love_path          location of love executable"
    log INFO "  --wine_path          location of wine executable"
    log INFO "  --wineprefix         specify wineprefix"
    log INFO "  --user_dir           specify save directory"
    log INFO "  --noinstall          doesn't copy mods to mod directory (for testing downloads)"
    log INFO ""
}

# Displays version information and current configuration.
version() {
    log INFO "jkrsh $ver"
    log INFO "-------"
    log INFO ""
    log INFO "mode: $MODE (mods $(if [[ "$MODDED_LAUNCH" == 1 ]]; then echo "enabled"; else echo "disabled"; fi))"
    log INFO ""
    log INFO "mod dir: $MODS_DIR"
    log INFO "download cache dir: $DOWNLOAD_DIR"
    log INFO "balatro game dir: $GAME_PATH"
    log INFO ""
    if [[ "$MODE" == "wine" ]]; then
        if check wine; then
            log INFO "wine version: $($WINE_BIN --version)"
            log INFO "wine bin: $WINE_BIN"
            log INFO "wineprefix: $WINEPREFIX"
        else
            log INFO "wine: not found"
        fi
    elif [[ "$MODE" == "native" ]]; then
        if check love; then
            log INFO "love version: $($LOVE_BIN --version 2>/dev/null | head -n1)"
            log INFO "love bin: $LOVE_BIN"
            log INFO "user save dir: $USER_DIR"
            log INFO "balatro native bin: $GAME_BIN"
        else
            log INFO "love: not found"
        fi
    fi
}

# Launches Balatro, optionally with mods.
launch() {
    if [[ "$MODDED_LAUNCH" == 1 ]]; then
        launch_modded
    else
        launch_vanilla
    fi
}

# Launches Balatro without mods.
launch_vanilla() {
    log INFO "Starting Balatro [$MODE] (Vanilla)"

    case "$MODE" in
    native)
        if [[ ! -x "$GAME_BIN" ]]; then
            log ERROR "Native Balatro binary not found, please setup with \"jkrsh install native\"."
            return 1
        fi
        "$GAME_BIN"
        ;;
    wine)
        if [[ ! -f "$GAME_PATH/Balatro.exe" ]]; then
            log ERROR "Balatro.exe not found in $GAME_PATH. Please install it."
            return 1
        fi
        if [[ -f "$GAME_PATH/version.dll" ]]; then
            log INFO "Disabling Lovely (version.dll) for vanilla launch."
            mv "$GAME_PATH/version.dll" "$GAME_PATH/version.dll.disabled" || { log ERROR "Failed to disable version.dll."; return 1; }
        fi
        WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$GAME_PATH/Balatro.exe"
        ;;
    steam)
        local appid="2379780"
        if check steam; then
            steam -applaunch "$appid"
        else
            log ERROR "Steam not found, please install it here: https://steampowered.com"
            return 1
        fi
        ;;
    *)
        log ERROR "Can't launch using $MODE"
        return 1
        ;;
    esac
    return 0
}

# Launches Balatro with mods enabled.
launch_modded() {
    log INFO "Launching Balatro [$MODE] (Modded)..."

    if [[ "$MODE" == "native" ]]; then
        check love || return 1

        if [[ ! -x "$GAME_BIN" ]]; then
            log WARNING "Native Balatro launcher script '$GAME_BIN' not found."
            read -rp "Attempt to install native Balatro now? (Requires sudo) [Y/n] " yn
            if [[ "$yn" == [Yy]* ]]; then
                i_native
                if [[ $? -ne 0 ]]; then
                    log ERROR "Failed to install native Balatro. Cannot launch modded native."
                    return 1
                fi
            else
                log WARNING "Native Balatro launcher not set up. Cannot launch modded native."
                return 1
            fi
        fi

        mkdir -p "$USER_DIR/Mods"

        log INFO "[Lovely] Mod files linked"
        if ldconfig -p | grep -q liblovely &>/dev/null; then
            log INFO "[Lovely] liblovely.so preloaded"
            LD_PRELOAD=liblovely.so "$GAME_BIN"
        else
            log WARNING "Lovely not found or not preloaded."
            read -rp "Attempt to install Lovely now? (Requires sudo) [Y/n] " yn
            if [[ "$yn" == [Yy]* ]]; then
                i_lovely
                if [[ $? -ne 0 ]]; then
                    log ERROR "Failed to install Lovely. Mods will not load."
                    "$GAME_BIN"
                    return 1
                fi
                LD_PRELOAD=liblovely.so "$GAME_BIN"
            else
                log WARNING "Lovely not installed. Mods will not load."
                "$GAME_BIN"
                return 1
            fi
        fi
    elif [[ "$MODE" == "wine" ]]; then
        if [[ ! -f "$GAME_PATH/Balatro.exe" ]]; then
            log ERROR "Balatro.exe not found in $GAME_PATH. Please ensure it's installed."
            return 1
        fi

        local dll="$GAME_PATH/version.dll"
        if [[ -f "$GAME_PATH/version.dll.disabled" ]]; then
            log INFO "Enabling Lovely"
            mv "$GAME_PATH/version.dll.disabled" "$dll" || { log ERROR "Failed to enable version.dll."; return 1; }
        elif [[ -f "$dll" ]]; then
            log INFO "Lovely already enabled."
        else
            log WARNING "Lovely not found for Wine. Please install it with 'jkrsh install lovely'."
            return 1
        fi

        log INFO "[Lovely] Lovely copied to directory"
        WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$GAME_PATH/Balatro.exe"
    else
        log ERROR "Modded launch not supported for mode: $MODE. Only 'native' and 'wine' are supported for modding."
        return 1
    fi
    return 0
}

# Backs up Balatro save data.
backup() {
    local backup_dir="$1"
    if [[ -z "$backup_dir" ]]; then
        backup_dir="."
    fi
    mkdir -p "$backup_dir" || { log ERROR "Could not create backup directory '$backup_dir'."; return 1; }

    log INFO "Backing up saves in $USER_DIR to $(readlink -f "$backup_dir")"

    local file="$backup_dir/balatro-save-$(date +%Y-%m-%d).tar.jkr"

    if [[ ! -d "$USER_DIR" ]]; then
        log ERROR "User data directory '$USER_DIR' doesn't exist. No saves to backup."
        return 1
    fi

    tar -czf "$file" -C "$USER_DIR" . || {
        log ERROR "Failed to backup save directory. Please check permissions or backup manually."
        return 1
    }
    log INFO "Saves backed up to '$file'."
    return 0
}

# --- Mod Installation and Management
# Trims whitespace from a string.
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Dispatches mod-related subcommands.
m_command() {
    log VERBOSE "Dispatching mod subcommand: $1"
    case "$1" in
    launch) launch_modded ;; # Calls the main modded launch function
    install)
        shift
        m_install "$@"
        ;;
    remove)
        shift
        m_remove "$1"
        ;;
    disable)
        shift
        m_disable "$1"
        ;;
    enable)
        shift
        m_enable "$1"
        ;;
    list) m_list ;;
    search)
        shift
        m_search "$@"
        ;;
    help) m_help ;;
    *)
        log ERROR "Unknown mods command: $1"
        m_help
        ;;
    esac
}

# Displays help for mod commands.
m_help() {
    log INFO "jkrsh mods: manage installed Balatro mods"
    log INFO "Usage: jkrsh mods [subcommand] [args...]"
    log INFO ""
    log INFO "commands:"
    log INFO "  launch       Launches Balatro with mods enabled (same as 'jkrsh launch --modded')"
    log INFO "  install      installs specified mod(s) and their dependencies"
    log INFO "  remove       removes specified mod"
    log INFO "  disable      temporarily disables a mod by archiving it"
    log INFO "  enable       enables a previously disabled mod"
    log INFO "  search       searches for available mods in active repositories"
    log INFO "  list         lists all currently installed and disabled mods"
    log INFO ""
}

# Installs a mod and its dependencies based on repository data.
m_install() {
    log DEBUG "Entering m_install for mod: $1"
    check jq || return 1
    check git || return 1
    check unzip || return 1
    check wget || return 1
    check curl || return 1

    local modname="$1"
    local mods_index_file="$DOWNLOAD_DIR/mods_index.json"

    r_sync || { log ERROR "Failed to sync repositories. Cannot install mod."; return 1; }

    if [[ ! -f "$mods_index_file" ]]; then
        log ERROR "No aggregated mod index found. Please add a repository first using 'jkrsh repo add'."
        return 1
    fi

    unset insmod
    declare -g -A insmod

    # Downloads and installs a mod.
    resolve_mod() {
        local in_name="$1"
        in_name=$(echo "$in_name" | tr '[:upper:]' '[:lower:]')

        log DEBUG "Resolving '$in_name'. Current tracker state: ${!insmod[@]}"

        if [[ -n "${insmod[$in_name]}" ]]; then
            log VERBOSE "Skipping already processed mod: '$in_name' (state: '${insmod[$in_name]}')"
            return 0
        fi

        local mod_json_data=$(jq --arg name "$in_name" '.[] | select(.name | ascii_downcase == $name)' "$mods_index_file")

        if [[ -z "$mod_json_data" ]]; then
            log ERROR "Mod '$in_name' not found in any active repository."
            log DEBUG "Exiting resolve_mod for: '$in_name'. Final tracker state: ${!insmod[@]}"
            return 1
        fi

        local found_name=$(echo "$mod_json_data" | jq -r '.name')
        local found_url=$(echo "$mod_json_data" | jq -r '.download_url')
        local found_deps=$(echo "$mod_json_data" | jq -r '.dependencies | join(",")')
        local found_category=$(echo "$mod_json_data" | jq -r '.category')
        local found_install_type=$(echo "$mod_json_data" | jq -r '.install_type // ""')

        log DEBUG "Found match for '$in_name': '$found_name'. Marking as 'processing'."
        insmod[$in_name]="processing"
        log DEBUG "Tracker state after marking 'processing': ${!insmod[@]}"

        if [[ -n "$found_deps" && "$found_deps" != "null" ]]; then
            IFS=',' read -ra dep_array <<<"$found_deps"
            log DEBUG "'$in_name' has dependencies: ${dep_array[*]}"
            for dep in "${dep_array[@]}"; do
                resolve_mod "$dep"
                if [[ $? -ne 0 ]]; then
                    log ERROR "Dependency '$dep' failed to install for '$in_name'. Aborting '$found_name' installation."
                    return 1
                fi
            done
        fi

        local effective_install_type="$found_install_type"
        if [[ -z "$effective_install_type" || "$effective_install_type" == "null" ]]; then
            if [[ "$found_url" == *.zip ]]; then
                effective_install_type="zip"
            elif [[ "$found_url" == *.git ]]; then
                effective_install_type="git"
            else
                log WARNING "Could not infer install_type for '$found_name' from URL '$found_url'. Assuming 'zip'."
                effective_install_type="zip"
            fi
        fi
        log DEBUG "Effective install type for '$found_name': '$effective_install_type'."

        case "$effective_install_type" in
            lovely_prebuilt)
                log VERBOSE "Installing $found_name [$found_category] via prebuilt Lovely setup..."
                i_lovely || { log ERROR "Failed to install Lovely for '$found_name'."; return 1; }
                ;;
            smods_prebuilt|smod)
                log VERBOSE "Installing $found_name [$found_category] via prebuilt SMODS setup..."
                i_steammodded || { log ERROR "Failed to install SMODS for '$found_name'."; return 1; }
                ;;
            zip)
                log VERBOSE "Installing $found_name [$found_category] via ZIP download..."
                local dp="$DOWNLOAD_DIR/$found_name"
                local ip="$MODS_DIR/$found_name"
                local archive_file="$DOWNLOAD_DIR/${found_name}.zip"

                mkdir -p "$DOWNLOAD_DIR"

                wget -q -O "$archive_file" "$found_url" || {
                    log ERROR "Failed to download '$found_name.zip' from '$found_url'."
                    return 1
                }

                mkdir -p "$dp"
                unzip -o "$archive_file" -d "$dp" || {
                    log ERROR "Failed to extract '$found_name.zip'."
                    return 1
                }
                rm -f "$archive_file"

                local extracted_subdir_count=$(find "$dp" -maxdepth 1 -mindepth 1 -type d | wc -l)
                if [[ "$extracted_subdir_count" -eq 1 ]]; then
                    local extracted_first_dir=$(find "$dp" -maxdepth 1 -mindepth 1 -type d -print -quit)
                    local extracted_base_name=$(basename "$extracted_first_dir")
                    if [[ "$(echo "$extracted_base_name" | tr '[:upper:]' '[:lower:]')" == "$(echo "$found_name" | tr '[:upper:]' '[:lower:]')" ]]; then
                        log VERBOSE "Flattening directory structure for '$found_name' (moved contents from '$extracted_base_name')."
                        mv "$extracted_first_dir"/* "$dp/" 2>/dev/null
                        rmdir "$extracted_first_dir" 2>/dev/null || true
                    fi
                fi

                if [[ "$NOINSTALL" != 1 ]]; then
                    mkdir -p "$MODS_DIR"
                    log VERBOSE "Copying $found_name to "$ip""
                    rsync -a "$dp/" "$ip/"
                else
                    log INFO "Skipping $found_name."
                fi
                ;;
            git)
                log VERBOSE "Installing $found_name [$found_category]"
                local dp="$DOWNLOAD_DIR/$found_name"
                local ip="$MODS_DIR/$found_name"

                mkdir -p "$DOWNLOAD_DIR"

                if [[ -d "$dp/.git" ]]; then
                    log VERBOSE "Updating $found_name (pulling latest changes)."
                    git -C "$dp" pull || {
                        log ERROR "Update failed for $found_name."
                        return 1
                    }
                else
                    log VERBOSE "Cloning $found_name from $found_url."
                    git clone "$found_url" "$dp" || {
                        log ERROR "Download failed for $found_name."
                        return 1
                    }
                fi

                if [[ "$NOINSTALL" != 1 ]]; then
                    mkdir -p "$MODS_DIR"
                    log VERBOSE "Copying $found_name to "$ip""
                    rsync -a --exclude='.git' "$dp/" "$ip/"
                else
                    log INFO "Skipping $found_name."
                fi
                ;;
            custom_script)
                log WARNING "Installing '$found_name' via custom script from '$found_url'."
                log WARNING "Executing remote scripts is a significant security risk. Proceed with extreme caution."
                read -rp "Do you wish to continue with this custom script installation? [y/N] " confirm_custom_script
                if [[ "$confirm_custom_script" == [Yy]* ]]; then
                    local temp_script="$DOWNLOAD_DIR/${found_name}_install_script.sh"
                    log VERBOSE "Downloading custom script to $temp_script."
                    wget -q -O "$temp_script" "$found_url" || {
                        log ERROR "Failed to download custom install script for '$found_name'."
                        return 1
                    }
                    chmod +x "$temp_script" || {
                        log ERROR "Failed to make custom install script executable."
                        rm -f "$temp_script"
                        return 1
                    }
                    log VERBOSE "Executing custom install script for '$found_name'..."
                    "$temp_script" "$found_name" "$DOWNLOAD_DIR" "$MODS_DIR" "$USER_DIR" "$DEBUG" || {
                        log ERROR "Custom install script for '$found_name' failed."
                        rm -f "$temp_script"
                        return 1
                    }
                    rm -f "$temp_script"
                    log INFO "'$found_name' installed."
                else
                    log INFO "Installation for '$found_name' cancelled by user."
                    return 1
                fi
                ;;
            *)
                log ERROR "Unsupported install type for '$found_name': '$effective_install_type'."
                return 1
                ;;
        esac

        log DEBUG "Finished processing '$in_name'. Marking as 'installed'."
        insmod[$in_name]="installed"
        log DEBUG "Tracker state after marking 'installed': ${!insmod[@]}"
        log DEBUG "Exiting resolve_mod for: '$in_name'. Final tracker state: ${!insmod[@]}"
        return 0
    }

    resolve_mod "$modname"
    log DEBUG "Exiting m_install."
    return 0
}

# Removes an installed or cached mod.
m_remove() {
    log DEBUG "Entering m_remove for mod: $1"
    local modname="$1"
    if [[ -z "$modname" ]]; then
        log ERROR "Usage: jkrsh mods remove <mod_name>"
        return 1
    fi

    local downloaded_path="$DOWNLOAD_DIR/$modname"
    local installed_path="$MODS_DIR/$modname"
    local archive_file="$DISABLED_DIR/${modname}.tar.jkr"

    log VERBOSE "Attempting to remove mod: $modname"

    if [[ -d "$installed_path" ]]; then
        read -rp "Remove '$modname' ($installed_path)? [Y/n] " yn
        if [[ "$yn" == [Yy]* ]]; then
            rm -rf "$installed_path" || { log ERROR "Failed to remove '$installed_path'."; return 1; }
            log INFO "Removed '$modname'."
        else
            log INFO "Skipping removal."
        fi
    else
        log ERROR "'$modname' not found."
        return 1
    fi

    if [[ -d "$downloaded_path" ]]; then
        read -rp "Remove '$modname' from your downloads ($downloaded_path)? [Y/n] " yn
        if [[ "$yn" == [Yy]* ]]; then
            rm -rf "$downloaded_path" || { log ERROR "Failed to remove '$downloaded_path'."; return 1; }
            log INFO "Removed '$modname'."
        else
            log INFO "Skipping removal."
        fi
    else
        log ERROR "'$modname' not found."
    fi

    if [[ -f "$archive_file" ]]; then
        read -rp "Remove disabled mod '$modname' ($archive_file)? [Y/n] " yn
        if [[ "$yn" == [Yy]* ]]; then
            rm -f "$archive_file" || { log ERROR "Failed to remove '$archive_file'."; return 1; }
            log INFO "Removed '$modname'."
        else
            log INFO "Skipping removal."
        fi
    else
        log WARNING "'$modname' not found in disabled archives ($archive_file)."
    fi

    if [[ ! -d "$installed_path" ]] && [[ ! -d "$downloaded_path" ]] && [[ ! -f "$archive_file" ]]; then
        log INFO "Removed '$modname'."
    else
        log WARNING "Removal of '$modname' completed with some paths not found or skipped."
    fi
    log DEBUG "Exiting m_remove."
    return 0
}

# Disables an installed mod by archiving it.
m_disable() {
    log DEBUG "Entering m_disable for mod: $1"
    local modname="$1"

    if [[ -z "$modname" ]]; then
        log ERROR "Usage: jkrsh mods disable <mod_name>"
        return 1
    fi

    local installed_path="$MODS_DIR/$modname"
    local archive_file="$DISABLED_DIR/${modname}.tar.jkr"

    if [[ ! -d "$installed_path" ]]; then
        log ERROR "Mod '$modname' not found in installed mods directory ($installed_path)."
        return 1
    fi

    if [[ -f "$archive_file" ]]; then
        log INFO "'$modname' is already disabled."
        return 0
    fi

    mkdir -p "$DISABLED_DIR" || { log ERROR "Could not create disabled archives directory '$DISABLED_DIR'."; return 1; }
    log VERBOSE "Disabling mod: $modname"
    tar -czf "$archive_file" -C "$(dirname "$installed_path")" "$(basename "$installed_path")" || {
        log ERROR "Failed to create archive for '$modname'."
        return 1
    }

    rm -rf "$installed_path" || {
        log ERROR "Failed to remove original mod directory '$installed_path'."
        return 1
    }

    log INFO "Disabled '$modname'."
    log DEBUG "Exiting m_disable."
    return 0
}

# Enables a previously disabled mod.
m_enable() {
    log DEBUG "Entering m_enable for mod: $1"
    local modname="$1"
    if [[ -z "$modname" ]]; then
        log ERROR "Usage: jkrsh mods enable <mod_name>"
        return 1
    fi

    local installed_path="$MODS_DIR/$modname"
    local archive_file="$DISABLED_DIR/${modname}.tar.jkr"

    if [[ ! -f "$archive_file" ]]; then
        log ERROR "Mod '$modname' is already enabled or no archive found at '$archive_file'."
        return 1
    fi

    log VERBOSE "Extracting and enabling mod: $modname"
    mkdir -p "$MODS_DIR" || { log ERROR "Could not create mods directory '$MODS_DIR'."; return 1; }
    tar -xzf "$archive_file" -C "$MODS_DIR" || {
        log ERROR "Failed to extract archive for '$modname'."
        return 1
    }

    rm -f "$archive_file" || {
        log ERROR "Failed to remove archive file '$archive_file'."
        return 1
    }

    log INFO "Enabled $modname."
    log DEBUG "Exiting m_enable."
    return 0
}

# Lists all installed and disabled mods.
m_list() {
    log DEBUG "Entering m_list."
    log VERBOSE "Listing installed mods:"
    local installed_count=0

    log INFO "--- enabled mods ---"
    if [[ -d "$MODS_DIR" ]]; then
        find "$MODS_DIR" -maxdepth 1 -mindepth 1 -type d -not -name "disabled" -printf "%f\n" | sort | while read -r mod; do
            log INFO "- $mod"
            installed_count=$((installed_count + 1))
        done
    fi

    log INFO ""
    log INFO "--- disabled mods ---"
    if [[ -d "$DISABLED_DIR" ]]; then
        find "$DISABLED_DIR" -maxdepth 1 -mindepth 1 -type f -name "*.tar.jkr" -printf "%f\n" | sort | while read -r archive_name; do
            local mod=$(basename "$archive_name" .tar.jkr)
            log INFO "- $mod"
            installed_count=$((installed_count + 1))
        done
    fi

    if [[ "$installed_count" -eq 0 ]]; then
        log DEBUG "No mods found (enabled or disabled)." # still showing despite there being listed mods
    fi
    log DEBUG "Exiting m_list."
    return 0
}

# Searches for available mods in active repositories.
m_search() {
    log DEBUG "Entering m_search for query: $1"
    check jq || return 1

    local query="$1"
    local mods_index_file="$DOWNLOAD_DIR/mods_index.json"

    r_sync || { log ERROR "Failed to sync repositories. Cannot search mods."; return 1; }

    if [[ ! -f "$mods_index_file" ]]; then
        log ERROR "No aggregated mod index found. Please add a repository first using 'jkrsh repo add'."
        return 1
    fi

    log VERBOSE "Searching for '$query' in active repositories..."
    local search_results=$(jq -r --arg query "$query" '
        .[] | select(.name | ascii_downcase | contains($query | ascii_downcase) or
                     (.description // "" | ascii_downcase | contains($query | ascii_downcase))) |
        "Found: \( .name ) (Category: \( .category // "Unknown" ), Install Type: \( .install_type // "auto" )) - \( .download_url ) (Dependencies: \( (.dependencies // []) | join(", ") | if . == "" then "None" else . end ))"
    ' "$mods_index_file" | sort)

    if [[ -z "$search_results" ]]; then
        log INFO "'$query' not found. Nothing to do."
        return 1
    else
        log SILENT "$search_results"
    fi
    log DEBUG "Exiting m_search."
    return 0
}

# --- Handles install subcommands
# Dispatches component installation subcommands.
i_command() {
    log VERBOSE "Dispatching install subcommand: $1"
    case "$1" in
    native)
        shift
        i_native "$@"
        ;;
    wine)
        shift
        i_wine "$1"
        ;;
    lovely) i_lovely ;;
    smods | steammodded | smod) i_steammodded ;;
    balamod) i_balamod ;;
    help) i_help ;;
    *)
        log ERROR "Unknown install command: $1"
        i_help
        ;;
    esac
}

# Displays help for install commands.
i_help() {
    log INFO "jkrsh install: sets up Balatro components needed for modding"
    log INFO "Usage: jkrsh install [subcommand] [args...]"
    log INFO ""
    log INFO "commands:"
    log INFO "  native       sets up Balatro native environment"
    log INFO "  wine         sets up a wineprefix for Windows mods"
    log INFO "  lovely       downloads and installs Lovely injector"
    log INFO "  smod         downloads and installs Steamodded"
    log INFO "  balamod      downloads and installs Balamod"
    log INFO ""
}

# Installs Balatro natively
i_native() {
    log DEBUG "Entering i_native."
    log VERBOSE "Setting up Balatro native"

    if [[ -f "$GAME_BIN" ]]; then
        log INFO "Balatro Native launcher script '$GAME_BIN' already installed."
        log INFO "If you wish to reinstall, please remove it manually first: 'sudo rm $GAME_BIN'"
        return 0
    fi

    check love || { log ERROR "'love' executable not found. Please install LÖVE (love2d.org) for native Balatro to work."; return 1; }

    local src=""
    if steam_check; then
        log VERBOSE "Found Steam Balatro installation at default path: '$DEFAULT_PATH'."
        src="$DEFAULT_PATH"
    else
        log WARNING "Could not find Steam Balatro installation at default path."
        read -rp "Enter the path to your Balatro install (default: $DEFAULT_PATH): " user_input_dir
        src="${user_input_dir:-$DEFAULT_PATH}"
    fi

    if [[ ! -d "$src" ]]; then
        log ERROR "Source directory '$src' does not exist."
        log ERROR "Please provide a valid path to your Balatro installation."
        return 1
    fi
    if [[ ! -f "$src/Balatro.exe" ]]; then
        log ERROR "'Balatro.exe' not found in '$src'."
        log ERROR "Please ensure the path points to the root of your Balatro game directory."
        return 1
    fi

    log VERBOSE "Copying Balatro files from '$src' to '$GAME_PATH'..."
    sudo mkdir -p "$GAME_PATH" || { log ERROR "Could not create target directory '$GAME_PATH'. Check permissions."; return 1; }
    sudo rsync -a --delete "$src/" "$GAME_PATH/" || { log ERROR "Failed to copy Balatro files to '$GAME_PATH'. Check permissions."; return 1; }
    log INFO "Balatro files copied to '$GAME_PATH'."

    local scr="/tmp/balatro-native-temp-$(date +%s%N).sh"
    log VERBOSE "Creating temporary native launcher script at '$scr'..."

    cat <<EOF >"$scr"
#!/bin/bash
# This script launches Balatro natively using LÖVE and system libraries.
# Generated by jkrsh

LOVE_BIN=\"$LOVE_BIN\"
GAME_DIR=\"$GAME_PATH\"

if ! command -v \"\$LOVE_BIN\" &>/dev/null; then
    echo \"[Error] LÖVE executable ('\$LOVE_BIN') not found.\"
    echo \"[Error] Please install LÖVE for native Balatro to run.\"
    exit 1
fi

if [[ ! -f \"\$GAME_DIR/Balatro.exe\" ]]; then
    echo \"[Error] Balatro.exe not found in '\$GAME_DIR'. Something has gone wrong, probably.\"
    exit 1
fi

\"\$LOVE_BIN\" \"\$GAME_DIR/Balatro.exe\" \"\$@\"
EOF

    chmod +x "$scr" || { log ERROR "Could not make temporary native launcher script executable."; rm -f "$scr"; return 1; }

    log VERBOSE "Installing native launcher script to '$GAME_BIN'..."
    sudo mv "$scr" "$GAME_BIN" || { log ERROR "Could not install Balatro Native launcher script to '$GAME_BIN'. Check permissions."; rm -f "$scr"; return 1; }
    log INFO "Balatro Native installed successfully."
    log DEBUG "Finished i_native."
    return 0
}

# Sets up a Wine prefix.
i_wine() {
    log DEBUG "Entering i_wine."
    log INFO "Setting up Wine prefix in $WINEPREFIX..."
    check wine || return 1

    if [[ -d "$WINEPREFIX" ]]; then
        log INFO "Wine prefix '$WINEPREFIX' already exists. Skipping creation."
    else
        mkdir -p "$(dirname "$WINEPREFIX")" || { log ERROR "Could not create parent directory for Wineprefix."; return 1; }
        log INFO "Creating Wine prefix '$WINEPREFIX'..."
        WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -u || {
            log ERROR "Failed to create Wine prefix '$WINEPREFIX'."
            return 1
        }
        log INFO "Wine prefix '$WINEPREFIX' created successfully."
    fi

    log INFO "Wine setup complete."
    log DEBUG "Finished i_wine."
    return 0
}

# Downloads and installs lovely-injector.
i_lovely() {
    log DEBUG "Entering i_lovely."
    log INFO "Setting up Lovely [$MODE]"
    check curl || return 1
    check wget || return 1
    check unzip || return 1
    check tar || return 1

    local repo="ethangreen-dev/lovely-injector"
    local url=""
    local archive=""
    local extract_dir="$DOWNLOAD_DIR/lovely"

    if [[ "$MODE" == "native" ]]; then
        url=$(get_releases "$repo" "lovely-x86_64-unknown-linux-gnu.tar.gz")
        archive="$DOWNLOAD_DIR/lovely-linux.tar.gz"
    else
        url=$(get_releases "$repo" "lovely-x86_64-pc-windows-msvc.zip")
        archive="$DOWNLOAD_DIR/lovely-windows.zip"
    fi

    if [[ -z "$url" ]]; then
        log ERROR "Could not find suitable Lovely [$MODE] release."
        return 1
    fi

    log INFO "downloading lovely from: $url"
    wget -q -O "$archive" "$url" || {
        log ERROR "Download failed."
        return 1
    }

    log INFO "extracting to "$extract_dir""
    mkdir -p "$extract_dir"
    if [[ "$MODE" == "native" ]]; then
        tar -xf "$archive" -C "$extract_dir" || return 1
        if [[ ! -f "$extract_dir/liblovely.so" ]]; then
            log ERROR "Linux Lovely library file not found"
            return 1
        fi

        log INFO "Installing liblovely.so to /lib"
        sudo mv "$extract_dir/liblovely.so" /lib/liblovely.so || return 1
        sudo ldconfig
    else
        unzip -o "$archive" -d "$extract_dir" || return 1
        if [[ ! -f "$extract_dir/version.dll" ]]; then
            log ERROR "Windows Lovely library file not found"
            return 1
        fi

        log INFO "Installing version.dll to "$GAME_PATH""
        cp "$extract_dir/version.dll" "$GAME_PATH/version.dll" || return 1
    fi

    log INFO "Finished installing Lovely [$MODE]"
    log DEBUG "Finished i_lovely."
    return 0
}

# Downloads and installs Steamodded.
i_steammodded() {
    log DEBUG "Entering i_steammodded."
    log INFO "Setting up SMODS [$MODE]"

    check git || return 1

    local repo="https://github.com/Steamodded/smods"
    local mod_dir="$MODS_DIR/smods"

    if [[ -d "$mod_dir/.git" ]]; then
        log INFO "Updating SMODS [$MODE]"
        git -C "$mod_dir" pull || {
            log ERROR "Update failed."
            return 1
        }
    else
        mkdir -p "$(dirname "$mod_dir")" || { log ERROR "Could not create parent directory for SMODS."; return 1; }
        git clone "$repo" "$mod_dir" || {
            log ERROR "Download failed."
            return 1
        }
    fi

    log INFO "SMODS [$MODE] installed to "$mod_dir""
    log DEBUG "Finished i_steammodded."
    return 0
}

# idk how im gonna handle this
i_balamod() {
    log ERROR "Balamod install not implemented yet."
    return 0
}

# --- Repo commands
r_command() {
    log VERBOSE "Dispatching repo subcommand: $1"
    case "$1" in
    add)
        shift
        r_add "$@"
        ;;
    delete)
        shift
        r_delete "$1"
        ;;
    list) r_list ;;
    sync) r_sync ;;
    help) r_help ;;
    *)
        log ERROR "Unknown repo command: $1"
        r_help
        ;;
    esac
}

# Displays help for repository commands.
r_help() {
    log INFO "jkrsh repo: manage mod repositories (JSON-based)"
    log INFO "Usage: jkrsh repo [subcommand] [args...]"
    log INFO ""
    log INFO "commands:"
    log INFO "  add                Add a new mod repository from a JSON URL."
    log INFO "  delete             Delete a local mod repository JSON file."
    log INFO "  list               List all active mod repositories."
    log INFO "  sync               Sync all mod data from the repositories."
    log INFO ""
}

# Adds a new JSON mod repository.
r_add() {
    log DEBUG "Entering r_add for name: $1, url: $2"
    check curl || return 1
    check jq || return 1

    local repo_name="$1"
    local repo_url="$2"

    if [[ -z "$repo_name" || -z "$repo_url" ]]; then
        log ERROR "Usage: jkrsh repo add <name> <url>"
        return 1
    fi

    local repo_file="$REPO_DIR/${repo_name}.json"

    if [[ -f "$repo_file" ]]; then
        log WARNING "Repository '$repo_name' already exists. Use 'repo delete' first if you want to replace it."
        return 1
    fi

    log INFO "Downloading repository JSON from '$repo_url'..."
    if ! curl -s -L "$repo_url" -o "$repo_file.tmp"; then
        log ERROR "Failed to download repository from '$repo_url'."
        rm -f "$repo_file.tmp"
        return 1
    fi

    log VERBOSE "Validating downloaded JSON structure."
    if ! jq -e '.name and .author and .description and .url and (.mods | type == "array")' "$repo_file.tmp" &>/dev/null; then
        log ERROR "Downloaded file is not a valid mod repository JSON format."
        log ERROR "Expected a JSON object with 'name', 'author', 'description', 'url', and a 'mods' array."
        rm -f "$repo_file.tmp"
        return 1
    fi

    mv "$repo_file.tmp" "$repo_file" || { log ERROR "Failed to move temporary repo file to '$repo_file'."; return 1; }

    log INFO "Repository '$repo_name' added successfully."
    r_sync
    log DEBUG "Exiting r_add."
    return 0
}

# Deletes a local mod repository JSON file.
r_delete() {
    log DEBUG "Entering r_delete for name: $1"
    local repo_name="$1"

    if [[ -z "$repo_name" ]]; then
        log ERROR "Usage: jkrsh repo delete <name>"
        return 1
    fi

    local repo_file="$REPO_DIR/${repo_name}.json"

    if [[ ! -f "$repo_file" ]]; then
        log ERROR "Repository '$repo_name' not found."
        return 1
    fi

    read -rp "Are you sure you want to delete repository '$repo_name' ($repo_file)? [Y/n] " yn
    if [[ "$yn" == [Yy]* ]]; then
        rm -f "$repo_file" || { log ERROR "Failed to delete repository file '$repo_file'."; return 1; }
        log INFO "Repository '$repo_name' deleted."
        r_sync
    else
        log INFO "Deletion cancelled."
    fi
    log DEBUG "Exiting r_delete."
    return 0
}

# Lists all active mod repositories.
r_list() {
    log DEBUG "Entering r_list."
    check jq || return 1

    log INFO "Listing active mod repositories:"
    local found_repos=0
    for repo_file in "$REPO_DIR"/*.json; do
        if [[ -f "$repo_file" ]]; then
            found_repos=$((found_repos + 1))
            local repo_info=$(jq -r '{name: .name, author: .author, description: .description, url: .url, mod_count: (.mods | length)}' "$repo_file")
            
            local name=$(echo "$repo_info" | jq -r '.name')
            local author=$(echo "$repo_info" | jq -r '.author')
            local desc=$(echo "$repo_info" | jq -r '.description')
            local url=$(echo "$repo_info" | jq -r '.url')
            local mod_count=$(echo "$repo_info" | jq -r '.mod_count')

            log SILENT "------------------------------------"
            log SILENT "Name: ${name:-$(basename "$repo_file" .json)} (${mod_count:-Unknown} mods)"
            log SILENT "Author: ${author:-Unknown}"
            log SILENT "Description: ${desc:-No description provided.}"
            log SILENT "URL: ${url:-N/A}"
        fi
    done

    if [[ "$found_repos" -eq 0 ]]; then
        log INFO "No repositories found. Add one with 'jkrsh repo add'."
    else
        log SILENT "------------------------------------"
    fi
    log DEBUG "Exiting r_list."
    return 0
}

# Sync sall the data from the repo file
r_sync() {
    log VERBOSE "Starting r_sync (JSON aggregation)."
    check jq || return 1

    log INFO "Syncing mod repositories to create aggregated index..."
    local aggregated_mods_file="$DOWNLOAD_DIR/mods_index.json"
    local all_mods_json="[]"

    for repo_file in "$REPO_DIR"/*.json; do
        if [[ -f "$repo_file" ]]; then
            log DEBUG "Aggregating mods from: $(basename "$repo_file")"
            local repo_mods=$(jq -c '.mods' "$repo_file")
            if [[ "$repo_mods" != "null" ]]; then
                all_mods_json=$(echo "$all_mods_json" "$repo_mods" | jq -s 'add | unique_by(.name | ascii_downcase)')
            fi
        fi
    done

    echo "$all_mods_json" > "$aggregated_mods_file" || { log ERROR "Failed to write aggregated mod index to '$aggregated_mods_file'."; return 1; }
    local total_mods=$(echo "$all_mods_json" | jq '. | length')
    log INFO "Aggregated $total_mods mods into '$aggregated_mods_file'."
    log DEBUG "Finished r_sync."
    return 0
}

# --- Locks script so nothing breaks
lock() {
    log VERBOSE "Attempting to acquire lock."
    echo $$ >"$LOCKFILE" || { log ERROR "Could not create lock file '$LOCKFILE'. Check permissions."; exit 1; }
    cleanup() {
        rm -f "$LOCKFILE"
        log DEBUG "Cleaned up lockfile."
    }
    trap cleanup INT TERM EXIT
    log VERBOSE "Lock acquired."
    return 0
}

# ----------- Main function
# Main entry point for the script.
main() {

    if [[ ! -f "$CONF" ]]; then
        mkconf || { log ERROR "Failed to create default config. Exiting."; exit 1; }
    fi

    load_config || { log ERROR "Failed to load configuration. Exiting."; exit 1; }

    lock || { log ERROR "Failed to acquire lock. Exiting."; exit 1; }

    check jq || { log ERROR "'jq' is required for this mod manager. Please install it."; exit 1; }

    mkrepo || { log WARNING "Failed to create default repository file."; }

    flags "$@"


    log VERBOSE "Running jkrsh $ver"
    log DEBUG "CONF: $CONF. $DEBUG|$MODE|$NOINSTALL|$MODDED_LAUNCH|$ver"

    if [[ "$SHOW_HELP" == 1 ]]; then
        help
        exit 0
    fi
    if [[ "$SHOW_VERSION" == 1 ]]; then
        version
        exit 0
    fi

    if [[ ${#ARGS[@]} -gt 0 ]]; then
        subcommand "${ARGS[@]}"
    else
        help
    fi
    exit 0
}

main "$@"
