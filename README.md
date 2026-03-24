![shell](https://img.shields.io/badge/shell-sh-blue)
![platform](https://img.shields.io/badge/platform-iPadOS-lightgrey)
![license](https://img.shields.io/badge/license-GPLv2-green)
![status](https://img.shields.io/badge/status-personal--project-orange)

# [ i a d i m e ]

CLI ligera para usar modelos de IA (Gemini) desde terminal, ideada para un  **iPad  obsoleto con a-shell**.

## Características

- Chat interactivo en terminal
- Contexto persistente entre preguntas
- Exportación e importación de conversaciones
- Historial en formato Markdown
- Cálculo de tokens y coste estimado cada peticion a la API
- Colores en consola
- Compatible con a-shell y shells Linux básicos

## Requisitos

Mínimos:

- `sh`
- `curl`
- `jq`
- `sed`
- `awk`

Opcional:

- `frogmouth` → visualización bonita de Markdown

## Ejemplo de uso

```sh
[ i a d i m e ] (gemini-flash-latest)

Tu:
Hola

IA:
¡Hola! ¿En qué puedo ayudarte?

Uso:
120 tokens

Total acumulado:
350

Coste estimado (€):
0.0007
````

## Instalación

Necesitas:

1. Una `API_KEY` de un proyecto (puede ser gratuito) en google [aistudio](https://aistudio.google.com/api-keys)

1. Crear/añadir al fichero ~/Documents/.profile las siguientes lineas:

```sh
export GEMINI_API_KEY="tu_api_key"
export OPENAI_API_KEY="tu_api_key"
export PATH="$HOME/Documents/bin:$PATH"
```

1. Dar permiso de ejecucion al script

```sh
chmod +x iadime.sh
```

1. Mover a la carpeta bin y darle un nombre corto: `~/Documents/bin/iadime`

## Uso

Actualmente se puede usar con el modelo flash-latest y el pro-latest de gemini.  Por defecto se inicia con flash.

```sh
iadime
iadime -m pro
iadime -m flash
```

Se muestra al final de cada respuesta el consumo en tokens y un coste estimado basado en el modelo flash.

### Comandos

#### Generales

- `:salir` → salir
- `:reset` → limpiar contexto
- `:clear` → limpiar pantalla
- `:ayuda` → muestra todos los comandos disponibles

#### Conversaciones

- `:export NOMBRE` → guarda conversación
- `:import NOMBRE` → carga conversación
- `:list` → lista conversaciones disponibles

#### Modelo

- `:model pro`
- `:model flash`

#### Lectura

- `:leer` → abre la conversacion actual con frogmouth (si está instalado)

## Estructura

```
~/Documents/ConversacionesGemini/
├── actual.md
├── tmp/
├── *.md
└── *_tmp/
```

## Colaboraciones

Son bienvenidas colaboraciones de la comunidad para mejoras y propuestas por pull request.

## Autor

Jose Navarro Osta. 2026.
 
