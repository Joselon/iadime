#!/bin/sh

API_KEY="$GEMINI_API_KEY"
MODEL="gemini-flash-latest"
TOKEN_PRICE="0.000002" # Precio por token en euros (ajustar según modelo)
IMAGE_MODEL="imagen-4.0-generate-001"
IMAGE_PRICE="0.05" # Precio aproximado (no oficial) por imagen en euros (ajustar según modelo)
TIMEOUT=120

if [ "$1" = "-m" ]; then
  if [ "$2" = "pro" ]; then
    MODEL="gemini-pro-latest"
  fi
fi

API_URL="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$API_KEY"

DEFAULT_SYSTEM_PROMPT="Eres un asistente útil. Si el usuario pide una imagen, genera un prompt detallado en inglés entre etiquetas [IMAGEN_PROMPT]PROMPT[/IMAGEN_PROMPT]. Responde siempre en español."

ROOT_PATH="."
IMAGES_DIR="imagenes"

HILO="$ROOT_PATH/actual.md"
LOG="$ROOT_PATH/iadime.log"

TMPDIR="$ROOT_PATH/tmp"
TMP="$TMPDIR/tmp.json"
RESP="$TMPDIR/ultima_resp.txt"
CTX="$TMPDIR/iadime_ctx.json"
IMG_DIR_PATH="$ROOT_PATH/$IMAGES_DIR"

mkdir -p "$TMPDIR"
mkdir -p "$IMG_DIR_PATH"

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

# Detectar entorno shell
OS_NAME=$(uname)

ENV_A_SHELL=0
ENV_ISH=0
ENV_LINUX_GUI=0

if  [ "$OS_NAME" = "Darwin" ] && [ "$SHELL" = "/bin/sh" ]; then
  ENV_A_SHELL=1
fi

if [ "$OS_NAME" = "Linux" ] && [ "$SHELL" = "/bin/ash" ] && ! command -v xdg-open > /dev/null 2>&1; then
  ENV_ISH=1
fi

if [ "$OS_NAME" = "Linux" ] && command -v xdg-open > /dev/null 2>&1; then
  ENV_LINUX_GUI=1
fi

# Dependencias
command -v jq >/dev/null || { echo "jq no instalado. Revisa los requisitos en README.md"; exit 1; }
command -v curl >/dev/null || { echo "curl no instalado. Revisa los requisitos en README.md"; exit 1; }

#Iniciar archivos si no existen
if [ ! -f "$CTX" ]; then
  echo "[]" > "$CTX"
elif ! grep -q '"role"' "$CTX"; then
  echo "[]" > "$CTX"
fi

if [ ! -f "$HILO" ]; then
  crea_titulo_hilo
fi

SYSTEM_PROMPT=""
HILO_TITLE="Conversación Actual"

if [ ! -f "$TMPDIR/system_prompt.txt" ]; then
  SYSTEM_PROMPT="$DEFAULT_SYSTEM_PROMPT"
else
  SYSTEM_PROMPT=$(cat "$TMPDIR/system_prompt.txt")  
fi

TOTAL_TOKENS=0
DEBUG_MODE=0
IMAGEN_GENERATED=0
RESPONSE_NORMALIZED="$TMPDIR/response_formatted.txt"

# Funciones
crea_titulo_hilo() {
  if [ -n "$1" ]; then
    HILO_TITLE="$1"
  fi
  echo "# $HILO_TITLE" > "$HILO"
  echo "" >> "$HILO"
  echo "> Reglas: $SYSTEM_PROMPT" >> "$HILO"
  echo "" >> "$HILO"
}

set_hilo_title() {
  if [ -n "$1" ]; then
    HILO_TITLE="$1"
  fi
  if [ -f "$HILO" ]; then
    tail -n +2 "$HILO" > "$TMPDIR/hilo_rest.tmp"
    printf '# %s\n' "$HILO_TITLE" > "$HILO"
    cat "$TMPDIR/hilo_rest.tmp" >> "$HILO"
    rm -f "$TMPDIR/hilo_rest.tmp"
  else
    crea_titulo_hilo "$HILO_TITLE"
  fi
}

consulta_api() {
  curl -s --max-time $TIMEOUT -H "Content-Type: application/json" "$1" -d @"$2"
}
#Crea TMP.req con el contexto $CTX+ mensaje del usuario (archivo) $TMP.user =con reglas $SYSTEM_PROMPT
crea_consulta() {
  jq -n \
    --slurpfile ctx "$CTX" \
    --slurpfile user "$TMP.user" \
    --arg sys "$SYSTEM_PROMPT" \
    '{
      system_instruction: { parts: [{ text: $sys }] },
      contents: ($ctx[0] + [$user[0]])
    }' > "$TMP.req"

  if [ $DEBUG_MODE -eq 1 ]; then
    printf "${BLUE}[DEBUG] Petición JSON construida:${RESET}\n"
    cat "$TMP.req"
    printf "${BLUE}[DEBUG] Validando formato JSON...${RESET}\n"
  fi
}

generate_imagen() {
  IMAGE_PROMPT_INPUT="$1"
  KEY="${IMAGEN_API_KEY:-$API_KEY}"

  if [ -z "$IMAGE_PROMPT_INPUT" ]; then
    printf "${RED}Uso: :imagen <texto de la imagen>${RESET}\n"
    return 1
  fi

  if [ -z "$KEY" ]; then
    printf "${RED}No hay API key para Imagen (IMAGEN_API_KEY o GEMINI_API_KEY).${RESET}\n"
    return 1
  fi

  printf "${CYAN}Generando imagen para prompt: '%s'...${RESET}\n" "$IMAGE_PROMPT_INPUT"

  IMAGE_API_URL="https://generativelanguage.googleapis.com/v1beta/models/$IMAGE_MODEL:predict?key=$KEY"
  IMAGE_TMP="$TMPDIR/imagen_response.json"

  jq -n \
    --arg prompt "$IMAGE_PROMPT_INPUT" \
    '{
      instances: [{ prompt: $prompt }],
      parameters: { sampleCount: 1 }
    }' > "$TMPDIR/image_req.json"

  curl --max-time $TIMEOUT -s -X POST "$IMAGE_API_URL" \
    -H "Content-Type: application/json" \
    -d @"$TMPDIR/image_req.json" \
    -o "$IMAGE_TMP"

  # Log de debug para la respuesta de imagen sin subshell
  if [ $DEBUG_MODE -eq 1 ]; then
    date '+%Y-%m-%d %H:%M:%S' > "$TMPDIR/timestamp_log.txt"
    read TIMESTAMP_LOG < "$TMPDIR/timestamp_log.txt"
    rm -f "$TMPDIR/timestamp_log.txt"
    echo "[DEBUG] $TIMESTAMP_LOG - Respuesta de imagen API:" >> "$LOG"
    cat "$IMAGE_TMP" >> "$LOG"
    echo "" >> "$LOG"
  fi

  # Extraer base64 del JSON de respuesta sin subshells
  if command -v jq >/dev/null 2>&1; then
    jq '.predictions[0].bytesBase64Encoded // .predictions[0].image.bytesBase64Encoded // .predictions[0].data[0].b64 // .predictions[0].output[0].imageBase64 // empty' "$IMAGE_TMP" | sed 's/^"//;s/"$//' > "$TMPDIR/b64_extract.txt"
    read B64_STRING < "$TMPDIR/b64_extract.txt"
    rm -f "$TMPDIR/b64_extract.txt"
  else
    tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"bytesBase64Encoded\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$TMPDIR/b64_extract.txt"
    read B64_STRING < "$TMPDIR/b64_extract.txt"
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"image.bytesBase64Encoded\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$TMPDIR/b64_extract.txt"
      read B64_STRING < "$TMPDIR/b64_extract.txt"
    fi
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"b64\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$TMPDIR/b64_extract.txt"
      read B64_STRING < "$TMPDIR/b64_extract.txt"
    fi
    if [ -z "$B64_STRING" ]; then
      tr -d '\n' < "$IMAGE_TMP" | sed -n 's/.*\"imageBase64\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' > "$TMPDIR/b64_extract.txt"
      read B64_STRING < "$TMPDIR/b64_extract.txt"
    fi
    rm -f "$TMPDIR/b64_extract.txt"
  fi

  if [ -z "$B64_STRING" ] || [ "$B64_STRING" = "null" ]; then
    printf "${RED} Error al generar la imagen con Imagen 4.${RESET}\n"
    printf "${YELLOW}Respuesta JSON de depuración:${RESET}\n"
    cat "$IMAGE_TMP"
    return 1
  fi

  date +%s > "$TMPDIR/timestamp.txt"
  read TIMESTAMP < "$TMPDIR/timestamp.txt"
  rm -f "$TMPDIR/timestamp.txt"
  FILENAME="$IMG_DIR_PATH/imagen_${TIMESTAMP}.png"

  # Escribir el base64 a un archivo temporal
  printf '%s' "$B64_STRING" > "$TMPDIR/b64_temp.txt"

  # Detectar qué variante de base64 funciona
  if base64 --decode "$TMPDIR/b64_temp.txt" >/dev/null 2>&1; then
    base64 --decode "$TMPDIR/b64_temp.txt" > "$FILENAME" 2>/dev/null
  elif base64 -d "$TMPDIR/b64_temp.txt" >/dev/null 2>&1; then
    base64 -d "$TMPDIR/b64_temp.txt" > "$FILENAME" 2>/dev/null
  elif base64 -D "$TMPDIR/b64_temp.txt" >/dev/null 2>&1; then
    base64 -D "$TMPDIR/b64_temp.txt" > "$FILENAME" 2>/dev/null
  else
    printf "${RED} Error: no se encuentra un comando base64 compatible.${RESET}\n"
    rm -f "$TMPDIR/b64_temp.txt"
    return 1
  fi

  rm -f "$TMPDIR/b64_temp.txt"

  if [ ! -f "$FILENAME" ] || [ ! -s "$FILENAME" ]; then
    printf "${RED} Error al decodificar Base64 a PNG.${RESET}\n"
    printf "${YELLOW}Respuesta JSON de depuración:${RESET}\n"
    cat "$IMAGE_TMP"
    return 1
  fi

  if [ $ENV_A_SHELL -eq 1 ]; then
    view "$FILENAME" >/dev/null 2>&1
  elif [ $ENV_LINUX_GUI -eq 1 ]; then
    xdg-open "$FILENAME" >/dev/null 2>&1
  elif [ $OS_NAME = "Darwin" ]; then
    open "$FILENAME" >/dev/null 2>&1
  else
    printf "${CYAN}Imagen guardada en: ${RESET}'%s'\n" "$FILENAME"
  fi

  LAST_IMAGE_PATH="$FILENAME"
  LAST_IMAGE_NAME="imagen_${TIMESTAMP}"

  printf "Imagen generada y guardada en: %s\n" "${FILENAME#$HOME}"
  printf "${CYAN}Coste imagen (€):${RESET} %s\n" "$IMAGE_PRICE"
  IMAGEN_GENERATED=1
  return 0
}
#Procesa $TMP y crea $RESPONSE_NORMALIZED con la respuesta formateada (sin caracteres escapados)
procesa_respuesta() {
  if jq -e '.error' "$TMP" > /dev/null 2>&1; then
      jq '.error.code' "$TMP" > "$TMPDIR/error_code.txt"
      sed 's/^"//' "$TMPDIR/error_code.txt" | sed 's/"$//' | head -1 > "$TMPDIR/code.txt"
      read code < "$TMPDIR/code.txt"
      jq '.error.message' "$TMP" > "$TMPDIR/error_message.txt"
      sed 's/^"//' "$TMPDIR/error_message.txt" | sed 's/"$//' | head -1 > "$TMPDIR/message.txt"
      read message < "$TMPDIR/message.txt"
      rm -f "$TMPDIR/error_code.txt" "$TMPDIR/code.txt" "$TMPDIR/error_message.txt" "$TMPDIR/message.txt"
      printf "${RED}Error en peticion a la API (code=%s): %s${RESET}\n" "$code" "$message"
      echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - API error code=$code" >> "$LOG"
      if [ "$code" = "404" ] || echo "$message" | grep -q "not found"; then
        printf "${RED}Modelo no encontrado en esta API/version. Cambia de modelo.${RESET}\n"
      fi
      if [ $DEBUG_MODE -eq 1 ]; then
        printf "${BLUE}[DEBUG] Respuesta de error:${RESET}\n"
        cat "$TMP"
      else
        cat "$TMP"
      fi
    return 1
  fi

  # EXTRAER RESPUESTA SIN -r
  jq '.candidates[0].content.parts[0].text' "$TMP" > "$RESP"

  read RESP_CHECK < "$RESP"
  if [ "$RESP_CHECK" = "null" ]; then
    printf "${RED}Respuesta inválida, se ignora${RESET}\n"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $MODEL - Null response" >> "$LOG"
    return 1
  fi

  sed 's/^"//;s/"$//' "$RESP" > "$TMPDIR/response_raw.txt"

  awk '{
    gsub(/\r/, "");
    # Unescape JSON escapes
    gsub(/\\"/, "\"");
    gsub(/\\\\/, "\\");
    gsub(/\\n/, "\n");
    gsub(/\\t/, "\t");
    gsub(/\\r/, "\r");
    gsub(/\\b/, "\b");
    gsub(/\\f/, "\f");
    print
  }' "$TMPDIR/response_raw.txt" > "$RESPONSE_NORMALIZED"

  rm -f "$TMPDIR/response_raw.txt"
  return 0
}
# Usa $RESPONSE_NORMALIZED para actualizar $CTX con la respuesta formateada (sin caracteres escapados)
actualiza_contexto() {
  jq -Rs '{
    role:"model",
    parts:[{text:(. // "")}]
  }' "$RESPONSE_NORMALIZED" > "$TMP.model"

  # Asegurar que CTX es un array JSON válido
  if ! jq -e 'type=="array"' "$CTX" >/dev/null 2>&1; then
    echo "[WARN] CTX corrupto, reiniciando" >> "$LOG"
    echo "[]" > "$CTX"
  fi

  jq -s '
    (if (.[0] | type) == "array" then .[0] else [] end)
    + [.[1], .[2]]
  ' "$CTX" "$TMP.user" "$TMP.model" > "$CTX.tmp" 2>/dev/null || {
    # fallback si CTX está corrupto
    jq -s '[.[1], .[2]]' "$CTX" "$TMP.user" "$TMP.model" > "$CTX.tmp"
    }

  if jq empty "$CTX.tmp" >/dev/null 2>&1; then
    mv "$CTX.tmp" "$CTX"
  else
    echo "[ERROR] CTX.tmp inválido, no se aplica" >> "$LOG"
  fi

  if jq -e 'type=="array"' "$CTX" >/dev/null 2>&1; then
    if ! jq '.[-30:]' "$CTX" > "$CTX.tmp"; then
      echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - jq falló al reducir contexto" >> "$LOG"
      cp "$CTX" "$CTX.tmp"
    fi
  else
    echo "[ERROR] Contexto vacío, se resetea"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Contexto vacío, se resetea" >> "$LOG"
    echo "[]" > "$CTX.tmp"
  fi
  mv "$CTX.tmp" "$CTX"
}

get_mime_type() {
  FILE="$1"

  case "$FILE" in
    *.md) echo "text/markdown" ;;
    *.txt) echo "text/plain" ;;
    *.json) echo "application/json" ;;
    *.png) echo "image/png" ;;
    *.jpg|*.jpeg) echo "image/jpeg" ;;
    *.pdf) echo "application/pdf" ;;
    *) echo "application/octet-stream" ;;
  esac
}

printf "[ i a d i m e ] ($MODEL)\n"
printf "Escribe tu pregunta o usa los comandos [':leer'|':salir'|...|':ayuda']\n"

while true; do
  IMAGEN_GENERATED=0
  printf "${GREEN}Tu:${RESET}\n"
  read PROMPT || break

  case "$PROMPT" in
    ":salir")
      break
      ;;

    ":reset")
      # Conservar las reglas
      if [ -f "$TMPDIR/system_prompt.txt" ]; then
        cp "$TMPDIR/system_prompt.txt" "$TMPDIR/system_prompt.backup"
      fi
      rm -f "$TMPDIR"/*.json "$TMPDIR"/*.txt
      # Restaurar reglas si existía backup
      if [ -f "$TMPDIR/system_prompt.backup" ]; then
        mv "$TMPDIR/system_prompt.backup" "$TMPDIR/system_prompt.txt"
      fi

      echo "[]" > "$CTX"
      crea_titulo_hilo
      
      echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Contexto reiniciado" >> "$LOG"
      printf "${CYAN}Contexto reiniciado${RESET}\n"
      continue
      ;;

    ":leer")
      if command -v mdv >/dev/null 2>&1; then
        mdv -A "$HILO" | less -r
      elif python3 -c "import rich" >/dev/null 2>&1; then
        export FORCE_COLOR=1 
        python3 -m rich.markdown "$HILO" | less -rFX
      elif [ $ENV_A_SHELL -eq 1 ]; then
        view "$FILENAME" >/dev/null 2>&1
      else
        vim "$HILO"
      fi
      continue
      ;;

    ":leeme")
      if [ $ENV_ISH -eq 1 ]; then
        printf "${RED}El comando ':leeme' no es compatible con este entorno (iSH en iOS sin soporte de voz).${RESET}\n"
        continue
      fi
      if [ $ENV_LINUX_GUI -eq 1 ]; then
        # Si el comando 'say' no existe, pero 'spd-say' sí (Linux)
        if ! command -v say &> /dev/null && command -v spd-say &> /dev/null; then
          alias say='spd-say'
        fi
      fi
      say  < "$RESPONSE_NORMALIZED"
      continue
      ;;

    ":leeme-todo")
      if [ $ENV_ISH -eq 1 ]; then
        printf "${RED}El comando ':leeme-todo' no es compatible con este entorno (iSH en iOS sin soporte de voz).${RESET}\n"
        continue
      fi

      if [ $ENV_LINUX_GUI -eq 1 ]; then
        # Si el comando 'say' no existe, pero 'spd-say' sí (Linux)
        if ! command -v say &> /dev/null && command -v spd-say &> /dev/null; then
          alias say='spd-say'
        fi
      fi
      say < "$HILO"
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
      printf '%s' "$PROMPT" | sed 's/^:imagen[[:space:]]*//' > "$TMPDIR/imagen_prompt.txt"
      read IMAGE_PROMPT < "$TMPDIR/imagen_prompt.txt"
      rm -f "$TMPDIR/imagen_prompt.txt"
      if [ -z "$IMAGE_PROMPT" ]; then
        printf "${CYAN}Uso: :imagen <texto>\n${RESET}"
      else
        generate_imagen "$IMAGE_PROMPT"
      fi
      continue
      ;;
    ":enviar "*)
      printf '%s' "$PROMPT" | sed 's/^:enviar //' > "$TMPDIR/file_rel.txt"
      read FILE_REL < "$TMPDIR/file_rel.txt"
      rm -f "$TMPDIR/file_rel.txt"
      FILE_PATH="$ROOT_PATH/$FILE_REL"

      if [ ! -f "$FILE_PATH" ]; then
        printf "${RED}Archivo ${FILE_REL} no encontrado en ${ROOT_PATH}${RESET}\n"
        continue
      fi

      MIME_TYPE=$(get_mime_type "$FILE_PATH")

      # a-Shell
      if [ $ENV_A_SHELL -eq 1 ]; then
        base64 -e "$FILE_PATH" | tr -d '\n' > "$TMPDIR/file_b64.txt" 2>/dev/null
      # Linux / estándar
      elif base64 "$FILE_PATH" >/dev/null 2>&1; then
        base64 "$FILE_PATH" | tr -d '\n' > "$TMPDIR/file_b64.txt"
      elif base64 < "$FILE_PATH" >/dev/null 2>&1; then
        base64 < "$FILE_PATH" | tr -d '\n' > "$TMPDIR/file_b64.txt"
      elif command -v openssl >/dev/null 2>&1; then
        openssl base64 -in "$FILE_PATH" | tr -d '\n' > "$TMPDIR/file_b64.txt"
      else
        printf "${RED}Error: no se pudo codificar en base64${RESET}\n"
        continue
      fi

      if [ ! -s "$TMPDIR/file_b64.txt" ]; then
        printf "[ERROR]${RED}Base64 vacío${RESET}\n"
        continue
      fi

      FILE_B64=$(cat "$TMPDIR/file_b64.txt")

      jq -n \
        --arg data "$FILE_B64" \
        --arg name "$(basename "$FILE_PATH")" \
        --arg mime "$MIME_TYPE" \
        '{
          role:"user",
          parts:[
            {text:"Archivo enviado:"},
            {
              inline_data:{
                mimeType:$mime,
                data:$data
              }
            }
          ]
        }' > "$TMP.user"

      #Crea TMP.req con el contexto $CTX+ mensaje del usuario (archivo) $TMP.user
      crea_consulta

      printf "${CYAN}Consultando...${RESET}\n"
      [ $DEBUG_MODE -eq 1 ] && echo "[DEBUG] Llamando a API: $API_URL con $TMP.req" >> "$LOG"
      consulta_api "$API_URL" "$TMP.req" > "$TMP"
      
      #Procesa $TMP y crea $RESPONSE_NORMALIZED con la respuesta formateada (sin caracteres escapados)
      if ! procesa_respuesta ; then
        continue
      fi
      # Usa $RESPONSE_NORMALIZED para actualizar $CTX con la respuesta formateada (sin caracteres escapados)
      actualiza_contexto
      
      echo "## Usuario" >> "$HILO"
      echo "[Archivo enviado: $FILE_REL]" >> "$HILO"
      echo "" >> "$HILO"

      echo "## IA ($MODEL)" >> "$HILO"
      cat "$TMPDIR/response_formatted.txt" >> "$HILO"
      echo "" >> "$HILO"

     continue
     ;;

    ":export "*)
      printf '%s' "$PROMPT" | sed 's/^:export //' > "$TMPDIR/export_name.txt"
      read EXPORT_NAME < "$TMPDIR/export_name.txt"
      rm -f "$TMPDIR/export_name.txt"
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
        if [ "$OS_NAME" = "Darwin" ]; then
          sed -i '' "1s/.*/# $EXPORT_NAME/" "$EXPORT_FILE"
        else
          sed -i "1s/.*/# $EXPORT_NAME/" "$EXPORT_FILE"
        fi
        echo "" >> "$EXPORT_FILE"
        echo "> Exportado el: $(date '+%Y-%m-%d %H:%M:%S')" >> "$EXPORT_FILE"
      # Exportar contexto tmp moviéndolo a Nombre_tmp para preservar estado completo
      EXPORT_TMP_DIR="$ROOT_PATH/${EXPORT_NAME}_tmp"
      SYSTEM_PROMPT_TMP_BACKUP=""
      if [ -f "$TMPDIR/system_prompt.txt" ]; then
        SYSTEM_PROMPT_TMP_BACKUP="$ROOT_PATH/.system_prompt_backup"
        cp "$TMPDIR/system_prompt.txt" "$SYSTEM_PROMPT_TMP_BACKUP"
      fi

      if [ -d "$TMPDIR" ]; then
        if [ -d "$EXPORT_TMP_DIR" ]; then
          printf "${CYAN}El directorio de contexto '$EXPORT_NAME_tmp' ya existe. ¿Sobrescribir? (s/n): ${RESET}"
          read CONFIRM_TMP
          if [ "$CONFIRM_TMP" != "s" ] && [ "$CONFIRM_TMP" != "S" ]; then
            printf "${CYAN}Exportación de tmp cancelada.\n${RESET}"
          else
            rm -rf "$EXPORT_TMP_DIR"
            cp -r "$TMPDIR" "$EXPORT_TMP_DIR"
            rm -rf "$TMPDIR"
            mkdir -p "$TMPDIR"
            crea_titulo_hilo
          fi
        else
          cp -r "$TMPDIR" "$EXPORT_TMP_DIR"
          rm -rf "$TMPDIR"
          mkdir -p "$TMPDIR"
          crea_titulo_hilo
        fi
      fi

      if [ -n "$SYSTEM_PROMPT_TMP_BACKUP" ] && [ -f "$SYSTEM_PROMPT_TMP_BACKUP" ]; then
        mv "$SYSTEM_PROMPT_TMP_BACKUP" "$TMPDIR/system_prompt.txt"
      fi
      # Reiniciar el contexto actual para empezar nueva conversación
      echo "[]" > "$CTX"
      printf "${GREEN}Conversación exportada: '$EXPORT_NAME'.\n Contexto reiniciado${RESET}\n"
      date '+%Y-%m-%d %H:%M:%S' > "$TMPDIR/ts_export.txt"
      read TS_EXPORT < "$TMPDIR/ts_export.txt"
      rm -f "$TMPDIR/ts_export.txt"
      echo "[INFO] $TS_EXPORT - Conversación exportada: $EXPORT_NAME. Contexto reiniciado" >> "$LOG"
      fi
      continue
      ;;

    ":import "*)
      printf '%s' "$PROMPT" | sed 's/^:import //' > "$TMPDIR/import_name.txt"
      read IMPORT_NAME < "$TMPDIR/import_name.txt"
      rm -f "$TMPDIR/import_name.txt"
      if [ -z "$IMPORT_NAME" ]; then
        printf "${CYAN}Uso: :import NOMBRE\n${RESET}"
      else
        IMPORT_FILE="$ROOT_PATH/${IMPORT_NAME}.md"
        if [ ! -f "$IMPORT_FILE" ]; then
          printf "${RED}El archivo '$IMPORT_NAME.md' no existe.\n${RESET}"
        else
          printf "${YELLOW}Advertencia:${RESET} ${CYAN}Al importar se borrará el contexto actual. ¿Continuar? (s/n): ${RESET}"
          read CONFIRM_IMPORT
          if [ "$CONFIRM_IMPORT" != "s" ] && [ "$CONFIRM_IMPORT" != "S" ]; then
            printf "${CYAN}Importación cancelada.\n${RESET}"
            continue
          fi
          cp "$IMPORT_FILE" "$HILO"
          printf "${GREEN}Conversación importada : '$IMPORT_NAME'\n${RESET}"
          date '+%Y-%m-%d %H:%M:%S' > "$TMPDIR/ts_import.txt"
          read TS_IMPORT < "$TMPDIR/ts_import.txt"
          rm -f "$TMPDIR/ts_import.txt"
          echo "[INFO] $TS_IMPORT - Conversación importada: $IMPORT_NAME" >> "$LOG"
          # Restaurar contexto tmp desde Nombre_tmp si existe
          IMPORT_TMP_DIR="$ROOT_PATH/${IMPORT_NAME}_tmp"
          if [ -d "$IMPORT_TMP_DIR" ]; then
            rm -rf "$TMPDIR"
            cp -r "$IMPORT_TMP_DIR" "$TMPDIR"

            if [ ! -f "$CTX" ]; then
              printf "${CYAN}Advertencia: no se encontró contexto.${RESET}\n"
              echo "[]" > "$CTX"
            fi
          else
            # Si no existe tmp específico, guardar reglas actuales antes de reiniciar tmp
            IMPORT_RULES_BACKUP="$ROOT_PATH/.import_rules_backup"
            if [ -f "$TMPDIR/system_prompt.txt" ]; then
              cp "$TMPDIR/system_prompt.txt" "$IMPORT_RULES_BACKUP"
            fi
            rm -rf "$TMPDIR"
            mkdir -p "$TMPDIR"
            if [ -f "$IMPORT_RULES_BACKUP" ]; then
              mv "$IMPORT_RULES_BACKUP" "$TMPDIR/system_prompt.txt"
            fi
            # y reiniciar contexto (no hay contexto guardado)
            echo "[]" > "$CTX"
            printf "${CYAN}Advertencia: no se encontró carpeta %s_tmp, se inicia sin contexto guardado.${RESET}\n" "$IMPORT_NAME"
          fi
        fi
      fi
      continue
      ;;

    ":exportHTML" | ":exportHTML "*)
      # Parse optional title
      HTML_TITLE=""
      if printf '%s' "$PROMPT" | grep -q '^:exportHTML[[:space:]]'; then
        printf '%s' "$PROMPT" | sed 's/^:exportHTML[[:space:]]*//' > "$TMPDIR/export_html_title.txt"
        read HTML_TITLE < "$TMPDIR/export_html_title.txt"
        rm -f "$TMPDIR/export_html_title.txt"
      fi

      # Verificar dependencias
      if ! command -v markdown >/dev/null 2>&1 && ! python3 -c "import markdown" >/dev/null 2>&1; then
        printf "${RED}Error: 'markdown' no está instalado.${RESET}\n"
        printf "${CYAN}Instálalo con: pip install markdown${RESET}\n"
        continue
      fi

      if ! python3 -c "import http.server" >/dev/null 2>&1; then
        printf "${RED}Error: No se puede usar http.server de Python.${RESET}\n"
        continue
      fi

      if [ -n "$HTML_TITLE" ]; then
        set_hilo_title "$HTML_TITLE"
      fi
      HTML_TITLE="${HTML_TITLE:-$HILO_TITLE}"

      HTML_DIR="$ROOT_PATH"
      HTML_FILE="$HTML_DIR/index.html"

      mkdir -p "$HTML_DIR"

      # Crear archivo HTML con estructura completa
      
      echo '<!DOCTYPE html>' > "$HTML_FILE"
      echo '<html lang="es">' >> "$HTML_FILE"
      echo '<head>' >> "$HTML_FILE"
      echo '<meta charset="UTF-8">' >> "$HTML_FILE"
      echo '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'>> "$HTML_FILE"
      echo '<meta name="viewport" content="width=device-width, initial-scale=1.0">'>> "$HTML_FILE"
      printf '<title>%s</title>\n' "$HTML_TITLE" >> "$HTML_FILE"
      echo '<style>' >> "$HTML_FILE"
      echo 'body { font-family: sans-serif; margin: 20px; line-height: 1.6; max-width: 900px; margin: 0 auto; }' >> "$HTML_FILE"
      echo 'code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }' >> "$HTML_FILE"
      echo 'pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }' >> "$HTML_FILE"
      echo 'h1, h2, h3 { color: #333; }' >> "$HTML_FILE"
      echo 'blockquote { border-left: 4px solid #ddd; padding-left: 15px; margin-left: 0; color: #666; }' >> "$HTML_FILE"
      echo 'img { max-width: 100%; height: auto; }' >> "$HTML_FILE"
      echo '</style>' >> "$HTML_FILE"
      echo '</head>' >> "$HTML_FILE"
      echo '<body>' >> "$HTML_FILE"
      

      # Crear archivo temporal con fecha de exportación
      TEMP_HILO="$TMPDIR/temp_export.md"
      cp "$HILO" "$TEMP_HILO"
      echo "" >> "$TEMP_HILO"
      echo "> Exportado el: $(date '+%Y-%m-%d %H:%M:%S')" >> "$TEMP_HILO"

      # Convertir markdown a HTML
      if command -v markdown >/dev/null 2>&1; then
        markdown "$TEMP_HILO" >> "$HTML_FILE"
      else
        python3 -m markdown "$TEMP_HILO" >> "$HTML_FILE"
      fi

      rm -f "$TEMP_HILO"

      # Cerrar etiquetas HTML
      echo '</body>' >> "$HTML_FILE"
      echo '</html>' >> "$HTML_FILE"

      printf "${GREEN}HTML generado: $HTML_FILE${RESET}\n"
      printf "${CYAN}Para servir este HTML localmente usa:${RESET}\n"
      printf "${BLACK}  cd %s && python3 -m http.server 3000${RESET}\n" "$HTML_DIR"
      printf "${CYAN}Luego abre en el navegador: http://localhost:3000${RESET}\n"
      printf "${CYAN}Si quieres, añade un alias en tu perfil (.zshrc, .bashrc o ~/Documents/.profile):${RESET}\n"
      printf "${BLACK}  alias iadime-serve='cd %s && python3 -m http.server 3000'${RESET}\n" "$HTML_DIR"
      
      echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - HTML exportado a $HTML_FILE" >> "$LOG"
      continue
      ;;

    ":list-models")
      printf "${CYAN}Modelos de Imagen y Gemini disponibles:${RESET}\n"
      MODELS_JSON=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY")
      if echo "$MODELS_JSON" | grep -q 'error'; then
        printf "${RED}Error al obtener lista de modelos: ${RESET}\n"
        echo "$MODELS_JSON" | jq '.error.message' > "$TMPDIR/models_error.txt"
        sed 's/^"//' "$TMPDIR/models_error.txt" | sed 's/"$//' | head -1 > "$TMPDIR/models_message.txt"
        read message < "$TMPDIR/models_message.txt"
        echo "$message"
        rm -f "$TMPDIR/models_error.txt" "$TMPDIR/models_message.txt"
      else
        echo "$MODELS_JSON" | jq '.models[] | select(.name | startswith("models/imagen") or startswith("models/gemini")) | .name' > "$TMPDIR/models_list.txt"
        sed 's/^"//' "$TMPDIR/models_list.txt" | sed 's/"$//' | sed 's/models\///' > "$TMPDIR/models_clean.txt"
        cat "$TMPDIR/models_clean.txt" || printf "${RED}No se pudieron parsear los modelos. jq no disponible o respuesta inválida.${RESET}\n"
        rm -f "$TMPDIR/models_list.txt" "$TMPDIR/models_clean.txt"
      fi
      continue
      ;;

    ":list")
      printf "${CYAN}Conversaciones disponibles:${RESET}\n"
      ls "$ROOT_PATH/" | grep '\.md$' | sed 's/\.md$//'  
      continue
      ;;

    ":model"* )
      printf '%s' "$PROMPT" | sed 's/^:model //' > "$TMPDIR/new_model.txt"
      read NEW_MODEL < "$TMPDIR/new_model.txt"
      rm -f "$TMPDIR/new_model.txt"
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

    ":reglas")
      printf "${GREEN}%s${RESET}\n" "$SYSTEM_PROMPT"
      printf "${CYAN}Para actualizarlas usa: :reglas <intrucciones para el modelo>\n${RESET}"
      continue
      ;;

    ":reglas "*)
      printf '%s' "$PROMPT" | sed 's/^:reglas[[:space:]]*//' > "$TMPDIR/system_prompt.txt"
      SYSTEM_PROMPT=$(cat "$TMPDIR/system_prompt.txt") 
      if [ -z "$SYSTEM_PROMPT" ]; then
        printf "${CYAN}Uso: :reglas <intrucciones para el modelo>\n${RESET}"
      else
        printf "${GREEN} Instrucciones para el model actualizadas\n${RESET}"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') Instrucciones para el model actualizadas : $SYSTEM_PROMPT" >> "$LOG"
        echo "" >> "$HILO"
        echo "> Cambio de reglas el $(date '+%Y-%m-%d %H:%M:%S'): $SYSTEM_PROMPT" >> "$HILO"
      fi
      continue
      ;;

      ":reglas-reset")
      SYSTEM_PROMPT="$DEFAULT_SYSTEM_PROMPT"
      printf "${GREEN}%s${RESET}\n" "$SYSTEM_PROMPT" > "$TMPDIR/system_prompt.txt"
      printf "${GREEN}Instrucciones para el modelo reiniciadas a valores por defecto\n${RESET}"
      echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') Instrucciones para el modelo reiniciadas a valores por defecto" >> "$LOG"
      echo "" >> "$HILO"
      echo "> Reglas reiniciadas el $(date '+%Y-%m-%d %H:%M:%S'): $SYSTEM_PROMPT" >> "$HILO"
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
      echo "  ':leer'           - Leer la conversación actual (usa q para salir del modo lectura)"
      echo "  ':imagen <texto>' - Generar imagen con el texto dado"
      echo "  ':enviar <ruta>'   - Enviar archivo (ruta relativa a ~${ROOT_PATH#$HOME})"
      echo "  ':clear'          - Limpiar pantalla"
      echo ""
      echo "  ':export TITULO'  - Exportar conversación"
      echo "  ':import TITULO'  - Importar conversación"
      echo "  ':exportHTML [TITULO]' - Exportar conversación a HTML (requiere markdown)"
      echo "  ':list'           - Listar conversaciones"
      echo ""
      echo "  ':reglas'         - Mostrar reglas actuales"
      echo "  ':reglas-reset'   - Reiniciar reglas a valores por defecto"
      echo "  ':reglas NUEVAS_REGLAS' - Actualizar reglas"
      echo "  ':list-models'    - Lista modelos disponibles"
      echo "  ':model pro/flash' - Cambiar modelo"
      echo "  ':tokens'         - Mostrar tokens acumulados y coste estimado"
      echo ""
      echo "  ':salir'          - Salir del programa"
      echo "  ':reset'          - Reiniciar contexto"
      echo "  ':debug'          - Alternar modo debug y validar petición"
      echo "  ':ayuda'          - Mostrar esta ayuda"
      echo ""
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

  #Crea TMP.req con el contexto $CTX + mensaje del usuario (archivo) $TMP.user
  crea_consulta

  if ! jq empty "$TMP.req" >/dev/null 2>&1; then
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Petición JSON no validada" >> "$LOG"
    cat "$TMP.req" >> "$LOG"
    continue
  fi

  echo "## Usuario" >> "$HILO"
  echo "$PROMPT" >> "$HILO"
  echo "" >> "$HILO"
  
  printf "${CYAN}Consultando...${RESET}\n"
  [ $DEBUG_MODE -eq 1 ] && echo "[DEBUG] Llamando a API: $API_URL con $TMP.req" >> "$LOG"
  consulta_api "$API_URL" "$TMP.req" > "$TMP"
  

  #Procesa $TMP y crea $RESPONSE_NORMALIZED con la respuesta formateada (sin caracteres escapados)
  procesa_respuesta || continue

  IMAGE_PATH=""
  IMAGE_NAME=""
  IMAGE_PROMPT_CLEAN=""

  if grep -q "\[IMAGEN_PROMPT\]" "$RESPONSE_NORMALIZED"; then

    # Extraer prompt
    awk 'BEGIN{RS="[IMAGEN_PROMPT]"; FS="[/IMAGEN_PROMPT]"} NR==2 {print $1; exit}' "$RESPONSE_NORMALIZED" > "$TMPDIR/image_prompt.txt"
    read IMAGE_PROMPT < "$TMPDIR/image_prompt.txt"
    rm -f "$TMPDIR/image_prompt.txt"

    # Limpiar respuesta (quitar bloque imagen)
    awk 'BEGIN{inimg=0}
    /\[IMAGEN_PROMPT\]/ { inimg=1; next }
    /\[\/IMAGEN_PROMPT\]/ { inimg=0; next }
    !inimg { print }
    ' "$RESPONSE_NORMALIZED" > "$TMPDIR/response_clean.txt"
    mv "$TMPDIR/response_clean.txt" "$RESPONSE_NORMALIZED"

    # Normalizar prompt (por si hay \n u otros caracteres escapados)
    printf '%s' "$IMAGE_PROMPT" | awk '{gsub(/\\n/, "\n")}1' > "$TMPDIR/image_prompt_clean.txt"
    read IMAGE_PROMPT_CLEAN < "$TMPDIR/image_prompt_clean.txt"
    rm -f "$TMPDIR/image_prompt_clean.txt"

    # Generar imagen
    generate_imagen "$IMAGE_PROMPT_CLEAN"

    IMAGE_PATH="$LAST_IMAGE_PATH"
    IMAGE_NAME="$LAST_IMAGE_NAME"
  fi

  cat "$RESPONSE_NORMALIZED"
  cat "$RESPONSE_NORMALIZED" > "$RESP.clean"

  # Usa $RESPONSE_NORMALIZED para actualizar $CTX con la respuesta formateada (sin caracteres escapados)
  actualiza_contexto

  # Obtener uso de tokens y actualizar total acumulado
  printf "${CYAN}Uso:${RESET}\n"

  jq '.usageMetadata.totalTokenCount // 0' "$TMP" > "$RESP.tokens"
  cat "$RESP.tokens"

  read TOKENS_LINE < "$RESP.tokens"
  case "$TOKENS_LINE" in
  	''|null) TOKENS_LINE=0 ;;
  esac

  TOTAL_TOKENS=`expr $TOTAL_TOKENS + $TOKENS_LINE`
  printf "${BLUE}Total acumulado:${RESET}\n"
  echo "$TOTAL_TOKENS"

  echo "$TOTAL_TOKENS * $TOKEN_PRICE" > "$RESP.calc"
  bc < "$RESP.calc" > "$RESP.price"

  printf "${RED}Coste estimado (€):${RESET}\n"
  cat "$RESP.price"

  printf "${BLUE}--------------------------------${RESET}\n"

  
  echo "## IA ($MODEL)" >> "$HILO"
  cat "$RESPONSE_NORMALIZED" >> "$HILO"

  if [ $IMAGEN_GENERATED -eq 1 ]; then
    echo "" >> "$HILO"
    echo "![${IMAGE_NAME}](./${IMAGES_DIR}/${IMAGE_NAME}.png)" >> "$HILO"
    echo "" >> "$HILO"
    echo "> $IMAGE_PROMPT_CLEAN" >> "$HILO"
    echo "" >> "$HILO"
    echo "**Coste imagen (€):** $IMAGE_PRICE" >> "$HILO"
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

