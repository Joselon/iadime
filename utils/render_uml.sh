#!/bin/sh

if [ -z "$1" ]; then
    echo "Uso: sh render_uml.sh archivo.mmd"
    exit 1
fi

# Leemos el archivo y lo codificamos en Base64 seguro para URL usando Python nativo de a-shell
B64=$(python3 -c "import base64, sys; print(base64.urlsafe_b64encode(open('$1', 'rb').read()).decode('utf-8').replace('=', ''))")

OS_NAME=$(uname)
OUTPUT_IMG="${1%.*}.png"
DESTINO="imagenes/$OUTPUT_IMG"

echo "Enviando diagrama a la API de Mermaid..."
curl -s "https://mermaid.ink/img/$B64" -o "$DESTINO"

if [ -f "$DESTINO" ] && [ -s "$DESTINO" ]; then
    echo "¡Éxito! Imagen guardada como: $DESTINO"
    echo "Ejecuta el siguiente comando para añadir a la conversación actual:"
    echo "echo '![$OUTPUT_IMG](./$DESTINO)' >> actual.md"
    # Abre la imagen en el visor nativo de iOS desde a-shell
    if  [ "$OS_NAME" = "Darwin" ] && [ "$SHELL" = "/bin/sh" ]; then
        view "$DESTINO"
    else
        open "$DESTINO"
    fi
    
else
    echo "Error al generar el diagrama. Verifique la sintaxis."
fi

