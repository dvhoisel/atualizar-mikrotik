# Script para Atualização de Equipamentos Mikrotik

Este script automatiza o processo de atualização do RouterOS em múltiplos equipamentos Mikrotik. Ele verifica a versão mais recente disponível, baixa os arquivos necessários e configura cada equipamento para realizar a atualização na data e hora programadas.

## Funcionalidades

- Verifica automaticamente a versão mais recente do RouterOS disponível
  - Consulta a página oficial de changelogs da MikroTik para obter a versão mais recente estável
  - Inclui múltiplos métodos de fallback para detecção de versão
- Permite definir manualmente a versão do RouterOS a ser instalada
- Suporte completo a todas as arquiteturas disponíveis para dispositivos Mikrotik:
  - arm, arm64/aarch64, mipsbe, mmips, mipsle, ppc, powerpc, tile, x86, smips, e500v2
  - Detecção automática de novas arquiteturas para cada versão
- Baixa os arquivos de atualização para todas as arquiteturas suportadas
- Detecta a arquitetura de cada equipamento Mikrotik com alta precisão
- Transfere o arquivo de atualização correto via SCP
- Configura o equipamento para atualização automática com dois reboots sequenciais
- Implementa o upgrade da routerboard entre os reboots
- Gera logs detalhados de todas as operações
- Usa as mesmas credenciais para todos os equipamentos
- Suporta portas SSH personalizadas

## Pré-requisitos

- Sistema Linux
- Bash (versão 4 ou superior)
- Pacotes instalados:
  - `sshpass` (para autenticação SSH com senha)
  - `curl` (para consultar versões e baixar arquivos)
  - `scp` (para transferência de arquivos)
- Acesso SSH aos equipamentos Mikrotik
- Credenciais de acesso com permissões administrativas
- Conexão com a internet para baixar os arquivos de atualização

## Instalação

1. Clone ou baixe este repositório:

```bash
git clone https://github.com/dvhoisel/atualizar-mikrotik.git
cd atualizar_mikrotik
```

2. Torne o script executável:

```bash
chmod +x atualizar_mikrotik.sh
```

3. Instale as dependências necessárias:

```bash
# Para sistemas baseados em Debian/Ubuntu
sudo apt-get install sshpass curl

# Para sistemas baseados em Red Hat/CentOS
sudo yum install sshpass curl

# Para sistemas baseados em Fedora
sudo dnf install sshpass curl
```

## Configuração

1. Edite o arquivo `equipamentos.txt` e adicione seus equipamentos Mikrotik no formato:

```
IP|PORTA_SSH
```

Onde:
- `PORTA_SSH` é opcional (padrão: 22)

Por exemplo:
```
192.168.1.1|22
10.0.0.1|2222
10.0.0.2      # Porta padrão (22) será usada
```

## Uso

Execute o script especificando a data e hora para a atualização, além das credenciais de acesso:

```bash
./atualizar_mikrotik.sh -d MM/DD/AAAA -h HH:MM:SS -u USUARIO -s SENHA
```

### Opções disponíveis:

- `-a, --arquivo ARQUIVO`: Especifica o arquivo com a lista de equipamentos (padrão: `equipamentos.txt`)
- `-d, --data DATA`: Define a data para a atualização (formato: MM/DD/AAAA)
- `-h, --hora HORA`: Define a hora para a atualização (formato: HH:MM:SS)
- `-u, --usuario USUARIO`: Define o usuário para autenticação SSH (padrão: `admin`)
- `-s, --senha SENHA`: Define a senha para autenticação SSH (padrão: `senha`)
- `-v, --versao VERSAO`: Define manualmente a versão do RouterOS a ser instalada (ex: 7.13.5)
- `--help`: Exibe a mensagem de ajuda

### Exemplos:

```bash
# Agenda atualização para 31/12/2023 às 23:30:00 com credenciais padrão
./atualizar_mikrotik.sh -d 12/31/2023 -h 23:30:00

# Agenda atualização com credenciais personalizadas
./atualizar_mikrotik.sh -d 12/31/2023 -h 23:30:00 -u meuusuario -s minhasenha

# Agenda atualização para uma versão específica do RouterOS
./atualizar_mikrotik.sh -d 12/31/2023 -h 23:30:00 -v 7.13.5

# Usa um arquivo diferente para a lista de equipamentos
./atualizar_mikrotik.sh -d 12/31/2023 -h 23:30:00 -u admin -s senha123 -a meus_equipamentos.txt
```

## Como funciona

O script realiza as seguintes operações:

1. **Verificação de versão**:
   - Se não for especificada manualmente, tenta determinar a versão mais recente do RouterOS usando:
     - Página oficial de changelogs da MikroTik (https://mikrotik.com/download/changelogs)
     - Página de download do RouterOS
     - Verificação de existência de versões conhecidas no servidor
     - Versão de fallback como último recurso
   
2. **Download dos arquivos**:
   - Verifica quais arquiteturas estão disponíveis para a versão específica
   - Baixa apenas os arquivos de atualização para arquiteturas disponíveis
   - Verifica a integridade dos arquivos baixados
   - Pula downloads se os arquivos já existirem localmente e estiverem íntegros

3. **Para cada equipamento**:
   - Conecta usando as credenciais padrão e a porta especificada
   - Detecta a arquitetura do RouterOS instalado com sistema avançado de mapeamento
   - Utiliza múltiplos métodos de detecção para garantir compatibilidade com todas as variantes
   - Transfere o arquivo de atualização correspondente via SCP
   - Verifica se o arquivo foi transferido corretamente
   
4. **Configuração dos agendamentos**:
   - Configura um primeiro reboot na hora especificada
   - Configura o agendamento para upgrade da routerboard na inicialização
   - Configura um segundo reboot 5 minutos após o primeiro
   - O processo completo é:
     1. Primeiro reboot -> Instala o RouterOS
     2. Executar o upgrade da routerboard (entre os reboots)
     3. Segundo reboot -> Finaliza a atualização

## Estrutura de diretórios

```
/
├── atualizar_mikrotik.sh     # Script principal
├── equipamentos.txt          # Lista de equipamentos
├── README.md                 # Este arquivo
└── downloads/                # Diretório para armazenar os arquivos baixados
    └── X.XX/                 # Subdiretórios por versão (ex: 7.10)
        ├── routeros-arm-X.XX.npk
        ├── routeros-arm64-X.XX.npk
        ├── routeros-mipsbe-X.XX.npk
        └── ...
```

## Logs

O script gera automaticamente um arquivo de log com o nome no formato:
```
atualizar_mikrotik_AAAAMMDD_HHMMSS.log
```

Este arquivo contém informações detalhadas sobre cada operação realizada, incluindo:
- Versão do RouterOS detectada ou especificada
- Arquivos baixados
- Arquitetura de cada equipamento
- Transferências de arquivos
- Configurações aplicadas
- Sucessos e falhas

## Solução de problemas

Se encontrar problemas ao executar o script:

1. **Problema de detecção de versão**:
   - Use a opção `-v` para especificar manualmente a versão do RouterOS 
   - Exemplo: `-v 7.13.5`
   - Verifique sua conexão com a internet e acesso aos sites da MikroTik
   - O script tentará automaticamente várias abordagens para detectar a versão
   - Consulte os logs para ver qual método foi usado para detectar a versão

2. **Problema de detecção de arquitetura**:
   - O script agora possui sistema avançado de detecção de arquiteturas
   - Caso a arquitetura não seja reconhecida automaticamente, o script tentará verificar quais arquivos estão disponíveis
   - Verifique os logs para mais detalhes sobre a detecção de arquitetura
   - O sistema de fallback tentará encontrar automaticamente a arquitetura correta

3. **Outros problemas comuns**:
   - Verifique as permissões do script (deve ser executável)
   - Confirme se todos os pacotes necessários estão instalados
   - Verifique se as credenciais SSH estão corretas
   - Confirme se os equipamentos Mikrotik estão acessíveis via SSH nas portas especificadas
   - Verifique se há conectividade com o site da Mikrotik para baixar os arquivos
   - Consulte o arquivo de log para mensagens de erro detalhadas

## Segurança

**Atenção**: Este script usa senhas em texto claro. Recomendações:

1. Evite armazenar senhas sensíveis no histórico do shell
2. Considere usar chaves SSH em vez de senhas para maior segurança
3. Execute o script apenas em ambientes seguros e controlados

## Contribuições

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests com melhorias.

## Licença

Este projeto é distribuído sob a licença GPL 3.0. Veja o arquivo LICENSE para mais detalhes. 
