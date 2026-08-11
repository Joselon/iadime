# iadime web

## Ejecutar

```bash
chmod +x iadime-web.sh
./iadime-web.sh start
```

También puedes arrancarlo directamente con:

```bash
python3 server.py
```

Luego abre http://127.0.0.1:8080 en el navegador.

Para detenerlo:

```bash
./iadime-web.sh stop
```

## Logs

- El lanzador web escribe el log en `logs/iadime-web.log`.
- Cada arranque, parada y petición HTTP del front queda registrada.
- Puedes ajustar el nivel con `IADIME_LOG_LEVEL`, por ejemplo `IADIME_LOG_LEVEL=DEBUG ./iadime-web.sh start`.

## Archivos estáticos (output e imagenes)

- El servidor expone la carpeta `output` en `/output`.
- El servidor expone la carpeta `imagenes` en `/imagenes`.
- Puedes abrir `http://127.0.0.1:8080/output/` o `http://127.0.0.1:8080/imagenes/` para ver un listado de ficheros.
- También puedes abrir archivos directos, por ejemplo: `/output/mi-imagen.png` o `/imagenes/diagrama.png`.

## Variables de entorno

- `PROVIDER=openai` o `PROVIDER=gemini`
- `OPENAI_API_KEY` o `GEMINI_API_KEY`
- `OPENAI_MODEL` / `GEMINI_MODEL`
- `PORT` para cambiar el puerto (por defecto 8080)
- `HOST` para cambiar la interfaz de escucha (por defecto `127.0.0.1`)
- `IADIME_LOG_LEVEL` para controlar la verbosidad del log
