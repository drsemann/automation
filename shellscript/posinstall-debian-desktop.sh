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
#
######################################################################

# Variaveis de configuração
#
#
# Cores
GREEN='\e[32m'
RESET='\e[0m'
#
#

pacotes=(
	htop iotop iftop hdparm locate traceroute tree
	ipcalc whois dnsutils net-tools ncdu bash-completion curl 
	grc nmap links tcpdump ethtool iptraf-ng micro 
	qbittorrent sed bpytop eza python3-pip golang zsh 
	gnome-tweaks tilix onedrive flatpak bat zoxide ripgrep duf
	vim-nox tmux kitty fzf wireguard-tools starship git
)

clear

echo -e '
 ███████                   ██                    ██              ██  ██
░██░░░░██                 ░░                    ░██             ░██ ░██
░██   ░██  ██████   ██████ ██ ███████   ██████ ██████  ██████   ░██ ░██
░███████  ██░░░░██ ██░░░░ ░██░░██░░░██ ██░░░░ ░░░██░  ░░░░░░██  ░██ ░██
░██░░░░  ░██   ░██░░█████ ░██ ░██  ░██░░█████   ░██    ███████  ░██ ░██
░██      ░██   ░██ ░░░░░██░██ ░██  ░██ ░░░░░██  ░██   ██░░░░██  ░██ ░██
░██      ░░██████  ██████ ░██ ███  ░██ ██████   ░░██ ░░████████ ███ ███
░░        ░░░░░░  ░░░░░░  ░░ ░░░   ░░ ░░░░░░     ░░   ░░░░░░░░ ░░░ ░░░
 ███████           ██      ██
░██░░░░██         ░██     ░░
░██    ░██  █████ ░██      ██  ██████   ███████
░██    ░██ ██░░░██░██████ ░██ ░░░░░░██ ░░██░░░██
░██    ░██░███████░██░░░██░██  ███████  ░██  ░██
░██    ██ ░██░░░░ ░██  ░██░██ ██░░░░██  ░██  ░██
░███████  ░░██████░██████ ░██░░████████ ███  ░██
░░░░░░░    ░░░░░░ ░░░░░   ░░  ░░░░░░░░ ░░░   ░░
\n'


DESC="Atualizando o sistema"
printf "\r[ .. ] $DESC"
(sudo apt update  && apt upgrade -y) > /tmp/posinstall.log 2>&1
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

DESC="Instalando pacotes basicos"
printf "\r[ .. ] $DESC"
sudo apt install -y ${pacotes[*]} > /tmp/posinstall.log 2>&1
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

DESC="Baixando softwares"
printf "\r[ .. ] $DESC"
wget -O /tmp/onlyoffice-desktopeditors_amd64.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb > /tmp/posinstall.log 2>&1
wget -O /tmp/obsidian_1.9.14_amd64.deb https://github.com/obsidianmd/obsidian-releases/releases/download/v1.9.14/obsidian_1.9.14_amd64.deb > /tmp/posinstall.log 2>&1
wget -O /tmp/sublime-text_build-4200_amd64.deb https://download.sublimetext.com/sublime-text_build-4200_amd64.deb > /tmp/posinstall.log 2>&1
wget -O /tmp/LocalSend-1.17.0-linux-x86-64.deb https://github.com/localsend/localsend/releases/download/v1.17.0/LocalSend-1.17.0-linux-x86-64.deb > /tmp/posinstall.log 2>&1
wget -O /tmp/ProtonMail-desktop-beta.deb https://proton.me/download/mail/linux/1.10.0/ProtonMail-desktop-beta.deb > /tmp/posinstall.log 2>&1
wget -O /tmp/protonvpn-stable-release_1.0.8_all.deb https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb > /tmp/posinstall.log 2>&1
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

DESC="Instalando softwares"
printf "\r[ .. ] $DESC"
sudo apt-get install -y /tmp/onlyoffice-desktopeditors_amd64.deb > /tmp/posinstall.log 2>&1 
sudo apt-get install -y /tmp/obsidian_1.9.14_amd64.deb > /tmp/posinstall.log 2>&1
sudo apt-get install -y /tmp/sublime-text_build-4200_amd64.deb > /tmp/posinstall.log 2>&1
sudo apt-get install -y /tmp/LocalSend-1.17.0-linux-x86-64.deb > /tmp/posinstall.log 2>&1
sudo apt-get install -y /tmp/ProtonMail-desktop-beta.deb > /tmp/posinstall.log 2>&1
sudo apt-get install -y /tmp/protonvpn-stable-release_1.0.8_all.deb > /tmp/posinstall.log 2>&1
sudo apt-get update -y > /tmp/posinstall.log 2>&1
sudo apt-get install -y proton-vpn-gnome-desktop > /tmp/posinstall.log 2>&1
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

### .bashrc
DESC="Bashrc"
echo "eval \"\$(starship init bash)\"" >> ~/.bashrc
echo "eval \"\$(fzf --bash)\"" >> ~/.bashrc
wget -O ~/.bash_aliases https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux/bash_aliases > /tmp/posinstall.log 2>&1
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

### .zshrc
DESC="Zshrc"
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions > /tmp/posinstall.log 2>&1
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/zsh-syntax-highlighting > /tmp/posinstall.log 2>&1
wget -O ~/.zsh/aliases.zsh https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux/aliases.zsh > /tmp/posinstall.log 2>&1

echo "eval \"\$(starship init zsh)\"" >> ~/.zshrc
echo "source <(fzf --zsh)" >> ~/.zshrc
echo "source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" >> ~/.zshrc
echo "source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc
echo "source ~/.zsh/aliases.zsh" >> ~/.zshrc
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"

### .vimrc
DESC="Vimrc"
wget -O ~/.vimrc https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux/vimrc > /tmp/posinstall.log 2>&1 &
mkdir -p ~/.vim/colors
wget https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux/molokai-dark.vim -P ~/.vim/colors > /tmp/posinstall.log 2>&1 &
printf "\r[ ${GREEN}OK${RESET} ] $DESC"

### .tmux.conf
DESC="Tmux"
wget -O ~/.tmux.conf https://raw.githubusercontent.com/drsemann/dotfiles/refs/heads/main/Linux/tmux.conf > /tmp/posinstall.log 2>&1 &
printf "\r[ ${GREEN}OK${RESET} ] $DESC"
echo -e "\n"