#!/bin/sh

API_KEY="$GEMINI_API_KEY"
MODEL="gemini-flash-latest"
TIMEOUT=60

if [ "$1" = "-m" ]; then
  if [ "$2" = "pro" ]; then
    MODEL="gemini-pro-latest"
  fi
fi

API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"

ROOT_PATH="$HOME/Documents/ConversacionesGemini"

HILO="$ROOT_PATH/actual.md"
LOG="$ROOT_PATH/iadime.log"

TMPDIR="$ROOT_PATH/tmp/"
TMP="$ROOT_PATH/tmp/tmp.json"
RESP="$ROOT_PATH/tmp/ultima_resp.txt"
CTX="$ROOT_PATH/tmp/iadime_ctx.json"
IMG_COUNTER_FILE="$ROOT_PATH/tmp/img_counter"
IMG_DIR="$ROOT_PATH/imagenes"

mkdir -p "$ROOT_PATH/tmp"
mkdir -p "$IMG_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

if [ -z "$TERM" ]; then
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  RESET=''
fi

if ! command -v jq >/dev/null 2>&1; then
  printf "${RED}[WARN] jq no instalado → funcionalidad limitada${RESET}\n"
fi

if [ ! -f "$CTX" ]; then
  echo "" > "$CTX"
elif ! grep -q '"role"' "$CTX"; then
  echo "" > "$CTX"
fi

if [ ! -f "$HILO" ]; then
  echo "# Conversación Gemini" > "$HILO"
  echo "" >> "$HILO"
fi

TOTAL_TOKENS=0
DEBUG_MODE=0

if [ ! -f "$IMG_COUNTER_FILE" ]; then
  echo 0 > "$IMG_COUNTER_FILE"
fi

next_image_number() {
  read N < "$IMG_COUNTER_FILE"
  N=`expr $N + 1`
  echo "$N" > "$IMG_COUNTER_FILE"
  printf "%02d" "$N"
}

# Modelo Imagen en v1beta compatible. Cambia según tu cuenta / disponibilidad.
# Ejecuta :list-models para ver opciones disponibles (ej. imagen-4.0-generate-001, fast, ultra).
IMAGE_MODEL="imagen-4.0-generate-001"

generate_imagen() {
  PROMPT="$1"
  KEY="${IMAGEN_API_KEY:-$API_KEY}"

  if [ -z "$PROMPT" ]; then
    printf "${RED}Uso: :imagen <texto de la imagen>${RESET}\n"
    return 1
  fi

  if [ -z "$KEY" ]; then
    printf "${RED}No hay API key para Imagen (IMAGEN_API_KEY o GEMINI_API_KEY).${RESET}\n"
    return 1
  fi

  printf "${CYAN}Generando imagen para prompt: '%s'...${RESET}\n" "$PROMPT"

  IMAGE_API_URL="https://generativelanguage.googleapis.com/v1beta/models/$IMAGE_MODEL:predict?key=$KEY"
  IMAGE_TMP="$ROOT_PATH/tmp/imagen_response.json"

  # Escapar el prompt para JSON sin subshell
  printf '%s' "$PROMPT" | sed 's/"/\\"/g' > "$ROOT_PATH/tmp/prompt_escaped.txt"
  read ESCAPED_PROMPT < "$ROOT_PATH/tmp/prompt_escaped.txt"
  rm -f "$ROOT_PATH/tmp/prompt_escaped.txt"

  curl --max-time $TIMEOUT -s -X POST "$IMAGE_API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"instances\":[{\"prompt\":\"$ESCAPED_PROMPT\"}],\"parameters\":{\"sampleCount\":1}}" \
    -o "$IMAGE_TMP"

  # Log de debug para la respuesta de imagen sin subshell
  date '+%Y-%m-%d %H:%M:%S' > "$ROOT_PATH/tmp/timestamp_log.txt"
  read TIMESTAMP_LOG < "$ROOT_PATH/tmp/timestamp_log.txt"
  rm -f "$ROOT_PATH/tmp/timestamp_log.txt"
  echo "[DEBUG] $TIMESTAMP_LOG - Respuesta de imagen API:" >> "$LOG"
  cat "$IMAGE_TMP" >> "$LOG"
  echo "" >> "$LOG"

  # Extraer base64 del JSON de respuesta sin subshells
  if command -v jq >/dev/null 2>&1; then
    jq '.predictions[0].bytesBase64Encoded // .predictions[0].image.bytesBase64Encoded // .predictions[0].data[0].b64 // .predictions[0].output[0].imageBase64 // empty' "$IMAGE_TMP" | sed 's/^"//;s/"$//' > "$ROOT_PATH/tmp/b64_extract.txt"
    read B64_STRING < "$ROOT_PATH/tmp/b64_extract.txt"
    rm -f "$ROOT_PATH/tmp/b64_extract.txt"
  else
    tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"bytesBase64Encoded\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$ROOT_PATH/tmp/b64_extract.txt"
    read B64_STRING < "$ROOT_PATH/tmp/b64_extract.txt"
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"image.bytesBase64Encoded\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$ROOT_PATH/tmp/b64_extract.txt"
      read B64_STRING < "$ROOT_PATH/tmp/b64_extract.txt"
    fi
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"b64\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$ROOT_PATH/tmp/b64_extract.txt"
      read B64_STRING < "$ROOT_PATH/tmp/b64_extract.txt"
    fi
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"imageBase64\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$ROOT_PATH/tmp/b64_extract.txt"
      read B64_STRING < "$ROOT_PATH/tmp/b64_extract.txt"
    fi
    rm -f "$ROOT_PATH/tmp/b64_extract.txt"
  fi

  if [ -z "$B64_STRING" ] || [ "$B64_STRING" = "null" ]; then
    printf "${RED} Error al generar la imagen con Imagen 4.${RESET}\n"
    printf "${YELLOW}Respuesta JSON de depuración:${RESET}\n"
    cat "$IMAGE_TMP"
    return 1
  fi

  date +%s > "$ROOT_PATH/tmp/timestamp.txt"
  read TIMESTAMP < "$ROOT_PATH/tmp/timestamp.txt"
  rm -f "$ROOT_PATH/tmp/timestamp.txt"
  IMG_NUM=$(next_image_number)
  FILENAME="$IMG_DIR/imagen_${IMG_NUM}.png"

  # Escribir el base64 a un archivo temporal
  printf '%s' "$B64_STRING" > "$ROOT_PATH/tmp/b64_temp.txt"

  # Detectar qué variante de base64 funciona
  BASE64_CMD=""
  if base64 --decode "$ROOT_PATH/tmp/b64_temp.txt" >/dev/null 2>&1; then
    base64 --decode "$ROOT_PATH/tmp/b64_temp.txt" > "$FILENAME" 2>/dev/null
  elif base64 -d "$ROOT_PATH/tmp/b64_temp.txt" >/dev/null 2>&1; then
    base64 -d "$ROOT_PATH/tmp/b64_temp.txt" > "$FILENAME" 2>/dev/null
  elif base64 -D "$ROOT_PATH/tmp/b64_temp.txt" >/dev/null 2>&1; then
    base64 -D "$ROOT_PATH/tmp/b64_temp.txt" > "$FILENAME" 2>/dev/null
  else
    printf "${RED} Error: no se encuentra un comando base64 compatible.${RESET}\n"
    rm -f "$ROOT_PATH/tmp/b64_temp.txt"
    return 1
  fi

  rm -f "$ROOT_PATH/tmp/b64_temp.txt"

  if [ ! -f "$FILENAME" ] || [ ! -s "$FILENAME" ]; then
    printf "${RED} Error al decodificar Base64 a PNG.${RESET}\n"
    printf "${YELLOW}Respuesta JSON de depuración:${RESET}\n"
    cat "$IMAGE_TMP"
    return 1
  fi

  if command -v open >/dev/null 2>&1; then
    open "$FILENAME" >/dev/null 2>&1
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$FILENAME" >/dev/null 2>&1
  fi

  LAST_IMAGE_PATH="$FILENAME"
  LAST_IMAGE_NAME="imagen_${IMG_NUM}"

  printf "Imagen generada y guardada en: %s\n" "$FILENAME"
  return 0
}

printf "[ i a d i m e ] ($MODEL)\n"
printf "Escribe tu pregunta o usa los comandos [':leer'|':salir'|...|':ayuda']\n"

while true; do
  printf "${GREEN}Tu:${RESET}\n"
  read PROMPT || break

  case "$PROMPT" in
    ":salir")
      break
      ;;

    ":reset")
      rm -f "$TMPDIR"/*.json "$TMPDIR"/*.txt

      echo "" > "$CTX"
      echo "# Conversación Gemini" > "$HILO"
      echo "" >> "$HILO"

      echo 0 > "$IMG_COUNTER_FILE"
      
      echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Contexto reiniciado" >> "$LOG"
      printf "${CYAN}Contexto reiniciado${RESET}\n"
      continue
      ;;

    ":leer")
      if command -v mdv >/dev/null 2>&1; then
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
      if [ $DEBUG_MODE -eq 0 ]; then
        DEBUG_MODE=1
        printf "${GREEN}[DEBUG]${RESET} Modo debug ${GREEN}ACTIVADO${RESET}\n"
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Modo debug activado" >> "$LOG"
      else
        DEBUG_MODE=0
        printf "${YELLOW}[DEBUG]${RESET} Modo debug ${RED}DESACTIVADO${RESET}\n"
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Modo debug desactivado" >> "$LOG"
      fi
      continue
      ;;

    ":imagen" | ":imagen "*)
      printf '%s' "$PROMPT" | sed 's/^:imagen[[:space:]]*//' > "$ROOT_PATH/tmp/imagen_prompt.txt"
      read IMAGE_PROMPT < "$ROOT_PATH/tmp/imagen_prompt.txt"
      rm -f "$ROOT_PATH/tmp/imagen_prompt.txt"
      if [ -z "$IMAGE_PROMPT" ]; then
        printf "${CYAN}Uso: :imagen <texto>\n${RESET}"
      else
        generate_imagen "$IMAGE_PROMPT"
      fi
      continue
      ;;

    ":export "*)
      printf '%s' "$PROMPT" | sed 's/^:export //' > "$ROOT_PATH/tmp/export_name.txt"
      read EXPORT_NAME < "$ROOT_PATH/tmp/export_name.txt"
      rm -f "$ROOT_PATH/tmp/export_name.txt"
      if [ -z "$EXPORT_NAME" ]; then
        printf "${CYAN}Uso: :export NOMBRE\n${RESET}"
      else
        EXPORT_FILE="$ROOT_PATH/${EXPORT_NAME}.md"
        if [ -f "$EXPORT_FILE" ]; then
          printf "${CYAN}El archivo '$EXPORT_NAME.md' ya existe. ¿Sobrescribir? (s/n): ${RESET}"
          read CONFIRM
          if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
            printf "${CYAN}Exportación cancelada.\n${RESET}"
            continue
          fi
        fi
        cp "$HILO" "$EXPORT_FILE"
      # Exportar contexto tmp moviéndolo a Nombre_tmp para preservar estado completo
      EXPORT_TMP_DIR="$ROOT_PATH/${EXPORT_NAME}_tmp"
      if [ -d "$ROOT_PATH/tmp" ]; then
        if [ -d "$EXPORT_TMP_DIR" ]; then
          printf "${CYAN}El directorio de contexto '$EXPORT_NAME_tmp' ya existe. ¿Sobrescribir? (s/n): ${RESET}"
          read CONFIRM_TMP
          if [ "$CONFIRM_TMP" != "s" ] && [ "$CONFIRM_TMP" != "S" ]; then
            printf "${CYAN}Exportación de tmp cancelada.\n${RESET}"
          else
            rm -rf "$EXPORT_TMP_DIR"
            cp -r "$ROOT_PATH/tmp" "$EXPORT_TMP_DIR"
            rm -rf "$ROOT_PATH/tmp"
            mkdir -p "$ROOT_PATH/tmp"
            echo "# Conversación Gemini" > "$HILO"
            echo "" >> "$HILO"
          fi
        else
          cp -r "$ROOT_PATH/tmp" "$EXPORT_TMP_DIR"
          rm -rf "$ROOT_PATH/tmp"
          mkdir -p "$ROOT_PATH/tmp"
          echo "# Conversación Gemini" > "$HILO"
          echo "" >> "$HILO"
        fi
      fi
      # Reiniciar el contexto actual para empezar nueva conversación
      echo "" > "$CTX"
      printf "${GREEN}Conversación exportada: '$EXPORT_NAME'.\n Contexto reiniciado${RESET}\n"
      date '+%Y-%m-%d %H:%M:%S' > "$ROOT_PATH/tmp/ts_export.txt"
      read TS_EXPORT < "$ROOT_PATH/tmp/ts_export.txt"
      rm -f "$ROOT_PATH/tmp/ts_export.txt"
      echo "[INFO] $TS_EXPORT - Conversación exportada: $EXPORT_NAME". Contexto reiniciado >> "$LOG"
      fi
      continue
      ;;

    ":import "*)
      printf '%s' "$PROMPT" | sed 's/^:import //' > "$ROOT_PATH/tmp/import_name.txt"
      read IMPORT_NAME < "$ROOT_PATH/tmp/import_name.txt"
      rm -f "$ROOT_PATH/tmp/import_name.txt"
      if [ -z "$IMPORT_NAME" ]; then
        printf "${CYAN}Uso: :import NOMBRE\n${RESET}"
      else
        IMPORT_FILE="$ROOT_PATH/${IMPORT_NAME}.md"
        if [ ! -f "$IMPORT_FILE" ]; then
          printf "${RED}El archivo '$IMPORT_NAME.md' no existe.\n${RESET}"
        else
          printf "${YELLOW}Advertencia:${RESET} ${CYAN}Al importar se borrará el contexto actual e imágenes generadas si no se han exportado previamente. ¿Continuar? (s/n): ${RESET}"
          read CONFIRM_IMPORT
          if [ "$CONFIRM_IMPORT" != "s" ] && [ "$CONFIRM_IMPORT" != "S" ]; then
            printf "${CYAN}Importación cancelada.\n${RESET}"
            continue
          fi
          cp "$IMPORT_FILE" "$HILO"
          printf "${GREEN}Conversación importada : '$IMPORT_NAME'\n${RESET}"
          date '+%Y-%m-%d %H:%M:%S' > "$ROOT_PATH/tmp/ts_import.txt"
          read TS_IMPORT < "$ROOT_PATH/tmp/ts_import.txt"
          rm -f "$ROOT_PATH/tmp/ts_import.txt"
          echo "[INFO] $TS_IMPORT - Conversación importada: $IMPORT_NAME" >> "$LOG"
          # Restaurar contexto tmp desde Nombre_tmp si existe
          IMPORT_TMP_DIR="$ROOT_PATH/${IMPORT_NAME}_tmp"
          if [ -d "$IMPORT_TMP_DIR" ]; then
            rm -rf "$ROOT_PATH/tmp"
            cp -r "$IMPORT_TMP_DIR" "$ROOT_PATH/tmp"

            if [ ! -f "$CTX" ]; then
              printf "${CYAN}Advertencia: no se encontró contexto.${RESET}\n"
              echo "" > "$CTX"
            fi
          else
            # Si no existe tmp específico, crear directorio tmp limpio
            mkdir -p "$ROOT_PATH/tmp"
            # y reiniciar contexto (no hay contexto guardado)
            echo "" > "$CTX"
            printf "${CYAN}Advertencia: no se encontró carpeta %s_tmp, se inicia sin contexto guardado.${RESET}\n" "$IMPORT_NAME"
          fi
        fi
      fi
      continue
      ;;

    ":list-models")
      printf "${CYAN}Modelos de Imagen y Gemini disponibles:${RESET}\n"
      MODELS_JSON=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY")
      if echo "$MODELS_JSON" | grep -q 'error'; then
        printf "${RED}Error al obtener lista de modelos: ${RESET}\n"
        echo "$MODELS_JSON" | jq '.error.message' > "$ROOT_PATH/tmp/models_error.txt"
        sed 's/^"//' "$ROOT_PATH/tmp/models_error.txt" | sed 's/"$//' | head -1 > "$ROOT_PATH/tmp/models_message.txt"
        read message < "$ROOT_PATH/tmp/models_message.txt"
        echo "$message"
        rm -f "$ROOT_PATH/tmp/models_error.txt" "$ROOT_PATH/tmp/models_message.txt"
      else
        echo "$MODELS_JSON" | jq '.models[] | select(.name | startswith("models/imagen") or startswith("models/gemini")) | .name' > "$ROOT_PATH/tmp/models_list.txt"
        sed 's/^"//' "$ROOT_PATH/tmp/models_list.txt" | sed 's/"$//' | sed 's/models\///' > "$ROOT_PATH/tmp/models_clean.txt"
        cat "$ROOT_PATH/tmp/models_clean.txt" || printf "${RED}No se pudieron parsear los modelos. jq no disponible o respuesta inválida.${RESET}\n"
        rm -f "$ROOT_PATH/tmp/models_list.txt" "$ROOT_PATH/tmp/models_clean.txt"
      fi
      continue
      ;;

    ":list")
      printf "${CYAN}Conversaciones disponibles:${RESET}\n"
      ls "$ROOT_PATH/" | grep '\.md$' | sed 's/\.md$//'  
      continue
      ;;

    ":model"* )
      printf '%s' "$PROMPT" | sed 's/^:model //' > "$ROOT_PATH/tmp/new_model.txt"
      read NEW_MODEL < "$ROOT_PATH/tmp/new_model.txt"
      rm -f "$ROOT_PATH/tmp/new_model.txt"
      if [ "$NEW_MODEL" = "pro" ]; then
        MODEL="gemini-pro-latest"
      else
        MODEL="gemini-flash-latest"
      fi
      API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"
      printf "${CYAN}Modelo cambiado a $MODEL${RESET}\n"
      echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Modelo cambiado a $MODEL" >> "$LOG"
      continue
      ;;

    ":tokens")
      echo "Total: $TOTAL_TOKENS"
      cat "$RESP.price"
      continue
    ;;

    ":ayuda")
      printf "${CYAN}Uso: '> iadime -m [pro|flash]' ...${RESET}\n"
      echo "Escribe tu pregunta,o usa los comandos:"
		echo "  ':leer'           - Leer la conversación actual"
		echo "  ':imagen <texto>' - Generar imagen con el texto dado"
		echo "  ':list-models'    - Lista modelos de imagen disponibles"
    echo "  ':tokens'         - Mostrar tokens acumulados y coste estimado"
		echo "  ':salir'          - Salir del programa"
		echo "  ':reset'          - Reiniciar contexto"
		echo "  ':clear'          - Limpiar pantalla"
		echo "  ':export TITULO'  - Exportar conversación"
		echo "  ':import TITULO'  - Importar conversación"
		echo "  ':list'           - Listar conversaciones"
		echo "  ':model pro/flash' - Cambiar modelo"
		echo "  ':debug'          - Alternar modo debug y validar petición"
		echo "  ':ayuda'          - Mostrar esta ayuda"
    echo ""
    echo "Para que la imagen la genere la IA, solicita que la siguiente respuesta incluya una descripcion de la imagen encerrada entre etiquetas <imagen>descripción de la imagen</imagen>. Ejemplo: 'Describe un paisaje y genera una imagen con esa descripción. La descripción de la imagen debe ir entre <imagen>y</imagen>'."
      continue
      ;;

    :*)
      printf "${RED}Comando desconocido${RESET}\n"
      continue
      ;;
  esac

  if [ -z "$PROMPT" ]; then
    if [ $DEBUG_MODE -eq 1 ]; then
      printf "${RED}[DEBUG] Pregunta vacía${RESET}\n"
      echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Pregunta vacía rechazada" >> "$LOG"
    fi
    continue
  fi
  
  printf '%s' "$PROMPT" | sed 's/"/\\"/g' > "$TMP.prompt"
  read PROMPT_ESCAPED < "$TMP.prompt"
  rm -f "$TMP.prompt"

  echo '{"role":"user","parts":[{"text":"'"$PROMPT_ESCAPED"'"}]}' > "$TMP.user"

  if [ $DEBUG_MODE -eq 1 ]; then
    printf "${BLUE}[DEBUG] Validando pregunta...${RESET}\n"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Pregunta enviada: $PROMPT" >> "$LOG"
  fi

  sed '1s/^,*//' "$CTX" > "$CTX.tmp" 2>> "$LOG"
  mv "$CTX.tmp" "$CTX"

  echo '{"contents":[' > "$TMP.req"
  FIRST=1
  if grep -q '"role"' "$CTX"; then
    cat "$CTX" >> "$TMP.req"
    FIRST=0
  fi
  if [ $FIRST -eq 0 ]; then
    echo "," >> "$TMP.req"
  fi
  cat "$TMP.user" >> "$TMP.req"
  echo ']}' >> "$TMP.req"

  if [ $DEBUG_MODE -eq 1 ]; then
    printf "${BLUE}[DEBUG] Petición JSON construida:${RESET}\n"
    cat "$TMP.req"
    printf "${BLUE}[DEBUG] Validando formato JSON...${RESET}\n"
    printf "${RED}[DEBUG] JSON no validado${RESET}\n"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON no validada" >> "$LOG"
  fi

  printf "${CYAN}Consultando...${RESET}\n"
  curl -s --max-time $TIMEOUT -H "Content-Type: application/json" "$API_URL" -d @"$TMP.req" > "$TMP"

  if grep -q '"error"' "$TMP"; then
    jq '.error.code' "$TMP" > "$ROOT_PATH/tmp/error_code.txt"
    sed 's/^"//' "$ROOT_PATH/tmp/error_code.txt" | sed 's/"$//' | head -1 > "$ROOT_PATH/tmp/code.txt"
    read code < "$ROOT_PATH/tmp/code.txt"
    jq '.error.message' "$TMP" > "$ROOT_PATH/tmp/error_message.txt"
    sed 's/^"//' "$ROOT_PATH/tmp/error_message.txt" | sed 's/"$//' | head -1 > "$ROOT_PATH/tmp/message.txt"
    read message < "$ROOT_PATH/tmp/message.txt"
    rm -f "$ROOT_PATH/tmp/error_code.txt" "$ROOT_PATH/tmp/code.txt" "$ROOT_PATH/tmp/error_message.txt" "$ROOT_PATH/tmp/message.txt"
    printf "${RED}Error en peticion a la API (code=%s): %s${RESET}\n" "$code" "$message"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - API error code=$code" >> "$LOG"
    if [ "$code" = "404" ] || echo "$message" | grep -q "not found"; then
      printf "${RED}Modelo de Imagen no encontrado en esta API/version. Cambia IMAGE_MODEL en el codigo del script.${RESET}\n"
    fi
    if [ $DEBUG_MODE -eq 1 ]; then
      printf "${BLUE}[DEBUG] Respuesta de error:${RESET}\n"
      cat "$TMP"
    else
      cat "$TMP"
    fi
    continue
  fi

  # EXTRAER RESPUESTA SIN -r
  jq '.candidates[0].content.parts[0].text' "$TMP" > "$RESP"

  read RESP_CHECK < "$RESP"
  if [ "$RESP_CHECK" = "null" ]; then
    printf "${RED}Respuesta inválida, se ignora${RESET}\n"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - Null response" >> "$LOG"
    continue
  fi

  sed 's/^"//;s/"$//' "$RESP" > "$ROOT_PATH/tmp/response_raw.txt"

  RESPONSE_NORMALIZED="$ROOT_PATH/tmp/response_formatted.txt"

  awk '{
    gsub(/\r/, "");
    gsub(/\\n/, "\n");
    print
  }' "$ROOT_PATH/tmp/response_raw.txt" > "$RESPONSE_NORMALIZED"

  rm -f "$ROOT_PATH/tmp/response_raw.txt"

IMAGE_PATH=""
IMAGE_NAME=""
IMAGE_PROMPT_CLEAN=""

if grep -q "<imagen>" "$RESPONSE_NORMALIZED"; then

  # Extraer prompt
  awk 'BEGIN{RS="<imagen>"; FS="</imagen>"} NR==2 {print $1; exit}' "$RESPONSE_NORMALIZED" > "$ROOT_PATH/tmp/image_prompt.txt"
  read IMAGE_PROMPT < "$ROOT_PATH/tmp/image_prompt.txt"
  rm -f "$ROOT_PATH/tmp/image_prompt.txt"

  # Limpiar respuesta (quitar bloque imagen)
  sed '/<imagen>/,/<\/imagen>/d' "$RESPONSE_NORMALIZED" > "$ROOT_PATH/tmp/response_clean.txt"
  mv "$ROOT_PATH/tmp/response_clean.txt" "$RESPONSE_NORMALIZED"

  # Normalizar prompt (por si hay \n u otros caracteres escapados)
  printf '%s' "$IMAGE_PROMPT" | awk '{gsub(/\\n/, "\n")}1' > "$ROOT_PATH/tmp/image_prompt_clean.txt"
  read IMAGE_PROMPT_CLEAN < "$ROOT_PATH/tmp/image_prompt_clean.txt"
  rm -f "$ROOT_PATH/tmp/image_prompt_clean.txt"

  # Generar imagen
  generate_imagen "$IMAGE_PROMPT_CLEAN"

  IMAGE_PATH="$LAST_IMAGE_PATH"
  IMAGE_NAME="$LAST_IMAGE_NAME"
fi

  cat "$RESPONSE_NORMALIZED"
  cat "$RESPONSE_NORMALIZED" > "$RESP.clean"

  printf '%s' "$(cat "$RESPONSE_NORMALIZED" | sed 's/"/\\"/g')" > "$ROOT_PATH/tmp/resp_escaped.txt"
  read RESP_ESCAPED < "$ROOT_PATH/tmp/resp_escaped.txt"
  rm -f "$ROOT_PATH/tmp/resp_escaped.txt"

  echo '{"role":"model","parts":[{"text":"'"$RESP_ESCAPED"'"}]}' > "$TMP.model"

  if ! grep -q '"role"' "$CTX"; then
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

  if [ -s "$CTX" ]; then
    sed -e '1s/^,*//' -e '$s/,$//' "$CTX" > "$CTX.clean" 2>> "$LOG"

    # Mantener solo las últimas 20 entradas (de 10 turnos) para el siguiente request
    if ! { echo '['; cat "$CTX.clean"; echo ']'; } | jq '.[-20:] | join(",")' > "$CTX.tmp" 2>> "$LOG"; then
      echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - jq falló al reducir contexto" >> "$LOG"
      cat "$CTX" > "$CTX.tmp"
    fi

    rm -f "$CTX.clean"
  else
    echo "" > "$CTX.tmp"
  fi
  mv "$CTX.tmp" "$CTX"

  printf "${CYAN}Uso:${RESET}\n"
  jq '.usageMetadata.totalTokenCount' "$TMP" > "$RESP.tokens"
  cat "$RESP.tokens"

  read TOKENS_LINE < "$RESP.tokens"
  if [ "$TOKENS_LINE" = "null" ]; then
    TOKENS_LINE=0
  fi

  TOTAL_TOKENS=`expr $TOTAL_TOKENS + $TOKENS_LINE`
  printf "${BLUE}Total acumulado:${RESET}\n"
  echo "$TOTAL_TOKENS"

  echo "$TOTAL_TOKENS * 0.000002" > "$RESP.calc"
  bc < "$RESP.calc" > "$RESP.price"

  printf "${RED}Coste estimado (€):${RESET}\n"
  cat "$RESP.price"

  printf "${BLUE}--------------------------------${RESET}\n"

  echo "## Usuario" >> "$HILO"
  echo "$PROMPT" >> "$HILO"
  echo "" >> "$HILO"

  echo "## Gemini ($MODEL)" >> "$HILO"
  cat "$RESPONSE_NORMALIZED" >> "$HILO"
  if [ -n "$IMAGE_PATH" ]; then
    echo "" >> "$HILO"
    echo "![${IMAGE_NAME}]($IMAGE_PATH)" >> "$HILO"
    echo "" >> "$HILO"
    echo "> $IMAGE_PROMPT_CLEAN" >> "$HILO"
  fi
  echo "" >> "$HILO"

  echo "**Total acumulado:**" >> "$HILO"
  echo "$TOTAL_TOKENS tks" >> "$HILO"
  echo "" >> "$HILO"
  echo "**Coste estimado (€):**" >> "$HILO"
  cat "$RESP.price" >> "$HILO"
  echo "" >> "$HILO"

  echo "[OK] $MODEL - $TOKENS_LINE tokens - €$(cat "$RESP.price")" >> "$LOG"

done

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Sesion finalizada. Hilo y log guardados" >> "$LOG"

echo ""
echo "Hilo guardado en:"
echo "~/${HILO#$HOME/}"
echo "Log de sistema en:"
echo "~/${LOG#$HOME/}"

