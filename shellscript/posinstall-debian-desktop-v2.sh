#!/usr/bin/env bash
# Pós-instalação de desktop Debian. Execute como usuário comum com sudo.
# Não altera sources.list nem habilita contrib/non-free automaticamente.
set -Eeuo pipefail
umask 022

usage() {
    cat <<'HELP'
Uso: bash posinstall-debian-desktop-v2.sh [opções]
  --yes              Não pedir confirmação inicial; apt usa -y.
  --skip-upgrade     Não atualizar os pacotes já instalados.
  --skip-apps        Não instalar aplicativos externos, Brave e Telegram.
  --skip-chatgpt     Não instalar ChatGPT Desktop (prévia; Debian 13/Ubuntu 24.04 ou 26.04).
  --skip-dotfiles    Não configurar Bash, Zsh, Vim e Tmux.
  --skip-fonts       Não baixar Nerd Fonts.
  -h, --help        Mostrar esta ajuda.
Execute como usuário comum (sem sudo antes de bash). O script solicita sudo.
Aplicativos externos e fontes consultam a última release estável a cada execução.
Os pacotes APT usam a versão candidata dos repositórios configurados, que pode
ser anterior à versão mais recente do projeto. ChatGPT mantém o canal de prévia
oficial para Linux. Falhas na consulta interrompem a execução, sem fallback antigo.
HELP
}

ASSUME_YES=0
UPGRADE=1
APPS=1
CHATGPT=1
DOTFILES=1
FONTS=1
for arg in "$@"; do
    case "$arg" in
        --yes) ASSUME_YES=1 ;;
        --skip-upgrade) UPGRADE=0 ;;
        --skip-apps) APPS=0 ;;
        --skip-chatgpt) CHATGPT=0 ;;
        --skip-dotfiles) DOTFILES=0 ;;
        --skip-fonts) FONTS=0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Opção desconhecida: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
(( EUID != 0 )) || fail 'Execute como usuário comum, sem sudo antes de bash.'
[[ -r /etc/os-release && -f /etc/debian_version ]] || fail 'Este script requer Debian ou um derivado com APT.'
for cmd in sudo apt-get apt-cache dpkg dpkg-deb mktemp tee; do
    command -v "$cmd" >/dev/null || fail "Comando necessário ausente: $cmd"
done

ARCH=$(dpkg --print-architecture)
if (( APPS )) && [[ $ARCH != amd64 ]]; then
    fail 'Os downloads externos desta configuração exigem amd64. Use --skip-apps nesta arquitetura.'
fi
if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || fail 'Sem terminal interativo. Use --yes para confirmar a execução.'
    printf 'Serão instalados pacotes e alteradas configurações do usuário %s. Continuar? [s/N] ' "$(id -un)"
    read -r answer
    [[ $answer == s || $answer == S ]] || exit 0
fi
sudo -v

STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/posinstall-debian
mkdir -p "$STATE_DIR"
LOG_FILE=$(mktemp "$STATE_DIR/run-XXXXXXXX.log")
WORK_DIR=$(mktemp -d -t posinstall-debian.XXXXXXXX)
BACKUP_DIR=$STATE_DIR/backups/$(basename "$WORK_DIR")
cleanup() { rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'code=$?; printf "ERRO na linha %s (código %s). Consulte: %s\n" "$LINENO" "$code" "$LOG_FILE" >&2; exit "$code"' ERR
exec > >(tee -a "$LOG_FILE") 2>&1
printf 'Log: %s\n' "$LOG_FILE"

step() { printf '\n==> %s\n' "$*"; }
download() {
    local url=$1 dest=$2
    curl --fail --show-error --location --retry 3 --connect-timeout 20 \
        --max-time 1800 --proto '=https' --proto-redir '=https' \
        --output "$dest.part" "$url"
    mv -- "$dest.part" "$dest"
}
backup() {
    local file=$1 relative=${1#"$HOME/"}
    if [[ -e $file || -L $file ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
        cp -a -- "$file" "$BACKUP_DIR/$relative"
    fi
}
install_dotfile() {
    local url=$1 dest=$2
    download "$url" "$WORK_DIR/dotfile"
    if [[ -f $dest ]] && cmp -s "$WORK_DIR/dotfile" "$dest"; then
        return
    fi
    backup "$dest"
    mkdir -p "$(dirname "$dest")"
    install -m 0644 "$WORK_DIR/dotfile" "$dest"
}
managed_block() {
    local dest=$1 begin='# >>> posinstall-debian >>>' end='# <<< posinstall-debian <<<'
    # Recusa marcadores inconsistentes para não remover conteúdo do usuário.
    if [[ -f $dest ]]; then
        awk -v begin="$begin" -v end="$end" '
            $0 == begin { if (inside) exit 1; inside=1; next }
            $0 == end { if (!inside) exit 1; inside=0 }
            END { if (inside) exit 1 }
        ' "$dest" || fail "Marcadores inválidos em $dest"
    fi
    backup "$dest"
    if [[ -f $dest ]]; then
        awk -v begin="$begin" -v end="$end" '
            $0 == begin { inside=1; next }
            $0 == end { inside=0; next }
            !inside { print }
        ' "$dest" > "$WORK_DIR/rc"
    else
        : > "$WORK_DIR/rc"
    fi
    { printf '%s\n' "$begin"; cat; printf '%s\n' "$end"; } >> "$WORK_DIR/rc"
    cat "$WORK_DIR/rc" > "$dest"
}
install_deb() {
    local url=$1 name=$2 checksum=${3:-} package_arch
    download "$url" "$WORK_DIR/$name.deb"
    if [[ -n $checksum ]]; then
        [[ $checksum =~ ^[[:xdigit:]]{128}$ ]] || fail "SHA-512 inválido para $name"
        printf '%s  %s\n' "$checksum" "$WORK_DIR/$name.deb" | sha512sum --check -
    fi
    package_arch=$(dpkg-deb -f "$WORK_DIR/$name.deb" Architecture)
    [[ $package_arch == "$ARCH" || $package_arch == all ]] || fail "Arquitetura incompatível: $name ($package_arch)"
    # Diretório mktemp é privado; use root para ler o .deb local.
    sudo apt-get -o APT::Sandbox::User=root install -y "$WORK_DIR/$name.deb"
}


# Cache de metadados por execução: todas as fontes usam a mesma release.
github_metadata() {
    local repo=$1 dest=$WORK_DIR/github-${1//\//-}.json
    if [[ ! -s $dest ]]; then
        download "https://api.github.com/repos/$repo/releases/latest" "$dest"
    fi
    printf '%s\n' "$dest"
}
github_asset() {
    local repo=$1 pattern=$2 metadata
    metadata=$(github_metadata "$repo")
    python3 - "$metadata" "$pattern" "$repo" <<'PY'
import json, re, sys
from urllib.parse import urlsplit
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
if release.get("draft") or release.get("prerelease"):
    sys.exit("A API não retornou uma release estável.")
assets = [a for a in release.get("assets", []) if re.fullmatch(sys.argv[2], a["name"])]
if len(assets) != 1:
    sys.exit("Asset ausente ou ambíguo: " + sys.argv[2])
url = assets[0]["browser_download_url"]
prefix = "https://github.com/" + sys.argv[3] + "/releases/download/"
if not url.startswith(prefix) or urlsplit(url).scheme != "https":
    sys.exit("URL de release não pertence ao repositório esperado.")
print(url)
PY
}
install_proton_latest() {
    local metadata_url=$1 name=$2
    local -a release
    download "$metadata_url" "$WORK_DIR/$name.json"
    python3 - "$WORK_DIR/$name.json" > "$WORK_DIR/$name.release" <<'PY'
import json, re, sys
from urllib.parse import urlsplit
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
releases = [r for r in data["Releases"] if r.get("CategoryName") == "Stable"
            and re.fullmatch(r"\d+(?:\.\d+)*", r.get("Version", ""))]
if not releases:
    sys.exit("Nenhuma release estável encontrada nos metadados da Proton.")
release = max(releases, key=lambda r: tuple(map(int, r["Version"].split("."))))
files = [f for f in release["File"] if urlsplit(f.get("Url", "")).path.endswith(".deb")]
if len(files) != 1:
    sys.exit("Pacote DEB ausente ou ambíguo nos metadados da Proton.")
file = files[0]
url = urlsplit(file["Url"])
if url.scheme != "https" or url.netloc != "proton.me" or not url.path.startswith("/download/"):
    sys.exit("URL de download inesperada para a Proton.")
if not re.fullmatch(r"[0-9a-fA-F]{128}", file.get("Sha512CheckSum", "")):
    sys.exit("SHA-512 inválido nos metadados da Proton.")
print(release["Version"])
print(file["Url"])
print(file["Sha512CheckSum"])
PY
    mapfile -t release < "$WORK_DIR/$name.release"
    step "Instalando $name ${release[0]} (estável)"
    install_deb "${release[1]}" "$name" "${release[2]}"
}
install_protonvpn_repository() {
    local base=https://repo.protonvpn.com/debian/dists/stable/main/binary-all file
    download "$base/" "$WORK_DIR/protonvpn-index.html"
    file=$(python3 - "$WORK_DIR/protonvpn-index.html" <<'PY'
import re, sys
from html.parser import HTMLParser
class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.files = []
    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href", "")
            if re.fullmatch(r"protonvpn-stable-release_\d+(?:[.\-]\d+)*_all\.deb", href):
                self.files.append(href)
parser = Links()
with open(sys.argv[1], encoding="utf-8") as f:
    parser.feed(f.read())
if not parser.files:
    sys.exit("Pacote do repositório estável do Proton VPN não encontrado.")
print(max(parser.files, key=lambda s: tuple(map(int, re.findall(r"\d+", s)))))
PY
    )
    install_deb "$base/$file" protonvpn-release
}

step 'Atualizando índices e instalando dependências'
sudo apt-get update
sudo apt-get install -y ca-certificates curl git unzip xz-utils fontconfig python3
if (( UPGRADE )); then
    step 'Atualizando o sistema'
    sudo apt-get upgrade -y
fi

packages=(
    htop iotop iftop hdparm plocate traceroute tree ipcalc whois dnsutils
    net-tools ncdu bash-completion grc nmap links tcpdump ethtool iptraf-ng
    micro qbittorrent sed bpytop eza python3-pip golang zsh gnome-tweaks
    tilix flatpak bat zoxide ripgrep duf vim-nox tmux kitty fzf
    wireguard-tools starship
)
step 'Verificando disponibilidade dos pacotes'
available=()
missing=()
for package in "${packages[@]}"; do
    candidate=$(LC_ALL=C apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')
    if [[ -n $candidate && $candidate != '(none)' ]]; then
        available+=("$package")
    else
        missing+=("$package")
    fi
done
if (( ${#missing[@]} )); then
    printf 'AVISO: pacotes sem candidato nos repositórios atuais: %s\n' "${missing[*]}"
fi
if (( ${#available[@]} )); then
    sudo apt-get install -y "${available[@]}"
fi

if (( APPS )); then
    step 'Instalando aplicativos externos (downloads HTTPS dos fornecedores)'
    # Pacotes .deb diretos são validados por arquitetura; Proton também por SHA-512.
    obsidian_url=$(github_asset obsidianmd/obsidian-releases 'obsidian_.*_amd64\.deb')
    install_deb "$obsidian_url" obsidian
    localsend_url=$(github_asset localsend/localsend 'LocalSend-.*-linux-x86-64\.deb')
    install_deb "$localsend_url" localsend
    install_proton_latest 'https://proton.me/download/mail/linux/version.json' proton-mail
    install_protonvpn_repository
    sudo apt-get update
    sudo apt-get install -y proton-vpn-gnome-desktop
    install_proton_latest 'https://proton.me/download/PassDesktop/linux/x64/version.json' proton-pass

    if (( CHATGPT )); then
        step 'Instalando ChatGPT Desktop oficial (prévia para Linux)'
        # https://learn.chatgpt.com/docs/linux/linux-app
        # Suporte oficial: Debian 13, Ubuntu 24.04 LTS e 26.04 LTS.
        # O pacote configura o repositório assinado para atualizações pelo APT.
        install_deb 'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb' chatgpt
    fi

    step 'Instalando Codex CLI para o usuário atual'
    # https://learn.chatgpt.com/docs/codex/cli
    # Instalador independente oficial: não requer Node.js/npm nem sudo.
    download 'https://chatgpt.com/codex/install.sh' "$WORK_DIR/codex-install.sh"
    sh "$WORK_DIR/codex-install.sh"

    step 'Configurando repositório oficial do Brave'
    download 'https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg' "$WORK_DIR/brave.gpg"
    download 'https://brave-browser-apt-release.s3.brave.com/brave-browser.sources' "$WORK_DIR/brave.sources"
    sudo install -D -m 0644 "$WORK_DIR/brave.gpg" /usr/share/keyrings/brave-browser-archive-keyring.gpg
    sudo install -D -m 0644 "$WORK_DIR/brave.sources" /etc/apt/sources.list.d/brave-browser-release.sources
    sudo apt-get update
    sudo apt-get install -y brave-browser

    step 'Instalando Telegram para o usuário atual'
    download 'https://telegram.org/dl/desktop/linux' "$WORK_DIR/telegram.tar.xz"
    mkdir -p "$WORK_DIR/telegram" "$HOME/.local/opt" "$HOME/.local/bin"
    tar -xJf "$WORK_DIR/telegram.tar.xz" -C "$WORK_DIR/telegram" --no-same-owner --no-same-permissions
    [[ -x $WORK_DIR/telegram/Telegram/Telegram ]] || fail 'Arquivo do Telegram inválido.'
    backup "$HOME/.local/opt/Telegram"
    mkdir -p "$HOME/.local/opt/Telegram"
    cp -a "$WORK_DIR/telegram/Telegram/." "$HOME/.local/opt/Telegram/"
    if [[ -e $HOME/.local/bin/telegram || -L $HOME/.local/bin/telegram ]]; then
        backup "$HOME/.local/bin/telegram"
    fi
    ln -sfn "$HOME/.local/opt/Telegram/Telegram" "$HOME/.local/bin/telegram"
fi

if (( DOTFILES )); then
    step 'Configurando shells e dotfiles com backup'
    DOTFILES_URL=https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux
    install_dotfile "$DOTFILES_URL/bash_aliases" "$HOME/.bash_aliases"
    install_dotfile "$DOTFILES_URL/aliases.zsh" "$HOME/.zsh/aliases.zsh"
    install_dotfile "$DOTFILES_URL/vimrc" "$HOME/.vimrc"
    install_dotfile "$DOTFILES_URL/molokai-dark.vim" "$HOME/.vim/colors/molokai-dark.vim"
    install_dotfile "$DOTFILES_URL/tmux.conf" "$HOME/.tmux.conf"
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        if [[ ! -e $HOME/.zsh/$plugin ]]; then
            git clone --depth 1 "https://github.com/zsh-users/$plugin.git" "$HOME/.zsh/$plugin"
        fi
    done
    managed_block "$HOME/.bashrc" <<'BASHRC'
command -v starship >/dev/null && eval "$(starship init bash)"
if command -v fzf >/dev/null; then
    if fzf --help 2>/dev/null | command grep -q -- '--bash'; then
        eval "$(fzf --bash)"
    else
        [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]] && source /usr/share/doc/fzf/examples/key-bindings.bash
        [[ -r /usr/share/bash-completion/completions/fzf ]] && source /usr/share/bash-completion/completions/fzf
    fi
fi
BASHRC
    managed_block "$HOME/.zshrc" <<'ZSHRC'
command -v starship >/dev/null && eval "$(starship init zsh)"
if command -v fzf >/dev/null; then
    if fzf --help 2>/dev/null | command grep -q -- '--zsh'; then
        source <(fzf --zsh)
    else
        [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
        [[ -r /usr/share/doc/fzf/examples/completion.zsh ]] && source /usr/share/doc/fzf/examples/completion.zsh
    fi
fi
[[ -r ~/.zsh/aliases.zsh ]] && source ~/.zsh/aliases.zsh
[[ -r ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSHRC
fi

if (( FONTS )); then
    step 'Instalando Nerd Fonts'
    fonts_metadata=$(github_metadata ryanoasis/nerd-fonts)
    NERD_FONTS_VERSION=$(python3 - "$fonts_metadata" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
tag = release.get("tag_name", "")
if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v\d+(?:\.\d+)*", tag):
    sys.exit("Release estável inválida para Nerd Fonts.")
print(tag[1:])
PY
    )
    printf 'Nerd Fonts: %s\n' "$NERD_FONTS_VERSION"
    fonts=(FiraCode Hack Inconsolata Ubuntu UbuntuMono ProFont Meslo SourceCodePro RobotoMono JetBrainsMono)
    for font in "${fonts[@]}"; do
        font_dir=$HOME/.local/share/fonts/NerdFonts/$font
        # O marcador só é gravado após extração bem-sucedida.
        [[ -f $font_dir/.version ]] && [[ $(cat "$font_dir/.version") == "$NERD_FONTS_VERSION" ]] && continue
        font_url=$(github_asset ryanoasis/nerd-fonts "${font}\\.zip")
        download "$font_url" "$WORK_DIR/$font.zip"
        mkdir -p "$font_dir"
        unzip -oq "$WORK_DIR/$font.zip" -d "$font_dir"
        printf '%s\n' "$NERD_FONTS_VERSION" > "$font_dir/.version"
    done
    fc-cache -f "$HOME/.local/share/fonts"
fi

step 'Concluído'
printf 'Log: %s\nBackups, quando necessários: %s\n' "$LOG_FILE" "$BACKUP_DIR"
if (( ${#missing[@]} )); then
    printf 'Pacotes não instalados por indisponibilidade: %s\n' "${missing[*]}"
fi
printf 'Abra um novo terminal para carregar as configurações.\n'
if (( APPS )); then
    printf 'Codex CLI: abra um novo terminal e execute codex para entrar na sua conta.\n'
    if (( CHATGPT )); then
        printf 'ChatGPT: disponível no menu de aplicativos ou pelo comando chatgpt.\n'
    fi
    printf 'Telegram: %s (adicione ~/.local/bin ao PATH, se necessário).\n' "$HOME/.local/bin/telegram"
fi
if [[ -f /var/run/reboot-required ]]; then
    printf 'O sistema sinalizou que precisa ser reiniciado.\n'
fi
