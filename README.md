![shell](https://img.shields.io/badge/shell-sh-blue)
![license](https://img.shields.io/badge/license-GPLv2-green)
![status](https://img.shields.io/badge/status-personal--project-orange)

# [ i a d i m e ]

CLI ligera para usar modelos de IA (Gemini) desde terminal, ideada para un  **iPad obsoleto con a-shell**.

## Características

- Chat interactivo en terminal
- Contexto persistente entre preguntas
- Exportación e importación de conversaciones
- Historial en formato Markdown
- Cálculo de tokens y coste estimado cada peticion a la API
- Colores en consola
- Compatible con a-shell y facilmente adaptable a shells Linux básicos

## Limitaciones y Diseño

`a-shell` es una aplicación para iOS que simula un entorno Unix limitado (sandboxing, permisos restringidos, compatibilidad parcial con comandos nativos de Linux, command subsitution limitado).

Este proyecto está diseñado específicamente para dispositivos obsoletos como el iPad Mini 4 (lanzado en 2015), que no admiten la aplicación oficial de ChatGPT debido a requisitos de iOS más actuales en la AppStore. Tampoco sus versiones de Safari o Chrome pueden abrir la interfaz web de ChatGPT.

Sin embargo, gracias a este script y a a-shell, el dispositivo sigue siendo una herramienta válida y funcional para interactuar con modelos de IA, extendiendo su utilidad mucho más allá de su obsolescencia.

## Requisitos

Mínimos:

- `sh`
- `curl`
- `jq`
- `sed`
- `awk`

Opcional:

- `mdv` → (requiere python3) :leer conversacion en Markdown
- `git` → para descargar y actualizar este proyecto

>`a-shell` usa `pkg install git` para instalar.


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

Tu:
:leer
```

## Instalación

1. Descarga el proyecto o clónalo

   ```sh
   git clone https://github.com/Joselon/iadime.git
   ```

   >`a-Shell` usa **pickFolder** que permite seleccionar una carpeta de `Archivos` para poder copiar archivos con `cp` desde/a ~/Documents/

1. Copiar `iadime.sh` a la carpeta bin(crear si no existe) y darle un nombre corto como `iadime`

   ```sh
   cp iadime.sh ~/Documents/bin/iadime
   ```

1. Dar permiso de ejecucion al script

   ```sh
   chmod +x iadime
   ```

1. Necesitas:

   1. Una `API_KEY` de un proyecto (puede ser gratuito) en google [aistudio](https://aistudio.google.com/api-keys)
   1. Crear/añadir al fichero `~/Documents/.profile` en `a-Shell`(en terminales comunes `.bashrc` o `.zshrc`) las siguientes lineas:

   ```sh
   export GEMINI_API_KEY="tu_api_key"
   export PATH="$HOME/Documents/bin:$PATH"
   ```

>**Nota:** En `a-Shell` solo hay permiso de escritura en la carpeta Documents, por lo que todas las rutas lo incluyen. En otros dispositivos modificar `ROOT_PATH`

- Para mejorar la lectura, se recomienda tener instalado `mdv` y/o usar aplicaciones externas como `Obsidian`

   ```sh
   # Comprobar si esta instalado
   mdv --version

   # Instalar
   pip install mdv
   ```

   >`pipx` Si `pip` da algun problema en otras terminales

   El comando `:leer` abre la conversación actual con `mdv` a traves de `less` por lo que se pueden usar comandos como:

  - `G` Ir al final del fichero
  - `q` Salir de la lectura

- Para abrir las imagenes desde a-Shell usa `view imagen01.png`.
- Actualiza con `git pull` si clonaste el proyecto y copia de nuevo el script a bin.

## Uso

Se puede usar con el modelo flash-latest y el pro-latest de gemini.  Por defecto se inicia con flash. Es facilmente adaptable a otros proveedores como openAI, cambiando la url y el json.

```sh
iadime
# Inicia o continua la converacion actual con la carpeta tmp como contexto

iadime -m pro
iadime -m flash
# Inicia con uno de los modelos pro o flash
```

Puedes mantener una conversacion con el modelo de IA seleccionado o ejecutar los comandos que necesites.

Se muestra al final de cada respuesta el consumo en tokens y un coste estimado basado en el modelo flash.

### Comandos

#### Generales

- `:salir` → salir
- `:reset` → limpiar contexto
- `:clear` → limpiar pantalla
- `:imagen <texto>` → Generar imagen con el texto dado ( usa misma API key y llamadas a Imagen 4.0)
- `:envia <ruta>`   → Enviar archivo (ruta relativa a ~/ROOT_PATH) * Por defecto `~/Documents/ConversacionesGemini/`
- `:list-models` → Lista modelos de imagen disponibles en la API
- `:ayuda` → muestra todos los comandos disponibles
- `:debug` → Alternar modo debug y validar petición
- `:tokens` → Muestra el consumo anterior de tokens

#### Conversaciones

- `:export NOMBRE` → guarda conversación
- `:import NOMBRE` → carga conversación
- `:list` → lista conversaciones disponibles

#### Modelo

- `:model pro`
- `:model flash`


#### Lectura

- `:leer` → abre la conversacion actual con mdv (si está instalado)
            al abrirse con `less -r` se puede navegar al final de la conversacion pulsando `G` mayuscula.

## Estructura

```sh
~/Documents/ConversacionesGemini/
├── actual.md
├── tmp/
├── *.md
└── *_tmp/
```

## Colaboraciones

Son bienvenidas colaboraciones para mejoras y propuestas por pull request.

## Autor

Jose Navarro Osta. 2026.
