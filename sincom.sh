#!/bin/sh

# 1. Comprobar si has puesto un nombre de archivo
if [ -z "$1" ]
then
	echo \"❌ Error: No has indicado ningún archivo.\"
	echo \"Uso: mdlook <archivo.md>\"
	exit 1
fi

# 2. Comprobar si el archivo realmente existe en esta carpeta
if [ ! -f "$1" ]
then

	echo \"❌ Error: No se encuentra el archivo '$1' en esta carpeta.\"
	echo \"Asegúrate de estar en el directorio correcto usando el comando 'ls'.\"
	exit 1
fi
sed "s/['\\\"]//g" "$1" | pbcopy
