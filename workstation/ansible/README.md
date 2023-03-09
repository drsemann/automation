## Playbook para pos-instalação de workstation (Ubuntu/Fedora)

### Versão do Ansible necessária
- Versão 2.14 ou superior

### Variáveis
- Ajustar variáveis no **group_vars/all.yaml**.
- Ajustar variáveis na pasta **defaults** nas roles **apps** e **devops**

### Comando de execução

```shell
# ansible-playbook -K workstation.yaml
```

### Homologado nas distros
- Fedora 37
- Ubuntu 22.04

### Observação
No ubuntu é necessário utilizar o ansible instalado via PIP, a versão do repositório padrão é menor que a necessária.

### Procedimento a ser efetuado no Ubuntu

#### Instalação de pacote python3-pip
```shell
# sudo apt install python3-pip
```
#### Instalação do ansible via pip
```shell
# sudo python3 -m pip install ansible
```