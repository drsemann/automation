#!/usr/bin/env bash
# Configuracao inicial para Debian 12/13. Execute com sudo ou como root.
set -Eeuo pipefail
umask 022

usage() {
    cat <<'HELP'
Uso: sudo bash debian-posinstall.sh [opcoes]
  --user NOME           Configura root e este usuario existente; pode repetir.
                        Sem a opcao, usa SUDO_USER. Como root, informe --user.
  --dotfiles-only       Apenas configura os dotfiles, sem APT.
  --reset-repositories Substitui fontes APT por fontes oficiais (com backup).
                        Desativa tambem fontes de terceiros; opcao explicita.
  --no-upgrade          Nao executa apt-get upgrade.
  -h, --help            Exibe esta ajuda.
Nao cria contas. Backups e log: /var/backups/debian-posinstall/<execucao>/
HELP
}
die() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
log() { printf '\n[%s] %s\n' "$(date +%T)" "$*"; }
users=()
dotfiles_only=0
reset_repositories=0
upgrade=1
while (($#)); do
    case "$1" in
        --user) (($# >= 2)) || die 'Informe o nome apos --user.'; users+=("$2"); shift 2 ;;
        --dotfiles-only) dotfiles_only=1; shift ;;
        --reset-repositories) reset_repositories=1; shift ;;
        --no-upgrade) upgrade=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Opcao desconhecida: $1" ;;
    esac
done
((EUID == 0)) || die 'Execute com sudo ou como root.'
# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == debian ]] || die 'Este script requer Debian.'
case ${VERSION_ID:-} in 12|13) ;; *) die 'Versao suportada: Debian 12 ou 13.' ;; esac
if ((${#users[@]} == 0)); then
    [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] || die 'Informe --user NOME para configurar tambem um usuario comum.'
    users+=("$SUDO_USER")
fi
# Valide todos os destinos antes de alterar o servidor.
accounts=(root)
homes=()
uids=()
gids=()
for user in "${users[@]}"; do
    [[ $user != root && $user != -* ]] || die "Usuario comum invalido: $user"
    accounts+=("$user")
done
for user in "${accounts[@]}"; do
    entry=$(getent passwd "$user") || die "Usuario inexistente: $user"
    IFS=: read -r name _ uid gid _ home shell <<< "$entry"
    [[ $name == "$user" && $home == /* && $home != / && -d $home && ! -L $home ]] || die "Home invalido para $user: $home"
    [[ $shell == */bash ]] || die "O shell de $user deve ser Bash (atual: $shell)."
    for filename in .bashrc .bashrc.posinstall .vimrc .tmux.conf; do
        target=$home/$filename
        [[ ! -L $target ]] || die "Link simbolico recusado: $target"
        [[ ! -e $target || -f $target ]] || die "Destino nao e arquivo: $target"
    done
    homes+=("$home"); uids+=("$uid"); gids+=("$gid")
done
install -d -m 0700 /var/backups/debian-posinstall
backup_dir=$(mktemp -d /var/backups/debian-posinstall/"$(date +%Y%m%d-%H%M%S)".XXXXXX)
exec > >(tee -a "$backup_dir/execution.log") 2>&1
trap 'rc=$?; printf "ERRO na linha %s (codigo %s). Log: %s/execution.log\n" "$LINENO" "$rc" "$backup_dir" >&2; exit "$rc"' ERR
backup() {
    local path=$1
    if [[ -e $path || -L $path ]]; then
        if [[ ! -e $backup_dir$path && ! -L $backup_dir$path ]]; then
            mkdir -p -- "$backup_dir$(dirname -- "$path")"
            cp -a -- "$path" "$backup_dir$path"
        fi
    fi
}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

if ((!dotfiles_only)); then
    if ((reset_repositories)); then
        log 'Salvando e substituindo fontes APT por repositorios oficiais'
        [[ -n ${VERSION_CODENAME:-} ]] || die 'VERSION_CODENAME ausente.'
        [[ -f /usr/share/keyrings/debian-archive-keyring.gpg ]] || die 'Chaveiro Debian ausente.'
        backup /etc/apt/sources.list
        backup /etc/apt/sources.list.d
        install -d /etc/apt/sources.list.d
        shopt -s nullglob
        for source_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            mv -- "$source_file" "$source_file.disabled-$(basename "$backup_dir")"
        done
        shopt -u nullglob
        # Remove eventual symlink antes de escrever o arquivo gerenciado.
        rm -f /etc/apt/sources.list
        install -m 0644 /dev/null /etc/apt/sources.list
        cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $VERSION_CODENAME ${VERSION_CODENAME}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${VERSION_CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    fi
    log 'Atualizando indices APT'
    apt-get -o APT::Update::Error-Mode=any update
    if ((upgrade)); then
        log 'Atualizando pacotes; prompts de configuracao continuam interativos'
        apt-get upgrade -y
    fi
    packages=(ca-certificates fzf vim-nox tmux htop iotop iftop hdparm plocate
        traceroute tree ipcalc whois dnsutils net-tools ncdu bash-completion
        curl grc nmap links tcpdump ethtool iptraf-ng micro btop python3-pip
        bat zoxide ripgrep duf)
    log 'Instalando pacotes'
    apt-get install -y "${packages[@]}"
fi

cat > "$work/bashrc" <<'BASHRC'
# Gerenciado por debian-posinstall.sh; carregado pelo .bashrc.
[[ $- == *i* ]] || return
umask 022
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend checkwinsize
if (( EUID == 0 )); then
    PS1='\[\e[31m\]\u\[\e[0m\]@\[\e[36m\]\h\[\e[0m\]:\w\$ '
else
    PS1='\[\e[32m\]\u\[\e[0m\]@\[\e[36m\]\h\[\e[0m\]:\w\$ '
fi
command -v dircolors >/dev/null && eval "$(dircolors -b)"
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -lah'
alias l='ls -lhA'
alias grep='grep --color=auto'
alias ip='ip -color=auto'
alias diff='diff --color=auto'
alias meuip='curl -fsS --max-time 10 https://ifconfig.me; printf "\n"'
if command -v grc >/dev/null; then
    for cmd in tail ping ps netstat dig traceroute ifconfig; do
        command -v "$cmd" >/dev/null && alias "$cmd=grc $cmd"
    done
    unset cmd
fi
if command -v batcat >/dev/null; then alias bat=batcat; fi
_posinstall_apt() {
    if (( EUID == 0 )); then command apt-get "$@"
    elif command -v sudo >/dev/null; then sudo apt-get "$@"
    else printf 'Execute esta operacao como root ou instale/configure sudo.\n' >&2; return 1
    fi
}
aptu() { _posinstall_apt update && _posinstall_apt upgrade; }
apti() { _posinstall_apt install "$@"; }
aptr() { _posinstall_apt remove "$@"; }
apts() { apt-cache search "$@"; }
aptc() { _posinstall_apt autoremove && _posinstall_apt clean; }
if ! shopt -oq posix && [[ -r /usr/share/bash-completion/bash_completion ]] && ! declare -F _init_completion >/dev/null; then
    source /usr/share/bash-completion/bash_completion
fi
if command -v fzf >/dev/null; then
    if fzf_init=$(fzf --bash 2>/dev/null); then
        eval "$fzf_init"
    else
        for fzf_file in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/bash-completion/completions/fzf; do
            [[ ! -r $fzf_file ]] || source "$fzf_file"
        done
        unset fzf_file
    fi
    unset fzf_init
fi
command -v zoxide >/dev/null && eval "$(zoxide init bash)"
# Mantenha status de carregamento bem-sucedido mesmo sem ferramentas opcionais.
true
BASHRC
cat > "$work/vimrc" <<'VIMRC'
" Gerenciado por debian-posinstall.sh
set nocompatible
syntax on
filetype plugin indent on
set background=dark
set completeopt=menuone,noselect
set cursorline hidden
set mouse=
set splitbelow splitright
set title
set ttimeoutlen=50
set shiftwidth=4 tabstop=4 expandtab
set scrolloff=10 nowrap
set incsearch ignorecase smartcase hlsearch
set showcmd showmode showmatch
set history=1000 wildmenu wildmode=list:longest
set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.img,*.xlsx
VIMRC
cat > "$work/tmux.conf" <<'TMUX'
# Gerenciado por debian-posinstall.sh
unbind C-b
set -g prefix C-a
bind C-a send-prefix
bind r source-file ~/.tmux.conf \; display-message 'Configuracao recarregada'
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D
set -g default-terminal 'screen-256color'
set -s escape-time 10
set -g set-titles on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
setw -g automatic-rename on
set -g allow-rename off
bind | split-window -h -c '#{pane_current_path}'
bind - split-window -v -c '#{pane_current_path}'
unbind '"'
unbind %
bind Tab last-window
TMUX
for i in "${!accounts[@]}"; do
    log "Configurando dotfiles: ${accounts[i]} (${homes[i]})"
    for pair in 'bashrc:.bashrc.posinstall' 'vimrc:.vimrc' 'tmux.conf:.tmux.conf'; do
        src=${pair%%:*}; dest=${homes[i]}/${pair#*:}
        backup "$dest"
        install -o "${uids[i]}" -g "${gids[i]}" -m 0644 "$work/$src" "$dest"
    done
    bashrc=${homes[i]}/.bashrc
    backup "$bashrc"
    # Preserva o conteudo existente e evita duplicar o carregamento.
    include='[ ! -r "$HOME/.bashrc.posinstall" ] || . "$HOME/.bashrc.posinstall"'
    if ! grep -Fqx -- "$include" "$bashrc" 2>/dev/null; then
        printf '\n# Configuracao local do posinstall\n%s\n' "$include" >> "$bashrc"
    fi
    chown "${uids[i]}:${gids[i]}" "$bashrc"
    bash -n "$bashrc"
    bash -n "${homes[i]}/.bashrc.posinstall"
done
log "Concluido. Backups e log: $backup_dir"
printf 'Abra uma nova sessao Bash para carregar os dotfiles.\n'
[[ ! -f /var/run/reboot-required ]] || printf 'O sistema indica que uma reinicializacao e necessaria.\n'
