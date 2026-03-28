#!/bin/sh
 
API_KEY="$GEMINI_API_KEY"
MODEL="gemini-flash-latest"

# selector de modelo

if [ "$1" = "-m" ]
then
	if [ "$2" = "pro" ]
	then
		MODEL="gemini-pro-latest"
	fi
fi

API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"

mkdir -p "$HOME/Documents/ConversacionesGemini/tmp"

HILO="$HOME/Documents/ConversacionesGemini/actual.md"
LOG="$HOME/Documents/ConversacionesGemini/iadime.log"
TMP="$HOME/Documents/ConversacionesGemini/tmp/tmp.json"
RESP="$HOME/Documents/ConversacionesGemini/tmp/ultima_resp.txt"
CTX="$HOME/Documents/ConversacionesGemini/tmp/iadime_ctx.json"

TMPDIR="$HOME/Documents/ConversacionesGemini/tmp/"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# init contexto si no existe
if [ ! -f "$CTX" ]
then
	echo "" > "$CTX"
else
	if ! grep -q '"role"' "$CTX"
	then
		echo "" > "$CTX"
	fi

fi

# init hilo si no existe
if [ ! -f "$HILO" ]
then
	echo "# Conversación Gemini" > "$HILO"
	echo "" >> "$HILO"
fi

TOTAL_TOKENS=0
DEBUG_MODE=0

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Sesion iniciada con el modelo $MODEL" >> "$LOG"

echo ""
echo "[ i a d i m e ] ($MODEL)"
echo "Escribe tu pregunta o usa los comandos [':leer'|':salir'|...|':ayuda']"
echo ""

while true
do
	echo "${GREEN}Tu:${RESET}"
	read PROMPT || break

	#Comandos
	case "$PROMPT" in
	":salir")
		break
	;;

	":reset")
		echo "" > "$CTX"
		echo "" > "$HILO"
		rm -f "$TMPDIR"/*
		echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Contexto reiniciado" >> "$LOG"
		echo "${CYAN}Contexto reiniciado${RESET}"
		continue
	;;

	":leer")
		if command -v mdv > /dev/null 2>&1
		then
			mdv "$HILO" | less -r
		else
			vim "$HILO"
		fi
		continue
	;;

    ":clear")
		clear
		continue
	;;

	":debug")
		if [ $DEBUG_MODE -eq 0 ]
		then
			DEBUG_MODE=1
			echo "${GREEN}[DEBUG]${RESET} Modo debug ${GREEN}ACTIVADO${RESET}"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Modo debug activado" >> "$LOG"
		else
			DEBUG_MODE=0
			echo "${YELLOW}[DEBUG]${RESET} Modo debug ${RED}DESACTIVADO${RESET}"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Modo debug desactivado" >> "$LOG"
		fi
		continue
	;;

	:export*)
		NAME=`echo "$PROMPT" | sed 's/^:export //'`

		if [ -z "$NAME" ] || [ "$NAME" = ":export" ]
		then
			NAME="Conversacion"
		fi

		EXPORT_HILO="$HOME/Documents/ConversacionesGemini/$NAME.md"
		EXPORTDIR="$HOME/Documents/ConversacionesGemini/${NAME}_tmp"

		mv "$HILO" "$EXPORT_HILO"
		sed -i.bak '1s/^.*$/# '"$NAME"'/' "$EXPORT_HILO"
		rm -f "$EXPORT_HILO.bak"
		mkdir -p "$EXPORTDIR"
		mv "$TMPDIR"* "$EXPORTDIR"

		echo "" > "$CTX"
		echo "# Conversación Gemini" > "$HILO"
		echo "" >> "$HILO"
		rm -f "$TMPDIR"/*
		TOTAL_TOKENS=0

		echo "${CYAN}Exportado como $NAME${RESET}"
		echo "${CYAN}Contexto reiniciado${RESET}"

		echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Conversacion exportada como $NAME" >> "$LOG"
		echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Contexto reiniciado" >> "$LOG"

		continue
	;;

	:import*)
		NAME=`echo "$PROMPT" | sed 's/^:import //'`

		if [ -z "$NAME" ]
		then
			echo "${RED}Debes indicar un nombre${RESET}"
			continue
		fi

		IMPORT_HILO="$HOME/Documents/ConversacionesGemini/$NAME.md"
		IMPORT_TMP="$HOME/Documents/ConversacionesGemini/${NAME}_tmp"

		echo "${CYAN}Importar '$NAME'? (s/n)${RESET}"
		read CONFIRM

		if [ "$CONFIRM" != "s" ]
		then
			echo "Cancelado"
			continue
		fi

		if [ ! -f "$IMPORT_HILO" ] || [ ! -d "$IMPORT_TMP" ]
		then
			echo "${RED}No existe${RESET}"
			continue
		fi

		rm -f "$TMPDIR"/*
		echo "" > "$CTX"

		cp "$IMPORT_HILO" "$HILO"
		cp "$IMPORT_TMP"/* "$TMPDIR"/ 2>/dev/null

		echo "${CYAN}Importado${RESET}"
		echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Importada conversacion $NAME" >> "$LOG"
		continue
	;;

	":list")
		echo "${CYAN}Conversaciones disponibles:${RESET}"
		ls "$HOME/Documents/ConversacionesGemini/" | grep '\.md'| sed 's/\.md$//'
		continue
	;;

	:model*)
		NEW_MODEL=`echo "$PROMPT" | sed 's/^:model //'`

		if [ "$NEW_MODEL" = "pro" ]
		then
			MODEL="gemini-pro-latest"
		else
			MODEL="gemini-flash-latest"
		fi

		API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"

		echo "${CYAN}Modelo cambiado a $MODEL${RESET}"
		echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Modelo cambiado a $MODEL" >> "$LOG"
		continue
	;;

	":ayuda")
		echo "${CYAN}Uso: '> iadime -m [pro|flash]' - Para usar el modelo flash o el pro de gemini en su ultima version${RESET}"
		echo "Escribe tu pregunta o usa los comandos:"
		echo "  ':leer'           - Leer la conversación actual"
		echo "  ':salir'          - Salir del programa"
		echo "  ':reset'          - Reiniciar contexto"
		echo "  ':clear'          - Limpiar pantalla"
		echo "  ':export TITULO'  - Exportar conversación"
		echo "  ':import TITULO'  - Importar conversación"
		echo "  ':list'           - Listar conversaciones"
		echo "  ':model pro/flash' - Cambiar modelo"
		echo "  ':debug'          - Alternar modo debug y validar petición"
		echo "  ':ayuda'          - Mostrar esta ayuda"
		continue
	;;

	:*)
		echo "${RED}Comando desconocido${RESET}"
		continue
	;;

	esac
	
	#Valida
	if [ -z "$PROMPT" ]
	then
		if [ $DEBUG_MODE -eq 1 ]
		then
			echo "${RED}[DEBUG] Pregunta vacía${RESET}"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Pregunta vacía rechazada" >> "$LOG"
		fi
		continue
	fi

	#CONSTRUIR PREGUNTA USUARIO
	echo '{"role":"user","parts":[{"text":"'"$PROMPT"'"}]}' > "$TMP.user"
	
	if [ $DEBUG_MODE -eq 1 ]
	then
		echo "${BLUE}[DEBUG] Validando pregunta...${RESET}"
		echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Pregunta enviada: $PROMPT" >> "$LOG"
	fi
	
	#limpia primera coma
	sed '1s/^,*//' "$CTX" > "$CTX.tmp" 2>> "$LOG"
	mv "$CTX.tmp" "$CTX"

	echo '{"contents":[' > "$TMP.req"
	FIRST=1
	
	if grep -q '"role"' "$CTX"
	then
		cat "$CTX" >> "$TMP.req"
		FIRST=0
	fi

	if [ $FIRST -eq 0 ]
	then
		echo "," >> "$TMP.req"
	fi

	cat "$TMP.user" >> "$TMP.req"
	echo ']}' >> "$TMP.req"
	
	if [ $DEBUG_MODE -eq 1 ]
	then
		echo "${BLUE}[DEBUG] Petición JSON construida:${RESET}"
		cat "$TMP.req" | jq . 2>/dev/null || cat "$TMP.req"
		echo "${BLUE}[DEBUG] Validando formato JSON...${RESET}"
		if jq empty "$TMP.req" 2>/dev/null
		then
			echo "${GREEN}[DEBUG] JSON válido${RESET}"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON válida" >> "$LOG"
		else
			echo "${RED}[DEBUG] JSON inválido${RESET}"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON inválida" >> "$LOG"
		fi
	fi

	#ENVIA CON CONTEXTO SI HAY
	echo "${CYAN}Consultando...${RESET}"
	
	if [ $DEBUG_MODE -eq 1 ]
	then
		echo "${BLUE}[DEBUG] URL de la API: $API_URL${RESET}"
		echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Realizando petición curl a: $API_URL" >> "$LOG"
	fi
	
	curl -s -H "Content-Type: application/json" "$API_URL" -d @"$TMP.req" > "$TMP" 

	if grep -q '"error"' "$TMP"
	then
		echo "${RED}Error en peticion a la API${RESET}"
		echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - API error" >> "$LOG"
		if [ $DEBUG_MODE -eq 1 ]
		then
			echo "${BLUE}[DEBUG] Respuesta de error:${RESET}"
			cat "$TMP" | jq . 2>/dev/null || cat "$TMP"
			echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Respuesta de error completa en debug" >> "$LOG"
		else
			cat "$TMP"
		fi
		continue
	fi
	
	echo ""
	echo "${CYAN}IA:${RESET}"
	
	# EXTRAER RESPUESTA SIN -r
	jq '.candidates[0].content.parts[0].text' "$TMP" > "$RESP"

	read RESP_CHECK < "$RESP"
	if [ "$RESP_CHECK" = "null" ]
	then
		echo "${RED} Respuesta inválida, se ignora${RESET}"
		echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - Null response" >> "$LOG"
		continue
	fi
 
	# MUESTRA RESPUESTA SIN COMILLAS Y CON SALTOS DE LINEA
	sed 's/^"//;s/"$//' "$RESP" | awk '{gsub(/\\n/,"\n")}1'

	echo ""
	# GUARDAR RESPUESTA LIMPIA PARA CONTEXTO
	sed 's/^"//;s/"$//' "$RESP" > "$RESP.clean"

	echo '{"role":"model","parts":[{"text":' > "$TMP.model"
	cat "$RESP" >> "$TMP.model"
	echo '}]}'>> "$TMP.model"
	
	# construir nuevo contexto en fichero temporal

	if ! grep -q '"role"' "$CTX"
	then
		# contexto vacío
		cat "$TMP.user" > "$CTX.tmp"
		echo "," >> "$CTX.tmp"
		cat "$TMP.model" >> "$CTX.tmp"
	else
		cat "$CTX" > "$CTX.tmp"
		echo "," >> "$CTX.tmp"
		cat "$TMP.user" >> "$CTX.tmp"
		echo "," >> "$CTX.tmp"
		cat "$TMP.model" >> "$CTX.tmp"
	fi

	mv "$CTX.tmp" "$CTX"

	# limitar tamaño contexto 10 ultimas preguntas y respuestas (mantener últimas 20 entradas completas)
	if [ -s "$CTX" ]; then
	    sed -e '1s/^,*//' -e '$s/,$//' "$CTX" > "$CTX.clean" 2>> "$LOG"
	    if ! { echo '['; cat "$CTX.clean"; echo ']'; } | jq -r '. | reverse | .[0:20] | reverse | join(",")' > "$CTX.tmp" 2>> "$LOG"; then
	        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - jq failed to parse context" >> "$LOG"
	        echo "[DEBUG] CTX.clean content:" >> "$LOG"
	        cat "$CTX.clean" >> "$LOG"
	        echo "[DEBUG] End of CTX.clean" >> "$LOG"
	        # fallback: keep original context if jq fails
	        cp "$CTX" "$CTX.tmp"
	    fi
	    rm -f "$CTX.clean"
	else
	    echo "" > "$CTX.tmp"
	fi
	mv "$CTX.tmp" "$CTX"

	# ===== TOKENS =====
	echo "${CYAN}Uso:${RESET}"

	jq '.usageMetadata.totalTokenCount' "$TMP" > "$RESP.tokens"
	cat "$RESP.tokens"
	
	# acumulado
	read TOKENS_LINE < "$RESP.tokens"

	if [ "$TOKENS_LINE" = "null" ]
	then
		TOKENS_LINE=0
	fi

	TOTAL_TOKENS=`expr $TOTAL_TOKENS + $TOKENS_LINE`
	echo "${BLUE}Total acumulado:${RESET}"
	echo "$TOTAL_TOKENS"
	
	# precio aproximado
	echo "$TOTAL_TOKENS * 0.000002" > "$RESP.calc"
	bc < "$RESP.calc" > "$RESP.price"

	echo "${RED}Coste estimado (€):${RESET}"
	cat "$RESP.price"

	echo "${BLUE}--------------------------------${BLUE}"
	# ===== HILO (Conversación completa) =====
	echo "## Usuario" >> "$HILO"
	echo "$PROMPT" >> "$HILO"
	echo "" >> "$HILO"

	echo "## Gemini ($MODEL)" >> "$HILO"
	sed 's/^"//;s/"$//' "$RESP" |awk '{gsub(/\\n/,"\n")}1' >> "$HILO"
	echo "" >> "$HILO"

	echo "**Total acumulado:**" >> "$HILO"
	echo "$TOTAL_TOKENS tks" >> "$HILO"
	echo "" >> "$HILO"

	echo "**Coste estimado (€):**" >> "$HILO"
	cat "$RESP.price" >> "$HILO"
	echo "" >> "$HILO"

	# ===== LOG (Registro comprimido) =====
	echo "[OK] $MODEL - $TOKENS_LINE tokens - €$(cat "$RESP.price")" >> "$LOG"
done

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Sesion finalizada. Hilo y log guardados" >> "$LOG"

echo ""
echo "Hilo guardado en:"
echo "~/${HILO#$HOME/}"
echo "Log de sistema en:"
echo "~/${LOG#$HOME/}"
