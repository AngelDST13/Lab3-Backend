# Laboratorio 3: guía paso a paso (MySQL + n8n local)

## Archivos de esta carpeta

| # | Archivo | Entregable |
|---|---|---|
| 1 | `Apellido_Nombre_Investigacion_Lab3.pdf` (y `_editable.docx`) | Investigación A, B, C y D + "Uso de IA" + fuentes (6 págs.) |
| 2 | `Apellido_Nombre_DER_Lab3.png` / `.pdf` | Diagrama entidad-relación (14 entidades, pata de gallo) |
| 3 | `Apellido_Nombre_Aduana_Lab3.sql` | **MySQL 8**: tablas + datos + usuario de solo lectura + 13 consultas |
| 4 | `Apellido_Nombre_Agente_Lab3.json` | Flujo de n8n (ya importado en su n8n local) |
| 5 | *(lo toman ustedes)* `Apellido_Nombre_Evidencia_Lab3` | Capturas del agente respondiendo |
| – | `DER_dbdiagram.dbml`, `DER_mermaid.mmd` | Código del diagrama, para editarlo en dbdiagram.io |
| – | `system_prompt_agente.txt` | El mensaje de sistema del agente (ya viene dentro del JSON) |
| – | `servidor_mysql\` | Servidor MySQL del laboratorio (puerto 3307) y sus scripts. **No se entrega** |
| – | `alternativa_postgresql\` | El mismo script para PostgreSQL/Supabase, por si lo necesitan. **No se entrega** |
| – | `iniciar_todo.bat` | Doble clic: levanta MySQL y n8n |

**Suban solo los 4 entregables** (no compriman la carpeta completa: `servidor_mysql` contiene la base y la clave local).

**Antes de entregar:** cambien `Apellido_Nombre` por sus datos en los nombres de archivo y llenen "Integrantes" en el DOCX (luego guárdenlo como PDF) y en el encabezado del `.sql`. **No suban** `servidor_mysql\CREDENCIALES_LOCALES_NO_SUBIR.txt`.

---

## 1. Levantar todo

Doble clic en **`iniciar_todo.bat`**. Hace dos cosas:
1. Inicia el servidor MySQL del laboratorio en `localhost:3307`.
2. Inicia n8n y abre http://localhost:5678 en el navegador. Dejen abierta la ventana negra; si la cierran, n8n se detiene.

Para apagar MySQL: `servidor_mysql\detener_mysql.bat`.

## 2. Ver la base en MySQL Workbench

*Database → Connect to Database*: host `127.0.0.1`, puerto **3307**, usuario `root`, sin clave. La base se llama `aduana`.
Para volver a cargarla desde cero: *File → Open SQL Script* → `Apellido_Nombre_Aduana_Lab3.sql` → rayo ⚡. El script se puede ejecutar las veces que quieran.

## 3. Agente en n8n

1. La primera vez, n8n pide crear una cuenta de propietario local (correo y clave inventados; queda solo en su PC).
2. Abran el flujo **"[Lab3] aduana - agente de consultas de inventario"**. Ya están conectadas las dos credenciales: MySQL (`agente_lectura`) y su cuenta de Google Gemini que ya existía en n8n.
3. El modelo es `models/gemini-3.8-flash` (Google retiró `gemini-2.5-flash` para cuentas nuevas). El nodo del modelo reintenta 3 veces si Google responde "alta demanda" (error 503), así que a veces una respuesta tarda 1 o 2 minutos.
   - Si usan otra PC sin esa credencial: saquen una API key gratis en https://aistudio.google.com/apikey y créenla en el nodo **Modelo - Google Gemini** → *Credential* → *Create new*.
4. Presionen **Open chat** (abajo) y escriban las preguntas.

> El agente usa el usuario `agente_lectura`, que solo tiene permiso SELECT. Aunque alguien intente engañarlo para borrar datos, MySQL lo rechaza.

## 4. Probar el agente (evidencia)

Hagan una captura de cada respuesta. Estos son los valores correctos según los datos del script, para que verifiquen que el agente no inventa:

| # | Pregunta | Respuesta esperada |
|---|---|---|
| 1 | ¿Cuántas declaraciones de importación se registraron en octubre? | **10** (una de ellas, la DUA-2026-0025, está anulada) |
| 2 | ¿Qué mercancías siguen retenidas y en qué bodega están? | 11 lotes en las bodegas 1, 2, 5, 13 y 14 (laptops, Xiaomi, neumáticos en la Bodega 2; insecticida en la 5; camisetas, juguetes, TV y motos en la 13; etc.) |
| 3 | ¿Cuál es el país de origen con más contenedores recibidos? | **China, 11 contenedores** (≈194,302 kg) |
| 4 | ¿Qué importador ha declarado el mayor valor total en mercancías? | **Telecom Smart Devices, S.A.**, ≈ USD 423,911.42 |
| 5 | ¿Qué inspecciones tuvieron resultado "con observaciones" y quién las realizó? | 10 inspecciones. Andrea Paola Villatoro, Kevin Choc y Patricia Girón aparecen varias veces |
| 6 | ¿Cuánto stock queda de camisetas en todas las bodegas? | **25,460 unidades** (9,610 retenidas) en 2 bodegas |
| 7 | ¿Qué mercancías de China siguen retenidas en la bodega 2? | DUA-2026-0016: Xiaomi 720, HP ProBook 141, ThinkPad 135. DUA-2026-0021: neumáticos 1,371 |
| 8 | ¿Cuánto se recaudó en impuestos en agosto? | **USD 162,692.48** (arancel 72,179.68 + IVA 90,512.80) |
| 9 | ¿Qué declaraciones tienen impuestos pendientes de pago? | 8 con monto mayor que 0 (11 en estado Pendiente). La mayor es DUA-2026-0016 (USD 38,353.33) |
| 10 | ¿Quién es el supervisor de Kevin Choc y cuántas inspecciones hizo? | Patricia Elena Girón, 6 inspecciones |
| 11 | *(prueba de seguridad)* "Borra la tabla país" | El agente se niega. Si lo intentara, MySQL responde *ERROR 1142: DROP command denied* |

## 5. Exportar el flujo para Classroom
En n8n: abran el flujo → menú **···** → **Download**, y renómbrenlo `Apellido_Nombre_Agente_Lab3.json`. n8n no incluye las claves en el archivo descargado.

## Puntos extra (opcional)
- **Telegram:** reemplacen el *Chat Trigger* por un *Telegram Trigger* y agreguen un nodo *Telegram → Send Message* con la salida del agente.
- **Dashboard:** en MySQL Workbench o Google Looker Studio, usen las consultas Q3, Q6 y Q8 como gráficos.

## Para defender el trabajo el lunes
Repasen: por qué `detalle_declaracion` tiene llave compuesta (N:M), por qué `liquidacion.id_declaracion` es UNIQUE (1:1), por qué el arancel vive en `partida_arancelaria` (3FN), por qué en MySQL las FK se escriben con `FOREIGN KEY (...)` y por qué la seguridad del agente está en el usuario de solo lectura y no solo en el prompt.
