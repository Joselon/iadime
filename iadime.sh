#!/bin/sh

API_KEY="$GEMINI_API_KEY"
MODEL="gemini-flash-latest"

if [ "$1" = "-m" ]; then
  if [ "$2" = "pro" ]; then
    MODEL="gemini-pro-latest"
  fi
fi

API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"

ROOT_PATH="$HOME/Documents/ConversacionesGemini"
mkdir -p "$ROOT_PATH/tmp"

HILO="$ROOT_PATH/actual.md"
LOG="$ROOT_PATH/iadime.log"
TMP="$ROOT_PATH/tmp/tmp.json"
RESP="$ROOT_PATH/tmp/ultima_resp.txt"
CTX="$ROOT_PATH/tmp/iadime_ctx.json"
TMPDIR="$ROOT_PATH/tmp/"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

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

  printf "Generando imagen para prompt: '%s'...\n" "$PROMPT"

  IMAGE_API_URL="https://generativelanguage.googleapis.com/v1beta/models/$IMAGE_MODEL:predict?key=$KEY"
  IMAGE_TMP="$ROOT_PATH/tmp/imagen_response.json"

  curl -s -X POST "$IMAGE_API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"instances\":[{\"prompt\":\"$(printf '%s' "$PROMPT" | sed 's/\"/\\\\\"/g')\"}],\"parameters\":{\"sampleCount\":1}}" \
    -o "$IMAGE_TMP"

  # Log de debug para la respuesta de imagen
  echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Respuesta de imagen API:" >> "$LOG"
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
  FILENAME="$ROOT_PATH/tmp/iadime_imagen_${TIMESTAMP}.png"

  BASE64_CMD=""
  if printf '%s' "" | base64 --decode >/dev/null 2>&1; then
    BASE64_CMD="base64 --decode"
  elif printf '%s' "" | base64 -d >/dev/null 2>&1; then
    BASE64_CMD="base64 -d"
  elif printf '%s' "" | base64 -D >/dev/null 2>&1; then
    BASE64_CMD="base64 -D"
  else
    printf "${RED} Error: no se encuentra un comando base64 compatible.${RESET}\n"
    return 1
  fi

  if ! printf '%s' "$B64_STRING" | $BASE64_CMD > "$FILENAME" 2>/dev/null; then
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
      echo "" > "$CTX"
      echo "" > "$HILO"
      rm -f "$TMPDIR"/*
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
        printf "${YELLOW}Uso: :imagen <texto>\n${RESET}"
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
        printf "${YELLOW}Uso: :export NOMBRE\n${RESET}"
      else
        EXPORT_FILE="$ROOT_PATH/${EXPORT_NAME}.md"
        if [ -f "$EXPORT_FILE" ]; then
          printf "${YELLOW}El archivo '$EXPORT_NAME.md' ya existe. ¿Sobrescribir? (s/n): ${RESET}"
          read CONFIRM
          if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
            printf "${CYAN}Exportación cancelada.\n${RESET}"
            continue
          fi
        fi
        cp "$HILO" "$EXPORT_FILE"
        printf "${GREEN}Conversación exportada a '$EXPORT_NAME.md'\n${RESET}"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Conversación exportada a $EXPORT_NAME.md" >> "$LOG"
      fi
      continue
      ;;

    ":import "*)
      printf '%s' "$PROMPT" | sed 's/^:import //' > "$ROOT_PATH/tmp/import_name.txt"
      read IMPORT_NAME < "$ROOT_PATH/tmp/import_name.txt"
      rm -f "$ROOT_PATH/tmp/import_name.txt"
      if [ -z "$IMPORT_NAME" ]; then
        printf "${YELLOW}Uso: :import NOMBRE\n${RESET}"
      else
        IMPORT_FILE="$ROOT_PATH/${IMPORT_NAME}.md"
        if [ ! -f "$IMPORT_FILE" ]; then
          printf "${RED}El archivo '$IMPORT_NAME.md' no existe.\n${RESET}"
        else
          cp "$IMPORT_FILE" "$HILO"
          printf "${GREEN}Conversación importada desde '$IMPORT_NAME.md'\n${RESET}"
          echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Conversación importada desde $IMPORT_NAME.md" >> "$LOG"
          # Reset context when importing
          echo "" > "$CTX"
          rm -f "$TMPDIR"/*
        fi
      fi
      continue
      ;;

    ":list-models")
      printf "${CYAN}Modelos de Imagen disponibles:${RESET}\n"
      MODELS_JSON=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY")
      if echo "$MODELS_JSON" | grep -q '"error"'; then
        printf "${RED}Error al obtener lista de modelos: ${RESET}\n"
        echo "$MODELS_JSON" | jq -r '.error.message // "Error desconocido"' 2>/dev/null || echo "$MODELS_JSON"
      else
        echo "$MODELS_JSON" | jq -r '.models[] | select(.name | startswith("models/imagen")) | .name' 2>/dev/null | sed 's/models\///' || printf "${YELLOW}No se pudieron parsear los modelos. Respuesta:${RESET}\n$MODELS_JSON\n"
      fi
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

    ":ayuda")
      printf "${CYAN}Uso: '> iadime -m [pro|flash]' ...${RESET}\n"
      echo "Escribe tu pregunta o usa los comandos:"
		echo "  ':leer'           - Leer la conversación actual"
		echo "  ':imagen <texto>' - Generar imagen con el texto dado"
		echo "  ':list-models'    - Lista modelos de imagen disponibles"
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

  echo '{"role":"user","parts":[{"text":"'"$PROMPT"'"}]}' > "$TMP.user"

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
    cat "$TMP.req" | jq . 2>/dev/null || cat "$TMP.req"
    printf "${BLUE}[DEBUG] Validando formato JSON...${RESET}\n"
    if jq empty "$TMP.req" 2>/dev/null; then
      printf "${GREEN}[DEBUG] JSON válido${RESET}\n"
      echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON válida" >> "$LOG"
    else
      printf "${RED}[DEBUG] JSON inválido${RESET}\n"
      echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON inválida" >> "$LOG"
    fi
  fi

  printf "${CYAN}Consultando...${RESET}\n"
  curl -s --max-time 60 -H "Content-Type: application/json" "$API_URL" -d @"$TMP.req" > "$TMP"

  if grep -q '"error"' "$TMP"; then
    code=$(jq -r '.error.code // empty' "$TMP" 2>/dev/null || echo "")
    message=$(jq -r '.error.message // empty' "$TMP" 2>/dev/null || echo "")
    printf "${RED}Error en peticion a la API (code=%s): %s${RESET}\n" "$code" "$message"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - API error code=$code" >> "$LOG"
    if [ "$code" = "404" ] || echo "$message" | grep -q "not found"; then
      printf "${YELLOW}Modelo de Imagen no encontrado en esta API/version. Cambia IMAGE_MODEL en el script (por ejemplo, imagen-alpha-1).${RESET}\n"
    fi
    if [ $DEBUG_MODE -eq 1 ]; then
      printf "${BLUE}[DEBUG] Respuesta de error:${RESET}\n"
      cat "$TMP" | jq . 2>/dev/null || cat "$TMP"
    else
      cat "$TMP"
    fi
    continue
  fi

  jq '.candidates[0].content.parts[0].text' "$TMP" > "$RESP"
  read RESP_CHECK < "$RESP"
  if [ "$RESP_CHECK" = "null" ]; then
    printf "${RED}Respuesta inválida, se ignora${RESET}\n"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - Null response" >> "$LOG"
    continue
  fi

  sed 's/^\"//;s/\"$//' "$RESP" > "$ROOT_PATH/tmp/response_raw.txt"
  read RESPONSE_RAW < "$ROOT_PATH/tmp/response_raw.txt"
  rm -f "$ROOT_PATH/tmp/response_raw.txt"
  if echo "$RESPONSE_RAW" | grep -q "<imagen>.*</imagen>"; then
    printf '%s' "$RESPONSE_RAW" | sed -n 's/.*<imagen>\(.*\)<\/imagen>.*/\1/p' > "$ROOT_PATH/tmp/image_prompt_extracted.txt"
    read IMAGE_PROMPT < "$ROOT_PATH/tmp/image_prompt_extracted.txt"
    rm -f "$ROOT_PATH/tmp/image_prompt_extracted.txt"
    printf '%s' "$RESPONSE_RAW" | sed 's/<imagen>.*<\/imagen>//g' > "$ROOT_PATH/tmp/response_clean.txt"
    read RESPONSE_RAW < "$ROOT_PATH/tmp/response_clean.txt"
    rm -f "$ROOT_PATH/tmp/response_clean.txt"
    generate_imagen "$IMAGE_PROMPT"
  fi

  printf '%s\n' "$RESPONSE_RAW" | awk '{gsub(/\\n/,"\n")}1'
  echo "$RESPONSE_RAW" > "$RESP.clean"

  cat "$RESP" | sed 's/<imagen>.*<\/imagen>//g' > "$ROOT_PATH/tmp/resp_json.txt"
  read RESP_JSON < "$ROOT_PATH/tmp/resp_json.txt"
  rm -f "$ROOT_PATH/tmp/resp_json.txt"
  cat > "$TMP.model" <<MODELJSON
{"role":"model","parts":[{"text":$RESP_JSON}]}
MODELJSON

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

    # Para evitar colgados en jq con contexto grande, simplificar a mantener todo el contexto
    cat "$CTX.clean" > "$CTX.tmp"

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
  printf '%s\n' "$RESPONSE_RAW" >> "$HILO"
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

