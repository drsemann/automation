#!/usr/bin/env bash
#
#
# Script para configuração inicial de servidores Debian e derivados.
#
# O que é configurado pelo script:
# 1 - Ajusta sourcelist com contrib e non-free
# 2 - Atualiza repositorios e atualiza o sistema.
# 3 - Instala pacotes basicos.
# 4 - Configura bash e alias.
# 5 - Configura fzf
# 6 - Habilitar e configuraro o Fail2ban


# Variaveis de configuração
#
# Distro utilizada para criar o sourcelist
DISTRO_NAME="`lsb_release -s -c`"

# Habilita fail2ban?
F2B_ENABLE="Y"
# Coloque nessa lista usando espacos os IPs que o fail2ban nao podera bloquear.
# Adicione pelo menos o IP do servidor, IP do gateway, o seu DNS e o IP ou rede que voce
# usara para acessar esse servidor.
F2B_IGNOREIP="127.0.0.1 ::1"
# Tempo de banimento para o fail2ban
F2B_BANTIME="72h"
# Limite de tentativas antes do bloqueio
F2B_MAXRETRY="5"

echo -e "Configurando repositorios APT em /etc/apt/sources.list..."

cat << EOF > /etc/apt/sources.list
deb http://security.debian.org/debian-security $DISTRO_NAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $DISTRO_NAME main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $DISTRO_NAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $DISTRO_NAME-backports main contrib non-free non-free-firmware
EOF

echo -e "Atualizando o sistema e instalando alguns pacotes uteis..."
apt -y update && apt -y full-upgrade

echo -e "Instalando pacotes basicos..."
apt install -y fzf vim-nox tmux htop iotop iftop hdparm locate traceroute tree ipcalc whois dnsutils net-tools ncdu bash-completion curl grc nmap links tcpdump ethtool iptraf-ng micro sed btop python3-pip golang bat zoxide ripgrep duf fail2ban bind9utils

cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = $F2B_IGNOREIP
bantime  = $F2B_BANTIME
findtime  = 1m
maxretry = $F2B_MAXRETRY
banaction = route
banaction_allports = route
action = %(action_)s

[sshd]
enabled = true
EOF

cat << EOF > /etc/fail2ban/action.d/route.local
# Fail2Ban configuration file
#
# Author: Michael Gebetsroither
#
# This is for blocking whole hosts through blackhole routes.
#
# PRO:
#   - Works on all kernel versions and as no compatibility problems (back to debian lenny and WAY further).
#   - It's FAST for very large numbers of blocked ips.
#   - It's FAST because it Blocks traffic before it enters common iptables chains used for filtering.
#   - It's per host, ideal as action against ssh password bruteforcing to block further attack attempts.
#   - No additional software required beside iproute/iproute2
#
# CON:
#   - Blocking is per IP and NOT per service, but ideal as action against ssh password bruteforcing hosts

[Definition]
actionban   = ip route add <blocktype> <ip>
actionunban = ip route del <blocktype> <ip>
actioncheck =
actionstart =
actionstop =

[Init]

# Option:  blocktype
# Note:    Type can be blackhole, unreachable and prohibit. Unreachable and prohibit correspond to the ICMP reject messages.
# Values:  STRING
blocktype = blackhole
EOF

systemctl enable fail2ban.service
systemctl restart fail2ban.service

### .bashrc

cat << 'EOF' > /root/.bashrc
PS1="\e[32m\]\u\[\e[m\]@\[\e[36m\]\h\[\e[m:\W$ "
umask 022

export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'
alias grep='grep --color'
alias egrep='egrep --color'
alias ip='ip -c'
alias diff='diff --color'
alias meuip='curl ifconfig.me; echo;'
alias tail='grc tail'
alias ping='grc ping'
alias ps='grc ps'
alias netstat='grc netstat'
alias dig='grc dig'
alias traceroute='grc traceroute'
alias aptu='apt update -y;apt upgrade -y'
alias apti='apt install -y'
alias aptr='apt remove -y'
alias apts='apt search'
alias aptc='apt autoremove -y;apt clean all'
alias ifconfig='grc ifconfig'
alias l='ls -lh'
alias la='ls -lha'

eval "$(fzf --bash)"
EOF

### .vimrc

cat << 'EOF' > /root/.vimrc
set background=dark
set clipboard=unnamedplus
set completeopt=noinsert,menuone,noselect
set cursorline
set hidden
set mouse-=a
set splitbelow splitright
set title
set ttimeoutlen=0
set nocompatible
filetype on
filetype plugin on
filetype indent on
syntax on
set shiftwidth=4
set tabstop=4
set expandtab
set nobackup
set scrolloff=10
set nowrap
set incsearch
set ignorecase
set smartcase
set showcmd
set showmode
set showmatch
set hlsearch
set history=1000
set wildmenu
set wildmode=list:longest
set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx
EOF

### .tmux.conf
cat << 'EOF' > /root/.tmux.conf
# Alterando prefixo de 'C-b' para 'C-a'
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# Recarregar configuracao
bind r source-file ~/.tmux.conf \; display '~/.tmux.conf reloaded'

# Alternar entre os paineis com as setas sem prefixo
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

set -g default-terminal "screen-256color"
set -s escape-time 10
set -g set-titles on

# Numero inicia com 1 nas janelas
set -g base-index 1

set -g renumber-windows on
setw -g automatic-rename on
set -g allow-rename off

# Alterado atalho de split horizontal e vertical
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

bind Tab last-window
EOF

source /root/.bashrc