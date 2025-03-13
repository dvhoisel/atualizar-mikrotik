#!/bin/bash

# -------------------------------------------------------
# Script para atualização automática de equipamentos Mikrotik
# Autor: Daniel Hoisel, com auxilio de IA
# -------------------------------------------------------

# Cores para saída do terminal
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[0;33m'
AZUL='\033[0;34m'
SEM_COR='\033[0m'

# Variáveis globais
ARQUIVO_LOG="atualizar_mikrotik_$(date +%Y%m%d_%H%M%S).log"
ARQUIVO_EQUIPAMENTOS="equipamentos.txt"
DATA_ATUALIZACAO=""
HORA_ATUALIZACAO=""
DIR_DOWNLOADS="./downloads"
VERSAO_MAIS_RECENTE=""
MIKROTIK_URL="https://download.mikrotik.com/routeros"
MIKROTIK_CHANGELOG_URL="https://mikrotik.com/download/changelogs"
ARQUITETURAS=("arm" "arm64" "mipsbe" "mmips" "ppc" "tile" "smips")

# Credenciais padrão para todos os equipamentos
USUARIO_PADRAO="admin"
SENHA_PADRAO="admin"
PORTA_PADRAO="22"

# Função para exibir mensagens de ajuda
mostrar_ajuda() {
    echo "Uso: $0 [opções]"
    echo
    echo "Este script verifica a última versão disponível do RouterOS, baixa os arquivos"
    echo "necessários e configura os equipamentos Mikrotik para atualização programada."
    echo
    echo "Opções:"
    echo "  -a, --arquivo ARQUIVO   Especifica o arquivo com a lista de equipamentos"
    echo "                         (Padrão: equipamentos.txt)"
    echo "  -d, --data DATA         Define a data para a atualização (formato: MM/DD/AAAA)"
    echo "  -h, --hora HORA         Define a hora para a atualização (formato: HH:MM:SS)"
    echo "  -u, --usuario USUARIO   Define o usuário para autenticação SSH (Padrão: admin)"
    echo "  -s, --senha SENHA       Define a senha para autenticação SSH"
    echo "  -v, --versao VERSAO     Define manualmente a versão do RouterOS (ex: 7.14)"
    echo "  --help                  Exibe esta mensagem de ajuda"
    echo
    echo "Exemplo:"
    echo "  $0 -d 12/31/2023 -h 23:30:00 -u admin -s minhasenha"
    echo "  $0 -d 12/31/2023 -h 23:30:00 -v 7.18.2"
    exit 0      
}

# Função para registrar mensagens no log
registrar_log() {
    local nivel=$1
    local mensagem=$2
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$nivel] $mensagem" | tee -a "$ARQUIVO_LOG"
}

# Função para verificar se a data é válida
validar_data() {
    local data=$1
    date -d "$data" > /dev/null 2>&1
    return $?
}

# Função para verificar se a hora é válida
validar_hora() {
    local hora=$1
    [[ $hora =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$ ]]
    return $?
}

# Função para verificar se a versão é válida
validar_versao() {
    local versao=$1
    [[ $versao =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
    return $?
}

# Função para verificar a versão mais recente do RouterOS
verificar_versao_recente() {
    registrar_log "INFO" "Verificando a versão mais recente do RouterOS..."
    
    # Cria diretório de downloads se não existir
    if [ ! -d "$DIR_DOWNLOADS" ]; then
        mkdir -p "$DIR_DOWNLOADS"
    fi
    
    # Se a versão já foi definida manualmente, use-a
    if [ ! -z "$VERSAO_MAIS_RECENTE" ]; then
        registrar_log "INFO" "Usando versão definida manualmente: $VERSAO_MAIS_RECENTE"
        return 0
    fi
    
    # Tenta obter a versão mais recente com diferentes métodos
    
    # Método 0: Consultar a página de changelogs da MikroTik
    registrar_log "INFO" "Tentando obter a versão a partir da página de changelogs da MikroTik..."
    local pagina_changelog=$(curl -s --max-time 15 "$MIKROTIK_CHANGELOG_URL")
    if [ ! -z "$pagina_changelog" ]; then
        # Extrai a seção que contém as versões estáveis
        local stable_section=$(echo "$pagina_changelog" | sed -n '/Stable release tree/,/Testing release tree/p')
        
        if [ ! -z "$stable_section" ]; then
            # Procura por padrões de versão no formato 7.xy ou 7.xy.z
            # Muitas vezes, elas aparecem em formato de link ou entre asteriscos
            local versoes_encontradas=$(echo "$stable_section" | grep -o -E '[^0-9][7][.][0-9]+[.][0-9]+' | sed 's/^[^0-9]//' || echo "")
            
            # Se não encontrou no formato acima, tenta outro formato (7.xy sem subversão)
            if [ -z "$versoes_encontradas" ]; then
                versoes_encontradas=$(echo "$stable_section" | grep -o -E '[^0-9][7][.][0-9]+' | sed 's/^[^0-9]//' || echo "")
            fi
            
            # Ordena as versões e pega a mais recente (última na ordenação por versão)
            if [ ! -z "$versoes_encontradas" ]; then
                VERSAO_MAIS_RECENTE=$(echo "$versoes_encontradas" | sort -V | tail -1)
                registrar_log "INFO" "Versão mais recente obtida da página de changelogs: $VERSAO_MAIS_RECENTE"
                return 0
            fi
        fi
    fi
    
    # Se o método anterior falhou, tenta outros métodos
    registrar_log "INFO" "Não foi possível obter a versão da página de changelogs, tentando métodos alternativos..."
    
    # Método 1: Verificar diretamente a página de releases
    registrar_log "INFO" "Tentando obter a versão a partir da página principal..."
    local pagina_principal=$(curl -s --max-time 10 "$MIKROTIK_URL/")
    local versoes=$(echo "$pagina_principal" | grep -oP '>\K[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V)
    VERSAO_MAIS_RECENTE=$(echo "$versoes" | tail -1)
    
        
    # Se ainda não encontrou, usa uma versão recente conhecida como fallback
    if [ -z "$VERSAO_MAIS_RECENTE" ]; then
        VERSAO_MAIS_RECENTE="7.13.5"  # Versão padrão de fallback
        registrar_log "AVISO" "Não foi possível determinar automaticamente a versão mais recente. Usando versão de fallback: $VERSAO_MAIS_RECENTE"
    else
        registrar_log "INFO" "Versão mais recente do RouterOS: $VERSAO_MAIS_RECENTE"
    fi
    
    return 0        
}

# Função para baixar os arquivos para todas as arquiteturas
baixar_arquivos() {
    local versao=$1
    registrar_log "INFO" "Verificando arquivos para a versão $versao..."
    
    # Cria subdiretório para a versão
    local versao_dir="$DIR_DOWNLOADS/$versao"
    if [ ! -d "$versao_dir" ]; then
        mkdir -p "$versao_dir"
    fi
    
    # Verifica se já existem arquivos íntegros para esta versão
    local arquivos_existentes=()
    local arquivos_validos=0
    
    # Procura por arquivos existentes e verifica integridade
    for arq in "${ARQUITETURAS[@]}"; do
        local arquivo="routeros-$versao-$arq.npk"
        local caminho_arquivo="$versao_dir/$arquivo"
        
        if [ -f "$caminho_arquivo" ]; then
            local tamanho=$(stat -c%s "$caminho_arquivo" 2>/dev/null || echo "0")
            if [ "$tamanho" -gt 1000 ]; then
                registrar_log "INFO" "Arquivo $arquivo já existe e parece íntegro (tamanho: $tamanho bytes)"
                arquivos_existentes+=("$arq")
                ((arquivos_validos++))
            else
                registrar_log "AVISO" "Arquivo $arquivo existe mas parece corrompido (tamanho: $tamanho bytes). Será baixado novamente."
                rm "$caminho_arquivo"
            fi
        fi
    done
    
    # Se temos pelo menos 5 arquivos válidos para diferentes arquiteturas, podemos pular o download
    if [ $arquivos_validos -ge 5 ]; then
        registrar_log "INFO" "Encontrados $arquivos_validos arquivos válidos localmente. Pulando verificação online."
        registrar_log "INFO" "Arquiteturas disponíveis localmente: ${arquivos_existentes[*]}"
        return 0
    fi
    
    registrar_log "INFO" "Baixando arquivos para a versão $versao..."
    
    # Ajuste na URL para lidar com o formato específico da MikroTik para downloads
    # A URL correta é: https://download.mikrotik.com/routeros/{versao}/routeros-{versao}-{arch}.npk
    local base_url="$MIKROTIK_URL/$versao"
    
    # Verifica se a versão é separada por pontos (formato: 7.x ou 7.x.y)
    if [[ "$versao" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        # Versão principal (ex: 7 para 7.18.2)
        local versao_principal=${versao%%.*}
        registrar_log "INFO" "Versão principal: $versao_principal"
    else
        registrar_log "ERRO" "Formato de versão inválido: $versao"
        return 1
    fi
    
    # Verifica inicialmente quais arquiteturas estão disponíveis para esta versão
    registrar_log "INFO" "Verificando quais arquiteturas estão disponíveis para a versão $versao..."
    
    # Tenta listar o diretório da versão para ver quais arquivos estão disponíveis
    local pagina_versao=$(curl -s --max-time 15 -L "$base_url/")
    local arquivos_encontrados=0
    
    if [ ! -z "$pagina_versao" ]; then
        registrar_log "INFO" "Obteve informações do diretório da versão. Tamanho: $(echo "$pagina_versao" | wc -c) bytes"
        
        for arq in "${ARQUITETURAS[@]}"; do
            # O formato correto é routeros-VERSAO-ARQUITETURA.npk
            local padrao="routeros-$versao-$arq.npk"
            
            # Verifica se o arquivo está listado na página
            if echo "$pagina_versao" | grep -q "$padrao"; then
                registrar_log "INFO" "Arquitetura $arq disponível para versão $versao"
                arquivos_existentes+=("$arq")
                ((arquivos_encontrados++))
            else
                # Tenta verificar diretamente se o arquivo existe
                local check_url="$base_url/$padrao"
                registrar_log "INFO" "Verificando existência de $check_url"
                local status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -L "$check_url")
                
                if [ "$status_code" = "200" ]; then
                    registrar_log "INFO" "Arquitetura $arq disponível para versão $versao (verificação direta)"
                    arquivos_existentes+=("$arq")
                    ((arquivos_encontrados++))
                else
                    registrar_log "INFO" "Arquitetura $arq não disponível para versão $versao (status: $status_code)"
                fi
            fi
        done
    else
        registrar_log "AVISO" "Não foi possível obter a listagem do diretório da versão $versao"
    fi
    
    # Se não encontrou arquivos listados, tenta URLs alternativas
    if [ $arquivos_encontrados -eq 0 ]; then
        registrar_log "AVISO" "Não foi possível determinar quais arquiteturas estão disponíveis. Tentar URL alternativa."
        
        # URL alternativa baseada no formato histórico conhecido
        local alt_url="https://download2.mikrotik.com/routeros/$versao"
        registrar_log "INFO" "Tentando URL alternativa: $alt_url"
        
        local pagina_versao_alt=$(curl -s --max-time 15 -L "$alt_url/")
        
        if [ ! -z "$pagina_versao_alt" ]; then
            registrar_log "INFO" "Obteve informações do diretório alternativo. Tamanho: $(echo "$pagina_versao_alt" | wc -c) bytes"
            
            for arq in "${ARQUITETURAS[@]}"; do
                # O formato correto é routeros-VERSAO-ARQUITETURA.npk
                local padrao="routeros-$versao-$arq.npk"
                
                if echo "$pagina_versao_alt" | grep -q "$padrao"; then
                    registrar_log "INFO" "Arquitetura $arq disponível para versão $versao (URL alternativa)"
                    arquivos_existentes+=("$arq")
                    ((arquivos_encontrados++))
                    base_url="$alt_url"  # Use a URL alternativa para os downloads
                else
                    # Tenta verificar diretamente se o arquivo existe na URL alternativa
                    local check_url="$alt_url/$padrao"
                    local status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -L "$check_url")
                    
                    if [ "$status_code" = "200" ]; then
                        registrar_log "INFO" "Arquitetura $arq disponível para versão $versao (verificação direta na URL alternativa)"
                        arquivos_existentes+=("$arq")
                        ((arquivos_encontrados++))
                        base_url="$alt_url"  # Use a URL alternativa para os downloads
                    fi
                fi
            done
        fi
    fi
    
    # Se ainda não encontrou nada, tenta uma terceira estrutura de URL
    if [ $arquivos_encontrados -eq 0 ]; then
        local third_url="https://upgrade.mikrotik.com/routeros/$versao"
        registrar_log "INFO" "Tentando terceira URL alternativa: $third_url"
        
        for arq in "${ARQUITETURAS[@]}"; do
            # O formato correto é routeros-VERSAO-ARQUITETURA.npk
            local padrao="routeros-$versao-$arq.npk"
            local check_url="$third_url/$padrao"
            local status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -L "$check_url")
            
            if [ "$status_code" = "200" ]; then
                registrar_log "INFO" "Arquitetura $arq disponível para versão $versao (verificação na terceira URL)"
                arquivos_existentes+=("$arq")
                ((arquivos_encontrados++))
                base_url="$third_url"  # Use a terceira URL para os downloads
            fi
        done
    fi
    
    # Se ainda não encontrou nada, verifica se pelo menos a arquitetura x86 está disponível
    if [ $arquivos_encontrados -eq 0 ]; then
        registrar_log "AVISO" "Tentando uma abordagem mais direta para encontrar os arquivos..."
        
        # Lista de possíveis URLs para download
        local possiveis_urls=(
            "https://download.mikrotik.com/routeros/$versao"
            "https://download2.mikrotik.com/routeros/$versao"
            "https://upgrade.mikrotik.com/routeros/$versao"
            "https://mt.lv/routeros$versao"
        )
        
        # Tenta baixar diretamente o arquivo para x86, que é comum em todas as versões
        for url_base in "${possiveis_urls[@]}"; do
            # O formato correto é routeros-VERSAO-ARQUITETURA.npk
            local arquivo_x86="routeros-$versao-x86.npk"
            local check_url="$url_base/$arquivo_x86"
            
            registrar_log "INFO" "Verificando URL: $check_url"
            
            # Use curl com a opção -I (HEAD request) para verificar se o arquivo existe
            local headers=$(curl -s -I --max-time 5 -L "$check_url")
            
            if echo "$headers" | grep -q "200 OK"; then
                registrar_log "INFO" "Encontrou URL válida: $url_base"
                arquivos_existentes=("x86") # Começa com x86 e adiciona outras se existirem
                base_url="$url_base"
                
                # Verifica outras arquiteturas comuns
                for arq in "arm" "arm64" "mipsbe" "tile"; do
                    # O formato correto é routeros-VERSAO-ARQUITETURA.npk
                    local outro_arquivo="routeros-$versao-$arq.npk"
                    local outro_url="$url_base/$outro_arquivo"
                    
                    if curl -s -I --max-time 3 -L "$outro_url" | grep -q "200 OK"; then
                        arquivos_existentes+=("$arq")
                        registrar_log "INFO" "Arquitetura adicional encontrada: $arq"
                    fi
                done
                
                arquivos_encontrados=${#arquivos_existentes[@]}
                break
            fi
        done
    fi
    
    # Se ainda não encontrou nada, usa uma lista reduzida de arquiteturas comuns
    if [ $arquivos_encontrados -eq 0 ]; then
        registrar_log "AVISO" "Não foi possível determinar quais arquiteturas estão disponíveis usando URLs alternativas. Tentando arquiteturas comuns."
        # Usa apenas as arquiteturas mais comuns para tentar o download direto
        arquivos_existentes=("arm" "arm64" "mipsbe" "mmips" "tile" "x86")
    fi
    
    registrar_log "INFO" "Tentando baixar ${#arquivos_existentes[@]} arquiteturas: ${arquivos_existentes[*]}"
    registrar_log "INFO" "URL base para download: $base_url"
    
    # Contador para arquivos baixados com sucesso
    local downloads_sucesso=0
    
    # Baixa os arquivos para cada arquitetura disponível
    for arq in "${arquivos_existentes[@]}"; do
        # O formato correto é routeros-VERSAO-ARQUITETURA.npk
        local arquivo="routeros-$versao-$arq.npk"
        local caminho_arquivo="$versao_dir/$arquivo"
        local url="$base_url/$arquivo"
        
        # Verifica se o arquivo já existe e é válido
        if [ -f "$caminho_arquivo" ]; then
            registrar_log "INFO" "Arquivo $arquivo já existe. Verificando integridade..."
            
            # Verifica o tamanho do arquivo
            local tamanho_arquivo=$(stat -c%s "$caminho_arquivo" 2>/dev/null || echo "0")
            if [ "$tamanho_arquivo" -lt 1000 ]; then
                registrar_log "AVISO" "Arquivo $arquivo parece corrompido ou vazio (tamanho: $tamanho_arquivo bytes). Baixando novamente."
                rm "$caminho_arquivo"
            else
                registrar_log "INFO" "Arquivo $arquivo parece íntegro (tamanho: $tamanho_arquivo bytes). Pulando download."
                ((downloads_sucesso++))
                continue
            fi
        fi
        
        registrar_log "INFO" "Baixando $arquivo de $url..."
        
        # Tenta baixar com mais informações para debug
        local download_output_file=$(mktemp)
        local curl_exit_code=0
        
        # Usa a opção -L para seguir redirecionamentos e -v para saída detalhada
        curl -L -v -o "$caminho_arquivo" --max-time 60 "$url" > "$download_output_file" 2>&1 || curl_exit_code=$?
        
        # Exibe informações do download para debug
        registrar_log "INFO" "Saída do curl para $arquivo (código: $curl_exit_code):"
        registrar_log "DEBUG" "$(head -n 20 "$download_output_file" | grep -v "Authorization:")"
        
        # Limpa o arquivo temporário
        rm "$download_output_file"
        
        # Verifica se o download foi bem-sucedido
        if [ $curl_exit_code -eq 0 ] && [ -f "$caminho_arquivo" ]; then
            # Verifica o conteúdo do arquivo
            if [ -s "$caminho_arquivo" ]; then
                local tamanho_arquivo=$(stat -c%s "$caminho_arquivo" 2>/dev/null || echo "0")
                local tipo_arquivo=$(file -b "$caminho_arquivo")
                
                # Verifica se o arquivo é muito pequeno ou parece um HTML em vez de um binário
                if [ "$tamanho_arquivo" -lt 1000 ] || [[ "$tipo_arquivo" == *"HTML"* ]] || [[ "$tipo_arquivo" == *"text"* ]]; then
                    registrar_log "ERRO" "Arquivo $arquivo baixado não parece ser um NPK válido (tamanho: $tamanho_arquivo bytes, tipo: $tipo_arquivo)"
                    
                    # Exibe os primeiros bytes do arquivo para debug
                    registrar_log "DEBUG" "Primeiros bytes: $(head -c 100 "$caminho_arquivo" | xxd -p)"
                    
                    rm "$caminho_arquivo"
                else
                    registrar_log "SUCESSO" "Download de $arquivo concluído (tamanho: $tamanho_arquivo bytes)"
                    ((downloads_sucesso++))
                fi
            else
                registrar_log "ERRO" "Arquivo $arquivo baixado está vazio"
                rm "$caminho_arquivo"
            fi
        else
            registrar_log "ERRO" "Falha ao baixar $arquivo (código: $curl_exit_code)"
            # Remove arquivo possivelmente corrompido
            [ -f "$caminho_arquivo" ] && rm "$caminho_arquivo"
        fi
    done
    
    # Verifica se pelo menos um arquivo foi baixado com sucesso
    local arquivos_baixados=$(find "$versao_dir" -type f -name "*.npk" | wc -l)
    if [ "$arquivos_baixados" -eq 0 ]; then
        registrar_log "ERRO" "Nenhum arquivo foi baixado com sucesso para a versão $versao!"
        
        # Informações adicionais para ajudar no diagnóstico
        registrar_log "INFO" "Por favor, verifique manualmente se os arquivos estão disponíveis no site da MikroTik:"
        registrar_log "INFO" "https://download.mikrotik.com/routeros/$versao/"
        registrar_log "INFO" "https://upgrade.mikrotik.com/routeros/$versao/"
        registrar_log "INFO" "ou teste outra versão usando a opção -v do script"
        
        return 1
    else
        registrar_log "INFO" "Total de arquivos baixados para versão $versao: $arquivos_baixados"
        return 0
    fi
}

# Função para configurar a atualização no dispositivo Mikrotik
configurar_atualizacao() {
    local ip=$1
    local porta=$2
    local data_hora="${DATA_ATUALIZACAO} ${HORA_ATUALIZACAO}"
    local versao=$VERSAO_MAIS_RECENTE
    
    # Converte data para o formato do Mikrotik (MMM/DD/AAAA)
    local mes_dia_ano=$(date -d "${DATA_ATUALIZACAO}" "+%b/%d/%Y")
    
    registrar_log "INFO" "Configurando atualização para equipamento $ip:$porta..."
    
    # Opções SSH para porta personalizada
    local ssh_opts="-p $porta -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    
    # 1. Detectar a arquitetura do dispositivo
    registrar_log "INFO" "Detectando arquitetura do equipamento $ip:$porta..."
    local arquitetura=$(sshpass -p "$SENHA_PADRAO" ssh $ssh_opts "$USUARIO_PADRAO@$ip" "/system resource print" | grep -i "architecture-name" | awk '{print $2}')
    
    if [ -z "$arquitetura" ]; then
        registrar_log "ERRO" "Não foi possível detectar a arquitetura do equipamento $ip:$porta"
        return 1
    fi
    
    registrar_log "INFO" "Arquitetura detectada: $arquitetura"
    
    # Mapear a arquitetura retornada para o formato do nome do arquivo
    local arq_mapeada=""
    
    case "$arquitetura" in
        *"arm"*|*"ARM"*)
            if [[ "$arquitetura" == *"64"* || "$arquitetura" == *"aarch64"* ]]; then
                arq_mapeada="arm64"
            else
                arq_mapeada="arm"
            fi
            ;;
        *"mips"*|*"MIPS"*)
            if [[ "$arquitetura" == *"be"* || "$arquitetura" == *"BE"* ]]; then
                arq_mapeada="mipsbe"
            elif [[ "$arquitetura" == *"smips"* || "$arquitetura" == *"SMIPS"* ]]; then
                arq_mapeada="smips"
            elif [[ "$arquitetura" == *"le"* || "$arquitetura" == *"LE"* ]]; then
                arq_mapeada="mipsle"
            else
                arq_mapeada="mmips"
            fi
            ;;
        *"powerpc"*|*"PPC"*|*"ppc"*)
            if [[ "$arquitetura" == *"e500v2"* ]]; then
                arq_mapeada="e500v2"
            elif [[ "$arquitetura" == *"ppc"* ]]; then
                arq_mapeada="ppc"
            else
                arq_mapeada="powerpc"
            fi
            ;;
        *"tile"*|*"TILE"*)
            arq_mapeada="tile"
            ;;
        *"x86"*|*"X86"*|*"86"*)
            arq_mapeada="x86"
            ;;
        *)
            # Tenta uma abordagem alternativa - verifica arquivos disponíveis para a versão
            registrar_log "AVISO" "Arquitetura não reconhecida diretamente: $arquitetura. Tentando determinar pelo mapeamento de arquivos..."
            
            # Cria um array de possíveis mapeamentos baseados em padrões comuns
            local possiveis_mapeamentos=()
            
            # Adiciona mapeamentos baseados em padrões no nome da arquitetura
            if [[ "$arquitetura" == *"arm"* ]]; then
                if [[ "$arquitetura" == *"64"* ]]; then
                    possiveis_mapeamentos+=("arm64" "aarch64")
                else
                    possiveis_mapeamentos+=("arm")
                fi
            elif [[ "$arquitetura" == *"mips"* ]]; then
                if [[ "$arquitetura" == *"be"* ]]; then
                    possiveis_mapeamentos+=("mipsbe")
                elif [[ "$arquitetura" == *"le"* ]]; then
                    possiveis_mapeamentos+=("mipsle")
                else
                    possiveis_mapeamentos+=("mmips" "smips")
                fi
            elif [[ "$arquitetura" == *"power"* || "$arquitetura" == *"ppc"* ]]; then
                possiveis_mapeamentos+=("powerpc" "ppc" "e500v2")
            else
                # Adiciona todas as arquiteturas como possibilidade
                possiveis_mapeamentos+=("${ARQUITETURAS[@]}")
            fi
            
            # Verifica qual arquivo existe para esta versão
            for arq in "${possiveis_mapeamentos[@]}"; do
                # O formato correto é routeros-VERSAO-ARQUITETURA.npk
                local caminho_teste="$DIR_DOWNLOADS/$versao/routeros-$versao-$arq.npk"
                if [ -f "$caminho_teste" ]; then
                    arq_mapeada="$arq"
                    registrar_log "INFO" "Encontrado arquivo compatível para a arquitetura: $arq"
                    break
                fi
            done
            
            # Se ainda não encontrou, usa uma abordagem diferente
            if [ -z "$arq_mapeada" ]; then
                registrar_log "ERRO" "Não foi possível mapear a arquitetura: $arquitetura"
                return 1
            fi
            ;;
    esac
    
    # 2. Enviar o arquivo correto via SCP
    # O formato correto é routeros-VERSAO-ARQUITETURA.npk
    local arquivo="routeros-${versao}-${arq_mapeada}.npk"
    local caminho_arquivo="$DIR_DOWNLOADS/$versao/$arquivo"
    
    if [ ! -f "$caminho_arquivo" ]; then
        registrar_log "ERRO" "Arquivo $arquivo não encontrado localmente"
        return 1
    fi
    
    # Remover arquivos .npk anteriores do Mikrotik
    registrar_log "INFO" "Removendo arquivos .npk existentes no equipamento $ip:$porta..."
    sshpass -p "$SENHA_PADRAO" ssh $ssh_opts "$USUARIO_PADRAO@$ip" << EOF
    # Lista todos os arquivos .npk e os remove
    /file print where name ~ ".npk"
    /file remove [find where name ~ ".npk"]
    # Verifica se a remoção foi bem-sucedida
    /log info "Arquivos .npk removidos"
EOF
    
    registrar_log "INFO" "Enviando arquivo $arquivo para $ip:$porta..."
    # Enviar o arquivo com seu nome original, sem renomear
    if ! sshpass -p "$SENHA_PADRAO" scp -P $porta -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$caminho_arquivo" "$USUARIO_PADRAO@$ip:/$arquivo"; then
        registrar_log "ERRO" "Falha ao enviar arquivo para $ip:$porta"
        return 1
    fi
    
    # 3. Verificar se o arquivo foi copiado corretamente
    registrar_log "INFO" "Verificando se o arquivo foi copiado corretamente..."
    local verificacao=$(sshpass -p "$SENHA_PADRAO" ssh $ssh_opts "$USUARIO_PADRAO@$ip" "ls -la /$arquivo" 2>/dev/null)
    
    if [ -z "$verificacao" ]; then
        registrar_log "ERRO" "Arquivo não encontrado no equipamento $ip:$porta após transferência"
        return 1
    fi
    
    # 4. Configurar os agendamentos para reboot com o upgrade da routerboard entre eles
    registrar_log "INFO" "Configurando agendamentos para atualização e reboot em $ip:$porta..."
    
    # Calcula o horário para o segundo reboot (5 minutos após o primeiro)
    # Desmembra a hora em horas, minutos e segundos para calcular corretamente
    IFS=: read hora minuto segundo <<< "$HORA_ATUALIZACAO"
    
    # Converte para minutos totais e adiciona 5
    minutos_totais=$(( 10#$hora * 60 + 10#$minuto ))
    minutos_totais=$(( minutos_totais + 5 ))
    
    # Calcula as novas horas e minutos
    nova_hora=$(( minutos_totais / 60 ))
    novo_minuto=$(( minutos_totais % 60 ))
    
    # Formata a nova hora no formato correto HH:MM:SS
    hora_segundo_reboot=$(printf "%02d:%02d:%02d" $nova_hora $novo_minuto $segundo)
    
    registrar_log "INFO" "Hora programada para o primeiro reboot: $HORA_ATUALIZACAO"
    registrar_log "INFO" "Hora programada para o segundo reboot: $hora_segundo_reboot"
    
    # Cria os comandos para serem executados no Mikrotik
    sshpass -p "$SENHA_PADRAO" ssh $ssh_opts "$USUARIO_PADRAO@$ip" << EOF
    # Remove agendamentos anteriores (se existirem)
    /system scheduler remove [find name="primeiro-reboot"];
    /system scheduler remove [find name="segundo-reboot"];
    /system scheduler remove [find name="atualizar-firmware"];
    
    # Cria o agendamento para o primeiro reboot
    /system scheduler add name="primeiro-reboot" start-date="$mes_dia_ano" start-time="$HORA_ATUALIZACAO" interval=0 on-event="/log info \"Iniciando processo de atualizacao\"; /system reboot;" policy=reboot,read,write,policy,test;
    
    # Cria o agendamento para o segundo reboot (5 minutos após o primeiro)
    /system scheduler add name="segundo-reboot" start-date="$mes_dia_ano" start-time="$hora_segundo_reboot" interval=0 on-event="/log info \"Iniciando segundo reboot para finalizar atualizacoes\"; /system scheduler disable atualizar-firmware; /system reboot;" policy=reboot,read,write,policy,test;
    
    # Cria o agendamento para atualização do firmware da routerboard
    /system scheduler add name="atualizar-firmware" start-time=startup interval=0 on-event="/log info \"Iniciando atualizacao do firmware da RouterBoard\"; /system routerboard upgrade; /log info \"Firmware da RouterBoard atualizado\";" policy=reboot,read,write,policy,test;
    
    # Exibe os agendamentos criados para verificação
    /log info "Agendamentos criados:";
    /system scheduler print;
EOF
    
    # Verifica se o comando SSH foi bem-sucedido
    if [ $? -eq 0 ]; then
        registrar_log "SUCESSO" "Atualização agendada com sucesso para $ip:$porta em $data_hora"
        return 0
    else
        registrar_log "ERRO" "Falha ao configurar atualização para $ip:$porta"
        return 1
    fi
}

# Função principal
main() {
    # Verificando parâmetros
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--arquivo)
                ARQUIVO_EQUIPAMENTOS="$2"
                shift 2
                ;;
            -d|--data)
                DATA_ATUALIZACAO="$2"
                shift 2
                ;;
            -h|--hora)
                HORA_ATUALIZACAO="$2"
                shift 2
                ;;
            -u|--usuario)
                USUARIO_PADRAO="$2"
                shift 2
                ;;
            -s|--senha)
                SENHA_PADRAO="$2"
                shift 2
                ;;
            -v|--versao)
                VERSAO_MAIS_RECENTE="$2"
                shift 2
                ;;
            --help)
                mostrar_ajuda
                ;;
            *)
                echo -e "${VERMELHO}Opção inválida: $1${SEM_COR}"
                mostrar_ajuda
                ;;
        esac
    done
    
    # Verifica se as dependências estão instaladas
    for cmd in sshpass curl scp file xxd; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${VERMELHO}ERRO: O comando '$cmd' não está instalado.${SEM_COR}"
            echo "Instale-o com 'sudo apt-get install $cmd' (Debian/Ubuntu) ou equivalente."
            exit 1
        fi
    done
    
    # Verifica se a data e hora foram informadas
    if [ -z "$DATA_ATUALIZACAO" ]; then
        echo -e "${VERMELHO}ERRO: A data de atualização deve ser informada${SEM_COR}"
        mostrar_ajuda
    fi
    
    if [ -z "$HORA_ATUALIZACAO" ]; then
        echo -e "${VERMELHO}ERRO: A hora de atualização deve ser informada${SEM_COR}"
        mostrar_ajuda
    fi
    
    # Valida a data e hora informadas
    if ! validar_data "$DATA_ATUALIZACAO"; then
        echo -e "${VERMELHO}ERRO: Data inválida. Use o formato MM/DD/AAAA${SEM_COR}"
        exit 1
    fi
    
    if ! validar_hora "$HORA_ATUALIZACAO"; then
        echo -e "${VERMELHO}ERRO: Hora inválida. Use o formato HH:MM:SS${SEM_COR}"
        exit 1
    fi
    
    # Valida a versão se fornecida manualmente
    if [ ! -z "$VERSAO_MAIS_RECENTE" ]; then
        if ! validar_versao "$VERSAO_MAIS_RECENTE"; then
            echo -e "${VERMELHO}ERRO: Versão inválida. Use o formato X.Y ou X.Y.Z (ex: 7.11 ou 7.13.5)${SEM_COR}"
            exit 1
        fi
    fi
    
    # Verifica se o arquivo de equipamentos existe
    if [ ! -f "$ARQUIVO_EQUIPAMENTOS" ]; then
        echo -e "${VERMELHO}ERRO: Arquivo de equipamentos '$ARQUIVO_EQUIPAMENTOS' não encontrado${SEM_COR}"
        exit 1
    fi
    
    # Inicializa o arquivo de log
    echo "# Log de execução - $(date '+%Y-%m-%d %H:%M:%S')" > "$ARQUIVO_LOG"
    registrar_log "INFO" "Iniciando processo de agendamento de atualizações"
    registrar_log "INFO" "Data programada: $DATA_ATUALIZACAO, Hora: $HORA_ATUALIZACAO"
    registrar_log "INFO" "Usando usuário padrão: $USUARIO_PADRAO"
    
    # Verifica a versão mais recente do RouterOS
    if ! verificar_versao_recente; then
        echo -e "${VERMELHO}ERRO: Não foi possível determinar a versão do RouterOS${SEM_COR}"
        
        # Sugere algumas versões para o usuário escolher
        echo
        echo -e "${AMARELO}Por favor, especifique manualmente uma versão usando a opção -v${SEM_COR}"
        echo "Versões recentes conhecidas:"
        echo "  7.18.2, 7.18.1, 7.18, 7.17.2, 7.17.1, 7.17, 7.16.2, 7.16.1, 7.15.3, 7.14.3, 7.13.5"
        echo
        echo "Exemplo:"
        echo "  $0 -d $DATA_ATUALIZACAO -h $HORA_ATUALIZACAO -v 7.13.5"
        exit 1
    fi
    
    # Baixa os arquivos para todas as arquiteturas
    if ! baixar_arquivos "$VERSAO_MAIS_RECENTE"; then
        echo -e "${VERMELHO}ERRO: Falha ao baixar os arquivos para a versão $VERSAO_MAIS_RECENTE${SEM_COR}"
        echo
        echo -e "${AMARELO}Possíveis soluções:${SEM_COR}"
        echo "1. Verifique sua conexão com a internet"
        echo "2. Verifique se os arquivos estão disponíveis no site da MikroTik:"
        echo "   https://download.mikrotik.com/routeros/$VERSAO_MAIS_RECENTE/"
        echo "3. Tente especificar manualmente uma versão diferente com a opção -v"
        echo
        echo "Versões alternativas recomendadas:"
        echo "  7.13.5, 7.12.1, 7.11.2, 7.10.2, 7.9.2, 7.8, 7.7, 7.6"
        echo
        echo "Exemplo:"
        echo "  $0 -d $DATA_ATUALIZACAO -h $HORA_ATUALIZACAO -v 7.13.5"
        exit 1
    fi
    
    # Lista os arquivos baixados
    registrar_log "INFO" "Arquivos disponíveis para atualização:"
    find "$DIR_DOWNLOADS/$VERSAO_MAIS_RECENTE" -type f -name "*.npk" -exec basename {} \; | while read -r arquivo; do
        registrar_log "INFO" " - $arquivo"
    done
    
    # Contadores
    local total=0
    local sucesso=0
    local falha=0
    
    # Processa cada equipamento no arquivo
    while IFS="|" read -r ip porta || [[ -n "$ip" ]]; do
        # Ignora linhas em branco ou comentadas
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        
        # Remove espaços em branco
        ip=$(echo "$ip" | xargs)
        
        # Verifica se a porta foi especificada, senão usa a padrão
        if [ -z "$porta" ]; then
            porta="$PORTA_PADRAO"
        else
            porta=$(echo "$porta" | xargs)
        fi
        
        echo -e "${AMARELO}Configurando atualização para equipamento $ip:$porta...${SEM_COR}"
        
        # Configura a atualização
        if configurar_atualizacao "$ip" "$porta"; then
            echo -e "${VERDE}✓ Configuração concluída para $ip:$porta${SEM_COR}"
            ((sucesso++))
        else
            echo -e "${VERMELHO}✗ Falha na configuração para $ip:$porta${SEM_COR}"
            ((falha++))
        fi
        
        ((total++))
        echo
    done < "$ARQUIVO_EQUIPAMENTOS"
    
    # Exibe resumo
    echo -e "${VERDE}==== Resumo da execução ====${SEM_COR}"
    echo -e "Equipamentos processados: $total"
    echo -e "Configurações com ${VERDE}sucesso${SEM_COR}: $sucesso"
    echo -e "Configurações com ${VERMELHO}falha${SEM_COR}: $falha"
    echo -e "Arquivo de log: $ARQUIVO_LOG"
    echo -e "Versão do RouterOS para atualização: ${AZUL}$VERSAO_MAIS_RECENTE${SEM_COR}"
    
    # Exibe os arquivos baixados
    echo -e "${AZUL}Arquivos baixados:${SEM_COR}"
    find "$DIR_DOWNLOADS/$VERSAO_MAIS_RECENTE" -type f -name "*.npk" -exec ls -lh {} \; | while read -r linha; do
        echo -e " - $linha"
    done
    
    registrar_log "INFO" "Processo concluído. Sucesso: $sucesso, Falha: $falha, Total: $total"
}

# Executa o script
main "$@" 