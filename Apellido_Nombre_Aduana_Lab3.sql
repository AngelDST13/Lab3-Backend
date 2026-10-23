-- =====================================================================
-- Laboratorio #3 | Sistema de inventario aduanero
-- Asignatura : Bases de Datos
-- Integrantes: ________________________  /  ________________________
-- Gestor     : MySQL 8.0 (motor InnoDB, juego de caracteres utf8mb4)
-- Fecha      : 23/10/2026
-- Descripción: crea la base "aduana" con sus 14 tablas, llaves y
--              restricciones, la llena con datos de prueba, crea un usuario
--              de solo lectura para el agente de n8n y ejecuta 13 consultas.
-- Moneda     : todos los valores están en dólares (USD).
-- Ejecución  : MySQL Workbench (File > Open SQL Script > rayo) o consola:
--              mysql -h 127.0.0.1 -P 3307 -u root -p --default-character-set=utf8mb4 < este_archivo.sql
-- =====================================================================

-- utf8mb4 guarda tildes y ñ; la intercalación *_ai_ci hace que las búsquedas
-- no distingan mayúsculas ni tildes ('mexico' encuentra 'México').
CREATE DATABASE IF NOT EXISTS aduana
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE aduana;
SET NAMES utf8mb4;

-- Permite ejecutar el script varias veces: borra las tablas si ya existen.
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS liquidacion, inspeccion, movimiento_inventario, inventario,
    contenedor, detalle_declaracion, declaracion, bodega, funcionario, producto,
    partida_arancelaria, agente_aduanal, importador, pais;
SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- 1. CREACIÓN DE TABLAS (primero las "padre", luego las "hijas")
-- Nota: en MySQL las llaves foráneas se declaran con FOREIGN KEY (...)
-- al final de la tabla; un REFERENCES escrito junto a la columna se ignora.
-- =====================================================================

CREATE TABLE pais (
    id_pais      INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(60) NOT NULL UNIQUE,
    codigo_iso   CHAR(2)     NOT NULL UNIQUE,
    continente   VARCHAR(20) NOT NULL,
    CONSTRAINT chk_pais_iso CHECK (REGEXP_LIKE(codigo_iso, '^[A-Z]{2}$', 'c')),
    CONSTRAINT chk_pais_continente
        CHECK (continente IN ('America','Europa','Asia','Africa','Oceania'))
);

CREATE TABLE importador (
    id_importador INT AUTO_INCREMENT PRIMARY KEY,
    razon_social  VARCHAR(120) NOT NULL UNIQUE,
    nit           VARCHAR(15)  NOT NULL UNIQUE,
    tipo          VARCHAR(12)  NOT NULL DEFAULT 'Importador',
    direccion     VARCHAR(150) NOT NULL,
    telefono      VARCHAR(15),
    correo        VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT chk_importador_tipo CHECK (tipo IN ('Importador','Exportador','Ambos')),
    CONSTRAINT chk_importador_correo CHECK (correo LIKE '%_@_%._%')
);

CREATE TABLE agente_aduanal (
    id_agente  INT AUTO_INCREMENT PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL,
    licencia   VARCHAR(20)  NOT NULL UNIQUE,
    telefono   VARCHAR(15),
    correo     VARCHAR(100) UNIQUE,
    activo     BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_agente_correo CHECK (correo LIKE '%_@_%._%')
);

-- Partida arancelaria según el Sistema Armonizado (SA)
CREATE TABLE partida_arancelaria (
    id_partida         INT AUTO_INCREMENT PRIMARY KEY,
    codigo_sa          VARCHAR(12)  NOT NULL UNIQUE,
    descripcion        VARCHAR(150) NOT NULL,
    porcentaje_arancel DECIMAL(5,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_partida_porcentaje CHECK (porcentaje_arancel BETWEEN 0 AND 100)
);

-- 1:N -> una partida clasifica muchos productos
CREATE TABLE producto (
    id_producto    INT AUTO_INCREMENT PRIMARY KEY,
    descripcion    VARCHAR(120)  NOT NULL UNIQUE,
    unidad_medida  VARCHAR(15)   NOT NULL,
    valor_unitario DECIMAL(12,2) NOT NULL,
    id_partida     INT           NOT NULL,
    CONSTRAINT chk_producto_unidad
        CHECK (unidad_medida IN ('Unidad','Par','Caja','Kilogramo','Litro','Tonelada')),
    CONSTRAINT chk_producto_valor CHECK (valor_unitario > 0),
    CONSTRAINT fk_producto_partida FOREIGN KEY (id_partida)
        REFERENCES partida_arancelaria(id_partida)
);

-- Relación RECURSIVA -> un funcionario puede supervisar a otros funcionarios
-- (MySQL no permite un CHECK que use la columna AUTO_INCREMENT, por eso no
-- se valida aquí que alguien no sea su propio supervisor).
CREATE TABLE funcionario (
    id_funcionario INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    cargo          VARCHAR(40)  NOT NULL,
    correo         VARCHAR(100) NOT NULL UNIQUE,
    fecha_ingreso  DATE         NOT NULL DEFAULT (CURRENT_DATE),
    id_supervisor  INT          NULL,
    CONSTRAINT fk_funcionario_supervisor FOREIGN KEY (id_supervisor)
        REFERENCES funcionario(id_funcionario)
);

CREATE TABLE bodega (
    id_bodega    INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(40)  NOT NULL UNIQUE,
    ubicacion    VARCHAR(100) NOT NULL,
    capacidad_m3 INT          NOT NULL,
    tipo         VARCHAR(25)  NOT NULL DEFAULT 'General',
    CONSTRAINT chk_bodega_capacidad CHECK (capacidad_m3 > 0),
    CONSTRAINT chk_bodega_tipo CHECK (tipo IN ('General','Contenedores','Refrigerada',
        'Mercancía peligrosa','Vehículos','Depósito fiscal'))
);

-- 1:N con importador, agente y país (un país origina muchas declaraciones)
CREATE TABLE declaracion (
    id_declaracion    INT AUTO_INCREMENT PRIMARY KEY,
    numero            VARCHAR(20) NOT NULL UNIQUE,
    fecha             DATE        NOT NULL,
    regimen           VARCHAR(15) NOT NULL,
    estado            VARCHAR(15) NOT NULL DEFAULT 'Registrada',
    medio_transporte  VARCHAR(10) NOT NULL,
    id_importador     INT NOT NULL,
    id_agente         INT NOT NULL,
    id_pais_origen    INT NOT NULL,
    id_pais_destino   INT NULL,
    CONSTRAINT chk_declaracion_regimen
        CHECK (regimen IN ('Importacion','Exportacion','Transito','Deposito')),
    CONSTRAINT chk_declaracion_estado
        CHECK (estado IN ('Registrada','En inspeccion','Retenida','Liberada','Anulada')),
    CONSTRAINT chk_declaracion_transporte
        CHECK (medio_transporte IN ('Maritimo','Terrestre','Aereo')),
    -- exportaciones y tránsitos deben indicar a qué país va la mercancía
    CONSTRAINT chk_declaracion_destino
        CHECK (regimen IN ('Importacion','Deposito') OR id_pais_destino IS NOT NULL),
    CONSTRAINT fk_declaracion_importador FOREIGN KEY (id_importador) REFERENCES importador(id_importador),
    CONSTRAINT fk_declaracion_agente     FOREIGN KEY (id_agente)     REFERENCES agente_aduanal(id_agente),
    CONSTRAINT fk_declaracion_origen     FOREIGN KEY (id_pais_origen)  REFERENCES pais(id_pais),
    CONSTRAINT fk_declaracion_destino    FOREIGN KEY (id_pais_destino) REFERENCES pais(id_pais)
);

-- N:M resuelta -> una declaración tiene muchos productos y un producto aparece
-- en muchas declaraciones. Llave primaria COMPUESTA.
CREATE TABLE detalle_declaracion (
    id_declaracion  INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        DECIMAL(12,2) NOT NULL,
    valor_declarado DECIMAL(14,2) NOT NULL,
    PRIMARY KEY (id_declaracion, id_producto),
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_valor CHECK (valor_declarado >= 0),
    CONSTRAINT fk_detalle_declaracion FOREIGN KEY (id_declaracion)
        REFERENCES declaracion(id_declaracion) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) REFERENCES producto(id_producto)
);

CREATE TABLE contenedor (
    id_contenedor  INT AUTO_INCREMENT PRIMARY KEY,
    numero         VARCHAR(11)   NOT NULL UNIQUE,
    tipo           VARCHAR(20)   NOT NULL,
    peso_kg        DECIMAL(10,2) NOT NULL,
    id_declaracion INT           NOT NULL,
    CONSTRAINT chk_contenedor_numero CHECK (REGEXP_LIKE(numero, '^[A-Z]{4}[0-9]{7}$', 'c')),
    CONSTRAINT chk_contenedor_tipo
        CHECK (tipo IN ('20 pies','40 pies','40 pies HC','Refrigerado','Furgón 53 pies')),
    CONSTRAINT chk_contenedor_peso CHECK (peso_kg > 0),
    CONSTRAINT fk_contenedor_declaracion FOREIGN KEY (id_declaracion)
        REFERENCES declaracion(id_declaracion)
);

-- Stock actual de cada producto, por bodega y por declaración.
CREATE TABLE inventario (
    id_inventario  INT AUTO_INCREMENT PRIMARY KEY,
    id_bodega      INT           NOT NULL,
    id_producto    INT           NOT NULL,
    id_declaracion INT           NOT NULL,
    cantidad       DECIMAL(12,2) NOT NULL DEFAULT 0,
    fecha_ingreso  DATE          NOT NULL,
    estado         VARCHAR(15)   NOT NULL DEFAULT 'Retenido',
    CONSTRAINT uq_inventario UNIQUE (id_bodega, id_producto, id_declaracion),
    CONSTRAINT chk_inventario_cantidad CHECK (cantidad >= 0),
    CONSTRAINT chk_inventario_estado CHECK (estado IN ('Retenido','En inspeccion','Liberado')),
    CONSTRAINT fk_inventario_bodega      FOREIGN KEY (id_bodega)      REFERENCES bodega(id_bodega),
    CONSTRAINT fk_inventario_producto    FOREIGN KEY (id_producto)    REFERENCES producto(id_producto),
    CONSTRAINT fk_inventario_declaracion FOREIGN KEY (id_declaracion) REFERENCES declaracion(id_declaracion)
);

CREATE TABLE movimiento_inventario (
    id_movimiento     INT AUTO_INCREMENT PRIMARY KEY,
    tipo              VARCHAR(10)   NOT NULL,
    fecha             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad          DECIMAL(12,2) NOT NULL,
    id_producto       INT NOT NULL,
    id_bodega         INT NOT NULL,
    id_bodega_destino INT NULL,
    id_declaracion    INT NOT NULL,
    id_funcionario    INT NOT NULL,
    CONSTRAINT chk_movimiento_tipo CHECK (tipo IN ('Entrada','Salida','Traslado')),
    CONSTRAINT chk_movimiento_cantidad CHECK (cantidad > 0),
    -- solo los traslados tienen bodega destino, y debe ser distinta a la de origen
    CONSTRAINT chk_movimiento_traslado CHECK ((tipo = 'Traslado') = (id_bodega_destino IS NOT NULL)),
    CONSTRAINT chk_movimiento_destino CHECK (id_bodega_destino IS NULL OR id_bodega_destino <> id_bodega),
    CONSTRAINT fk_movimiento_producto    FOREIGN KEY (id_producto)       REFERENCES producto(id_producto),
    CONSTRAINT fk_movimiento_bodega      FOREIGN KEY (id_bodega)         REFERENCES bodega(id_bodega),
    CONSTRAINT fk_movimiento_destino     FOREIGN KEY (id_bodega_destino) REFERENCES bodega(id_bodega),
    CONSTRAINT fk_movimiento_declaracion FOREIGN KEY (id_declaracion)    REFERENCES declaracion(id_declaracion),
    CONSTRAINT fk_movimiento_funcionario FOREIGN KEY (id_funcionario)    REFERENCES funcionario(id_funcionario)
);

CREATE TABLE inspeccion (
    id_inspeccion  INT AUTO_INCREMENT PRIMARY KEY,
    fecha          DATE        NOT NULL,
    canal          VARCHAR(12) NOT NULL,
    resultado      VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    observaciones  TEXT,
    id_declaracion INT NOT NULL,
    id_funcionario INT NOT NULL,
    CONSTRAINT chk_inspeccion_canal CHECK (canal IN ('Documental','Física','Rayos X')),
    CONSTRAINT chk_inspeccion_resultado
        CHECK (resultado IN ('Pendiente','Conforme','Con observaciones','No conforme')),
    CONSTRAINT fk_inspeccion_declaracion FOREIGN KEY (id_declaracion) REFERENCES declaracion(id_declaracion),
    CONSTRAINT fk_inspeccion_funcionario FOREIGN KEY (id_funcionario) REFERENCES funcionario(id_funcionario)
);

-- 1:1 -> cada declaración tiene UNA sola liquidación de impuestos (UNIQUE en la FK)
CREATE TABLE liquidacion (
    id_liquidacion INT AUTO_INCREMENT PRIMARY KEY,
    id_declaracion INT NOT NULL UNIQUE,
    valor_cif      DECIMAL(14,2) NOT NULL,
    monto_arancel  DECIMAL(14,2) NOT NULL DEFAULT 0,
    monto_iva      DECIMAL(14,2) NOT NULL DEFAULT 0,
    total_pagar    DECIMAL(14,2) GENERATED ALWAYS AS (monto_arancel + monto_iva) STORED,
    estado_pago    VARCHAR(10)   NOT NULL DEFAULT 'Pendiente',
    fecha_pago     DATE NULL,
    CONSTRAINT chk_liquidacion_montos CHECK (valor_cif >= 0 AND monto_arancel >= 0 AND monto_iva >= 0),
    CONSTRAINT chk_liquidacion_estado CHECK (estado_pago IN ('Pendiente','Pagada','Anulada')),
    CONSTRAINT chk_liquidacion_fecha CHECK ((estado_pago = 'Pagada') = (fecha_pago IS NOT NULL)),
    CONSTRAINT fk_liquidacion_declaracion FOREIGN KEY (id_declaracion) REFERENCES declaracion(id_declaracion)
);

-- Índices para los filtros más usados (MySQL ya indexa cada llave foránea)
CREATE INDEX idx_declaracion_estado ON declaracion(estado);
CREATE INDEX idx_declaracion_fecha  ON declaracion(fecha);
CREATE INDEX idx_inventario_estado  ON inventario(estado);

-- =====================================================================
-- 2. LLENADO DE DATOS (mismo orden: padres -> hijas)
-- =====================================================================

INSERT INTO pais (nombre, codigo_iso, continente) VALUES
  ('Guatemala', 'GT', 'America'),
  ('China', 'CN', 'Asia'),
  ('Estados Unidos', 'US', 'America'),
  ('México', 'MX', 'America'),
  ('Japón', 'JP', 'Asia'),
  ('Corea del Sur', 'KR', 'Asia'),
  ('Alemania', 'DE', 'Europa'),
  ('España', 'ES', 'Europa'),
  ('Brasil', 'BR', 'America'),
  ('Colombia', 'CO', 'America'),
  ('Chile', 'CL', 'America'),
  ('Argentina', 'AR', 'America'),
  ('Vietnam', 'VN', 'Asia'),
  ('India', 'IN', 'Asia'),
  ('Italia', 'IT', 'Europa'),
  ('Panamá', 'PA', 'America'),
  ('Costa Rica', 'CR', 'America'),
  ('Canadá', 'CA', 'America');

INSERT INTO importador (razon_social, nit, tipo, direccion, telefono, correo) VALUES
  ('Distribuidora Tecnológica del Pacífico, S.A.', '4589632-1', 'Importador', 'Calzada Roosevelt 22-43, Zona 11', '2245-8890', 'compras@ditepsa.com'),
  ('Electrohogar Centroamericano, S.A.', '7741258-K', 'Importador', 'Av. Petapa 45-10, Zona 12', '2478-3321', 'importaciones@electrohogar.com'),
  ('Autos y Motores de Guatemala, S.A.', '3325874-9', 'Importador', 'Boulevard Liberación 6-31, Zona 9', '2360-7700', 'logistica@automotores.com.gt'),
  ('Textiles La Ceiba, S.A.', '6658471-2', 'Ambos', 'Km 15.5 Carretera a El Salvador', '6634-1200', 'comercio@textilesceiba.com'),
  ('Farmacéutica Nacional, S.A.', '1254789-6', 'Importador', 'Diagonal 6 13-01, Zona 10', '2385-4400', 'regulatorio@farmanac.com'),
  ('Café Altiplano Exportadores, S.A.', '8874521-3', 'Exportador', '5a Avenida 4-20, Antigua Guatemala', '7832-9090', 'exportaciones@cafealtiplano.com'),
  ('Llantas y Repuestos Rodamax, S.A.', '5547896-0', 'Importador', 'Calzada Aguilar Batres 34-70, Zona 11', '2440-5566', 'pedidos@rodamax.com'),
  ('Juguetería El Trompo, S.A.', '2365418-7', 'Importador', '18 Calle 7-55, Zona 1', '2232-1188', 'gerencia@eltrompo.com.gt'),
  ('Vinos y Licores Selectos, S.A.', '9963257-4', 'Importador', 'Av. Las Américas 9-08, Zona 13', '2331-6060', 'ventas@vinoselectos.com'),
  ('Industrias Plásticas del Sur, S.A.', '4412587-5', 'Importador', 'Km 22 Carretera al Pacífico, Villa Nueva', '6629-4545', 'materiaprima@plasur.com'),
  ('Aceros y Estructuras Maya, S.A.', '3369852-1', 'Importador', 'Km 17.5 Carretera a Amatitlán', '6640-2200', 'compras@acerosmaya.com'),
  ('Agroquímicos del Valle, S.A.', '7785412-8', 'Importador', 'Km 92 Carretera a Escuintla', '7888-3030', 'importaciones@agrovalle.com'),
  ('Muebles Confort Hogar, S.A.', '1147852-3', 'Importador', 'Calzada San Juan 12-60, Zona 7', '2434-7878', 'compras@confortogar.com'),
  ('Calzado Deportivo Andino, S.A.', '6632541-0', 'Importador', '6a Avenida 10-45, Zona 4, Mixco', '2437-9911', 'logistica@calzadoandino.com'),
  ('Comercializadora Global Express, S.A.', '8521479-6', 'Ambos', 'Av. Reforma 15-54, Zona 9', '2361-0505', 'operaciones@globalexpress.com.gt'),
  ('Telecom Smart Devices, S.A.', '2258963-4', 'Importador', 'Av. La Reforma 3-48, Zona 9', '2380-1414', 'supplychain@smartdevices.com.gt');

INSERT INTO agente_aduanal (nombre, licencia, telefono, correo, activo) VALUES
  ('Carlos Enrique Méndez López', 'AA-2011-0154', '5512-4478', 'cmendez@agenciasmendez.com', TRUE),
  ('María José Castillo Pérez', 'AA-2014-0233', '5589-1203', 'mjcastillo@aduanasmj.com', TRUE),
  ('Jorge Luis Ramírez Ochoa', 'AA-2009-0087', '4421-3390', 'jramirez@ramirezaduanas.com', TRUE),
  ('Ana Lucía Herrera Gómez', 'AA-2016-0312', '5532-7781', 'aherrera@herreralogistica.com', TRUE),
  ('Roberto Antonio Salazar Cruz', 'AA-2012-0198', '4478-1102', 'rsalazar@salazarcustoms.com', TRUE),
  ('Claudia Patricia Morales Díaz', 'AA-2018-0405', '5598-6634', 'cmorales@moralesagentes.com', TRUE),
  ('Luis Fernando Juárez Estrada', 'AA-2010-0121', '4410-5523', 'ljuarez@juarezaduanas.com', TRUE),
  ('Sofía Alejandra Rivera Paz', 'AA-2019-0457', '5567-2290', 'srivera@riverabroker.com', TRUE),
  ('Héctor Manuel Aguilar Soto', 'AA-2008-0063', '4433-8876', 'haguilar@aguilaraduanas.com', TRUE),
  ('Gabriela Isabel Fuentes Rosales', 'AA-2020-0498', '5541-0098', 'gfuentes@fuentescomex.com', TRUE),
  ('Mario Rodolfo Pineda Vásquez', 'AA-2013-0215', '4499-6612', 'mpineda@pinedaagencia.com', TRUE),
  ('Karla Beatriz Orellana Lima', 'AA-2017-0366', '5520-4417', 'korellana@orellanaaduanas.com', TRUE),
  ('Edgar Alfonso Barrios Monzón', 'AA-2015-0287', '4456-9930', 'ebarrios@barrioslogistics.com', TRUE),
  ('Diana Carolina Reyes Batres', 'AA-2021-0532', '5577-3365', 'dreyes@reyescomex.com', TRUE),
  ('Fernando José Cabrera Sandoval', 'AA-2007-0041', '4401-2258', 'fcabrera@cabreraaduanas.com', FALSE);

INSERT INTO partida_arancelaria (codigo_sa, descripcion, porcentaje_arancel) VALUES
  ('8471.30.00', 'Máquinas automáticas para procesamiento de datos, portátiles', 0),
  ('8517.13.00', 'Teléfonos inteligentes', 0),
  ('8528.72.00', 'Televisores en colores', 15),
  ('8703.23.00', 'Vehículos de turismo de cilindrada entre 1,500 y 3,000 cm3', 20),
  ('4011.10.00', 'Neumáticos nuevos de caucho para automóviles de turismo', 10),
  ('6109.10.00', 'Camisetas de punto, de algodón', 15),
  ('6404.11.00', 'Calzado deportivo con suela de caucho', 15),
  ('9503.00.00', 'Juguetes, rompecabezas y modelos reducidos', 10),
  ('3004.90.00', 'Medicamentos dosificados para uso humano', 0),
  ('0901.21.00', 'Café tostado sin descafeinar', 15),
  ('2204.21.00', 'Vino de uvas frescas en recipientes de hasta 2 litros', 15),
  ('8418.10.00', 'Refrigeradores y congeladores combinados', 10),
  ('8450.11.00', 'Lavadoras automáticas de ropa', 10),
  ('3923.30.00', 'Bombonas, botellas, frascos y preformas de plástico', 5),
  ('7208.51.00', 'Productos laminados planos de hierro o acero, laminados en caliente', 5),
  ('8711.20.00', 'Motocicletas con motor de cilindrada entre 50 y 250 cm3', 10),
  ('3808.91.00', 'Insecticidas', 5),
  ('9401.61.00', 'Asientos tapizados con armazón de madera', 10);

INSERT INTO producto (descripcion, unidad_medida, valor_unitario, id_partida) VALUES
  ('Laptop Lenovo ThinkPad E14', 'Unidad', 650.0, 1),
  ('Laptop HP ProBook 450 G10', 'Unidad', 720.0, 1),
  ('Smartphone Samsung Galaxy A55', 'Unidad', 310.0, 2),
  ('Smartphone Xiaomi Redmi Note 13', 'Unidad', 180.0, 2),
  ('Televisor LED 55 pulgadas 4K', 'Unidad', 340.0, 3),
  ('Automóvil Toyota Corolla 1.8L', 'Unidad', 18500.0, 4),
  ('Neumático 205/55 R16', 'Unidad', 48.0, 5),
  ('Camiseta de algodón cuello redondo', 'Unidad', 2.1, 6),
  ('Zapato deportivo para adulto', 'Par', 14.5, 7),
  ('Set de bloques de construcción 500 piezas', 'Unidad', 9.8, 8),
  ('Paracetamol 500 mg caja x100 tabletas', 'Caja', 3.2, 9),
  ('Café tostado en grano', 'Kilogramo', 6.5, 10),
  ('Vino tinto Malbec 750 ml', 'Unidad', 5.75, 11),
  ('Refrigerador de 14 pies cúbicos', 'Unidad', 420.0, 12),
  ('Lavadora automática 18 kg', 'Unidad', 380.0, 13),
  ('Preformas PET 28 g para botella', 'Kilogramo', 1.45, 14),
  ('Lámina de acero laminada en caliente 3 mm', 'Tonelada', 690.0, 15),
  ('Motocicleta 150 cc', 'Unidad', 1150.0, 16),
  ('Insecticida agrícola concentrado', 'Litro', 7.9, 17),
  ('Sofá tapizado de 3 plazas', 'Unidad', 260.0, 18);

-- Primero el jefe máximo (sin supervisor) y luego sus subordinados
INSERT INTO funcionario (nombre, cargo, correo, fecha_ingreso, id_supervisor) VALUES
  ('Ricardo Alberto Monterroso', 'Administrador de Aduana', 'rmonterroso@aduana.gob', '2012-03-01', NULL),
  ('Patricia Elena Girón', 'Jefe de Inspección', 'pgiron@aduana.gob', '2015-06-15', 1),
  ('Oscar David Lemus', 'Jefe de Bodegas', 'olemus@aduana.gob', '2016-01-10', 1),
  ('Marta Lucía Toledo', 'Jefe de Valoración', 'mtoledo@aduana.gob', '2017-09-04', 1),
  ('Julio César Arriaga', 'Inspector', 'jarriaga@aduana.gob', '2018-02-19', 2),
  ('Andrea Paola Villatoro', 'Inspector', 'avillatoro@aduana.gob', '2019-07-01', 2),
  ('Kevin Alexander Choc', 'Inspector', 'kchoc@aduana.gob', '2020-05-11', 2),
  ('Lucía Fernanda Estrada', 'Inspector', 'lestrada@aduana.gob', '2021-03-22', 2),
  ('Byron Estuardo Coyoy', 'Inspector', 'bcoyoy@aduana.gob', '2022-08-08', 2),
  ('Silvia Marisol Ajú', 'Bodeguero', 'saju@aduana.gob', '2018-11-05', 3),
  ('Walter Iván Tzul', 'Bodeguero', 'wtzul@aduana.gob', '2019-04-29', 3),
  ('Rosa Amelia Pérez', 'Bodeguero', 'rperez@aduana.gob', '2020-10-12', 3),
  ('Daniel Eduardo Sic', 'Bodeguero', 'dsic@aduana.gob', '2023-01-16', 3),
  ('Brenda Yaneth Ixcot', 'Analista de Valoración', 'bixcot@aduana.gob', '2019-09-02', 4),
  ('Hugo Leonel Cifuentes', 'Analista de Valoración', 'hcifuentes@aduana.gob', '2021-06-07', 4),
  ('Carmen Rocío Batz', 'Analista de Valoración', 'cbatz@aduana.gob', '2024-02-05', 4);

INSERT INTO bodega (nombre, ubicacion, capacidad_m3, tipo) VALUES
  ('Bodega 1', 'Puerto Quetzal - Patio A', 12000, 'General'),
  ('Bodega 2', 'Puerto Quetzal - Patio B', 15000, 'Contenedores'),
  ('Bodega 3', 'Puerto Quetzal - Nave 3', 8000, 'General'),
  ('Bodega 4', 'Puerto Quetzal - Nave 4', 3000, 'Refrigerada'),
  ('Bodega 5', 'Puerto Quetzal - Área restringida', 1500, 'Mercancía peligrosa'),
  ('Bodega 6', 'Santo Tomás de Castilla - Patio 1', 14000, 'Contenedores'),
  ('Bodega 7', 'Santo Tomás de Castilla - Nave 2', 9000, 'General'),
  ('Bodega 8', 'Santo Tomás de Castilla - Patio vehicular', 20000, 'Vehículos'),
  ('Bodega 9', 'Aeropuerto La Aurora - Terminal de carga', 2500, 'General'),
  ('Bodega 10', 'Aeropuerto La Aurora - Cuarto frío', 600, 'Refrigerada'),
  ('Bodega 11', 'Frontera Tecún Umán - Almacén 1', 5000, 'General'),
  ('Bodega 12', 'Frontera Pedro de Alvarado - Almacén 1', 4000, 'General'),
  ('Bodega 13', 'Almacén Fiscal Central - Zona 12', 10000, 'Depósito fiscal'),
  ('Bodega 14', 'Almacén Fiscal Central - Zona 12 Anexo', 6000, 'Depósito fiscal'),
  ('Bodega 15', 'Puerto Barrios - Nave 1', 7000, 'General');

-- id_pais: 1 Guatemala, 2 China, 3 EE.UU., 4 México, 5 Japón, 6 Corea del Sur, 7 Alemania, 8 España, 9 Brasil, ...
INSERT INTO declaracion (numero, fecha, regimen, estado, medio_transporte, id_importador, id_agente, id_pais_origen, id_pais_destino) VALUES
  ('DUA-2026-0001', '2026-08-04', 'Importacion', 'Liberada', 'Maritimo', 1, 1, 2, NULL),
  ('DUA-2026-0002', '2026-08-07', 'Importacion', 'Liberada', 'Maritimo', 3, 3, 5, NULL),
  ('DUA-2026-0003', '2026-08-12', 'Importacion', 'Liberada', 'Aereo', 5, 2, 7, NULL),
  ('DUA-2026-0004', '2026-08-18', 'Exportacion', 'Liberada', 'Maritimo', 6, 4, 1, 3),
  ('DUA-2026-0005', '2026-08-25', 'Importacion', 'Liberada', 'Maritimo', 7, 5, 9, NULL),
  ('DUA-2026-0006', '2026-09-02', 'Importacion', 'Liberada', 'Maritimo', 9, 6, 11, NULL),
  ('DUA-2026-0007', '2026-09-08', 'Importacion', 'Liberada', 'Terrestre', 2, 7, 4, NULL),
  ('DUA-2026-0008', '2026-09-11', 'Transito', 'Liberada', 'Terrestre', 15, 8, 16, 4),
  ('DUA-2026-0009', '2026-09-15', 'Importacion', 'Liberada', 'Aereo', 16, 9, 6, NULL),
  ('DUA-2026-0010', '2026-09-21', 'Deposito', 'Liberada', 'Maritimo', 10, 10, 2, NULL),
  ('DUA-2026-0011', '2026-09-26', 'Importacion', 'Retenida', 'Maritimo', 12, 11, 3, NULL),
  ('DUA-2026-0012', '2026-09-30', 'Exportacion', 'Liberada', 'Terrestre', 4, 12, 1, 3),
  ('DUA-2026-0013', '2026-10-01', 'Importacion', 'Retenida', 'Maritimo', 8, 1, 2, NULL),
  ('DUA-2026-0014', '2026-10-03', 'Importacion', 'En inspeccion', 'Maritimo', 13, 2, 15, NULL),
  ('DUA-2026-0015', '2026-10-05', 'Importacion', 'Liberada', 'Maritimo', 11, 3, 18, NULL),
  ('DUA-2026-0016', '2026-10-07', 'Importacion', 'Retenida', 'Maritimo', 16, 4, 2, NULL),
  ('DUA-2026-0017', '2026-10-09', 'Deposito', 'Retenida', 'Maritimo', 2, 5, 2, NULL),
  ('DUA-2026-0018', '2026-10-12', 'Importacion', 'En inspeccion', 'Maritimo', 14, 6, 13, NULL),
  ('DUA-2026-0019', '2026-10-13', 'Importacion', 'Liberada', 'Aereo', 5, 7, 14, NULL),
  ('DUA-2026-0020', '2026-10-14', 'Exportacion', 'Registrada', 'Maritimo', 6, 8, 1, 7),
  ('DUA-2026-0021', '2026-10-15', 'Importacion', 'Retenida', 'Maritimo', 3, 9, 2, NULL),
  ('DUA-2026-0022', '2026-10-16', 'Importacion', 'En inspeccion', 'Maritimo', 9, 10, 8, NULL),
  ('DUA-2026-0023', '2026-10-19', 'Transito', 'Registrada', 'Terrestre', 15, 11, 4, 17),
  ('DUA-2026-0024', '2026-10-20', 'Importacion', 'Registrada', 'Aereo', 1, 12, 3, NULL),
  ('DUA-2026-0025', '2026-10-21', 'Importacion', 'Anulada', 'Maritimo', 7, 13, 2, NULL);

INSERT INTO detalle_declaracion (id_declaracion, id_producto, cantidad, valor_declarado) VALUES
  (1, 1, 70, 44678.65),
  (1, 4, 702, 129531.96),
  (1, 5, 269, 87783.78),
  (2, 6, 9, 165851.86),
  (2, 18, 76, 87321.61),
  (3, 11, 6585, 20865.66),
  (3, 19, 1705, 13916.47),
  (4, 12, 9645, 62763.13),
  (5, 7, 1455, 68155.68),
  (5, 9, 4261, 63987.97),
  (6, 13, 5334, 30028.51),
  (7, 14, 81, 34641.87),
  (7, 15, 106, 39099.74),
  (8, 3, 464, 146409.48),
  (8, 7, 1198, 56197.55),
  (9, 3, 266, 82619.44),
  (9, 5, 61, 21680.92),
  (10, 16, 16820, 23697.68),
  (11, 19, 2908, 23748.3),
  (11, 15, 73, 27063.49),
  (12, 8, 10178, 21604.18),
  (13, 10, 1959, 18348.93),
  (13, 8, 9610, 20575.14),
  (14, 20, 75, 19689.06),
  (14, 9, 1717, 24537.92),
  (15, 17, 22, 14841.23),
  (16, 4, 720, 134292.91),
  (16, 2, 141, 98804.47),
  (16, 1, 135, 86513.68),
  (17, 14, 121, 49156.01),
  (17, 5, 95, 32993.54),
  (18, 9, 2794, 39838.9),
  (18, 8, 15850, 34241.09),
  (19, 11, 6416, 19801.82),
  (20, 12, 11822, 77688.42),
  (21, 18, 44, 49398.61),
  (21, 7, 1371, 68502.83),
  (22, 13, 3862, 22056.82),
  (22, 11, 5301, 16647.15),
  (23, 5, 273, 89272.85),
  (23, 15, 74, 29079.4),
  (24, 2, 109, 79475.73),
  (25, 20, 59, 15081.94),
  (25, 10, 1087, 10717.9);

INSERT INTO contenedor (numero, tipo, peso_kg, id_declaracion) VALUES
  ('MAEU6710873', '40 pies', 20414, 1),
  ('EGLV8674700', '20 pies', 17133, 1),
  ('MAEU8204296', '20 pies', 8800, 2),
  ('HLXU3047042', '40 pies', 19898, 2),
  ('MSCU5866552', '40 pies', 21139, 4),
  ('EGLV6993671', '20 pies', 9979, 5),
  ('ZIMU3262652', '20 pies', 8084, 5),
  ('HLXU7308337', '40 pies', 20520, 6),
  ('MSCU6821993', '20 pies', 9738, 6),
  ('CMAU1758944', 'Furgón 53 pies', 19620, 7),
  ('EGLV8783206', 'Furgón 53 pies', 17152, 8),
  ('MSCU6976939', '20 pies', 15144, 10),
  ('MSCU6199572', '20 pies', 8938, 11),
  ('COSU6284394', '20 pies', 9537, 11),
  ('ZIMU8149173', 'Furgón 53 pies', 10956, 12),
  ('COSU4312632', '40 pies', 21594, 13),
  ('CMAU3058316', '40 pies HC', 13844, 13),
  ('CMAU1476760', '40 pies HC', 14051, 14),
  ('ONEU5277759', '40 pies HC', 23202, 14),
  ('EGLV6716215', '20 pies', 18653, 15),
  ('COSU1943814', '40 pies HC', 24174, 15),
  ('EGLV4152477', '40 pies', 23033, 16),
  ('ZIMU1089117', '20 pies', 18289, 16),
  ('MSCU7598076', '40 pies HC', 21381, 17),
  ('CMAU9535601', '40 pies', 20463, 17),
  ('HLXU1158525', '40 pies', 14195, 18),
  ('COSU3866978', '40 pies HC', 18924, 18),
  ('MAEU2226936', '20 pies', 9741, 20),
  ('ZIMU6790134', '20 pies', 13876, 21),
  ('ZIMU6234931', '20 pies', 9131, 21),
  ('COSU7873623', '40 pies HC', 24897, 22),
  ('ZIMU3140504', '40 pies HC', 14529, 22),
  ('ZIMU5422858', 'Furgón 53 pies', 11381, 23);

INSERT INTO inventario (id_bodega, id_producto, id_declaracion, cantidad, fecha_ingreso, estado) VALUES
  (2, 1, 1, 28, '2026-08-07', 'Liberado'),
  (2, 4, 1, 0, '2026-08-07', 'Liberado'),
  (2, 5, 1, 0, '2026-08-05', 'Liberado'),
  (8, 6, 2, 4, '2026-08-08', 'Liberado'),
  (15, 18, 2, 25, '2026-08-09', 'Liberado'),
  (10, 11, 3, 3308, '2026-08-14', 'Liberado'),
  (9, 19, 3, 679, '2026-08-13', 'Liberado'),
  (3, 7, 5, 802, '2026-08-27', 'Liberado'),
  (3, 9, 5, 0, '2026-08-27', 'Liberado'),
  (7, 13, 6, 2973, '2026-09-05', 'Liberado'),
  (11, 14, 7, 31, '2026-09-10', 'Liberado'),
  (11, 15, 7, 14, '2026-09-10', 'Liberado'),
  (12, 3, 8, 0, '2026-09-12', 'Liberado'),
  (12, 7, 8, 0, '2026-09-12', 'Liberado'),
  (9, 3, 9, 132, '2026-09-17', 'Liberado'),
  (9, 5, 9, 31, '2026-09-17', 'Liberado'),
  (14, 16, 10, 6415, '2026-09-24', 'Liberado'),
  (5, 19, 11, 2908, '2026-09-28', 'Retenido'),
  (1, 15, 11, 73, '2026-09-28', 'Retenido'),
  (13, 10, 13, 1959, '2026-10-04', 'Retenido'),
  (13, 8, 13, 9610, '2026-10-03', 'Retenido'),
  (6, 20, 14, 75, '2026-10-04', 'En inspeccion'),
  (7, 9, 14, 1717, '2026-10-05', 'En inspeccion'),
  (7, 17, 15, 0, '2026-10-07', 'Liberado'),
  (2, 4, 16, 720, '2026-10-10', 'Retenido'),
  (2, 2, 16, 141, '2026-10-09', 'Retenido'),
  (2, 1, 16, 135, '2026-10-10', 'Retenido'),
  (14, 14, 17, 121, '2026-10-11', 'Retenido'),
  (13, 5, 17, 95, '2026-10-10', 'Retenido'),
  (6, 9, 18, 2794, '2026-10-14', 'En inspeccion'),
  (3, 8, 18, 15850, '2026-10-14', 'En inspeccion'),
  (10, 11, 19, 2901, '2026-10-14', 'Liberado'),
  (13, 18, 21, 44, '2026-10-17', 'Retenido'),
  (2, 7, 21, 1371, '2026-10-16', 'Retenido'),
  (15, 13, 22, 3862, '2026-10-18', 'En inspeccion'),
  (4, 11, 22, 5301, '2026-10-17', 'En inspeccion');

INSERT INTO movimiento_inventario (tipo, fecha, cantidad, id_producto, id_bodega, id_bodega_destino, id_declaracion, id_funcionario) VALUES
  ('Entrada', '2026-08-05 14:00:00', 269, 5, 2, NULL, 1, 11),
  ('Entrada', '2026-08-07 08:00:00', 70, 1, 2, NULL, 1, 10),
  ('Entrada', '2026-08-07 14:00:00', 702, 4, 2, NULL, 1, 10),
  ('Entrada', '2026-08-08 13:00:00', 9, 6, 8, NULL, 2, 13),
  ('Entrada', '2026-08-09 13:00:00', 76, 18, 15, NULL, 2, 13),
  ('Entrada', '2026-08-13 07:00:00', 1705, 19, 9, NULL, 3, 10),
  ('Salida', '2026-08-13 08:00:00', 702, 4, 2, NULL, 1, 11),
  ('Salida', '2026-08-14 12:00:00', 269, 5, 2, NULL, 1, 11),
  ('Entrada', '2026-08-14 15:00:00', 6585, 11, 10, NULL, 3, 13),
  ('Salida', '2026-08-14 16:00:00', 51, 18, 15, NULL, 2, 10),
  ('Salida', '2026-08-18 16:00:00', 42, 1, 2, NULL, 1, 13),
  ('Salida', '2026-08-19 15:00:00', 5, 6, 8, NULL, 2, 13),
  ('Salida', '2026-08-25 13:00:00', 3277, 11, 10, NULL, 3, 10),
  ('Salida', '2026-08-25 15:00:00', 1026, 19, 9, NULL, 3, 12),
  ('Entrada', '2026-08-27 07:00:00', 4261, 9, 3, NULL, 5, 3),
  ('Entrada', '2026-08-27 14:00:00', 1455, 7, 3, NULL, 5, 3),
  ('Salida', '2026-09-02 16:00:00', 4261, 9, 3, NULL, 5, 10),
  ('Entrada', '2026-09-05 09:00:00', 5334, 13, 7, NULL, 6, 10),
  ('Salida', '2026-09-06 08:00:00', 653, 7, 3, NULL, 5, 10),
  ('Entrada', '2026-09-10 08:00:00', 81, 14, 11, NULL, 7, 12),
  ('Entrada', '2026-09-10 16:00:00', 106, 15, 11, NULL, 7, 10),
  ('Entrada', '2026-09-12 13:00:00', 1198, 7, 12, NULL, 8, 11),
  ('Entrada', '2026-09-12 15:00:00', 464, 3, 12, NULL, 8, 10),
  ('Salida', '2026-09-14 15:00:00', 2361, 13, 7, NULL, 6, 12),
  ('Entrada', '2026-09-17 08:00:00', 266, 3, 9, NULL, 9, 13),
  ('Salida', '2026-09-17 09:00:00', 50, 14, 11, NULL, 7, 13),
  ('Entrada', '2026-09-17 12:00:00', 61, 5, 9, NULL, 9, 12),
  ('Salida', '2026-09-19 09:00:00', 464, 3, 12, NULL, 8, 10),
  ('Salida', '2026-09-19 12:00:00', 1198, 7, 12, NULL, 8, 10),
  ('Salida', '2026-09-21 07:00:00', 92, 15, 11, NULL, 7, 10),
  ('Salida', '2026-09-23 10:00:00', 134, 3, 9, NULL, 9, 10),
  ('Salida', '2026-09-24 07:00:00', 30, 5, 9, NULL, 9, 11),
  ('Entrada', '2026-09-24 16:00:00', 16820, 16, 14, NULL, 10, 10),
  ('Entrada', '2026-09-28 11:00:00', 73, 15, 1, NULL, 11, 12),
  ('Entrada', '2026-09-28 12:00:00', 2908, 19, 5, NULL, 11, 10),
  ('Salida', '2026-10-01 08:00:00', 10405, 16, 14, NULL, 10, 11),
  ('Entrada', '2026-10-03 08:00:00', 9610, 8, 2, NULL, 13, 11),
  ('Entrada', '2026-10-04 13:00:00', 1959, 10, 2, NULL, 13, 3),
  ('Entrada', '2026-10-04 13:00:00', 75, 20, 6, NULL, 14, 13),
  ('Entrada', '2026-10-05 10:00:00', 1717, 9, 7, NULL, 14, 12),
  ('Entrada', '2026-10-07 11:00:00', 22, 17, 7, NULL, 15, 11),
  ('Traslado', '2026-10-09 10:00:00', 9610, 8, 2, 13, 13, 3),
  ('Entrada', '2026-10-09 12:00:00', 141, 2, 2, NULL, 16, 10),
  ('Traslado', '2026-10-10 10:00:00', 1959, 10, 2, 13, 13, 3),
  ('Entrada', '2026-10-10 13:00:00', 720, 4, 2, NULL, 16, 11),
  ('Entrada', '2026-10-10 14:00:00', 135, 1, 2, NULL, 16, 13),
  ('Entrada', '2026-10-10 15:00:00', 95, 5, 13, NULL, 17, 10),
  ('Entrada', '2026-10-11 15:00:00', 121, 14, 14, NULL, 17, 11),
  ('Salida', '2026-10-13 09:00:00', 22, 17, 7, NULL, 15, 13),
  ('Entrada', '2026-10-14 07:00:00', 2794, 9, 6, NULL, 18, 13),
  ('Entrada', '2026-10-14 08:00:00', 6416, 11, 10, NULL, 19, 13),
  ('Entrada', '2026-10-14 11:00:00', 15850, 8, 3, NULL, 18, 13),
  ('Entrada', '2026-10-16 15:00:00', 1371, 7, 2, NULL, 21, 13),
  ('Entrada', '2026-10-17 08:00:00', 44, 18, 2, NULL, 21, 11),
  ('Entrada', '2026-10-17 14:00:00', 5301, 11, 4, NULL, 22, 10),
  ('Entrada', '2026-10-18 12:00:00', 3862, 13, 15, NULL, 22, 12),
  ('Salida', '2026-10-19 12:00:00', 3515, 11, 10, NULL, 19, 3),
  ('Traslado', '2026-10-23 10:00:00', 44, 18, 2, 13, 21, 3);

INSERT INTO inspeccion (fecha, canal, resultado, observaciones, id_declaracion, id_funcionario) VALUES
  ('2026-08-07', 'Física', 'Con observaciones', 'Diferencia menor de cantidad (2%) respecto a la factura; se ajustó la declaración.', 1, 6),
  ('2026-08-11', 'Física', 'Con observaciones', 'Falta certificado de origen original; se presentó copia y se otorgó plazo.', 2, 6),
  ('2026-08-14', 'Rayos X', 'Con observaciones', 'Falta certificado de origen original; se presentó copia y se otorgó plazo.', 3, 7),
  ('2026-08-22', 'Documental', 'Conforme', 'Sin novedad; sellos intactos.', 4, 7),
  ('2026-08-29', 'Física', 'Conforme', 'Mercancía coincide con lo declarado.', 5, 8),
  ('2026-09-03', 'Física', 'Con observaciones', 'Embalaje dañado en dos bultos; mercancía en buen estado.', 6, 7),
  ('2026-09-12', 'Física', 'Conforme', 'Mercancía coincide con lo declarado.', 7, 7),
  ('2026-09-14', 'Documental', 'Conforme', NULL, 8, 5),
  ('2026-09-18', 'Física', 'Con observaciones', 'Falta certificado de origen original; se presentó copia y se otorgó plazo.', 9, 8),
  ('2026-09-22', 'Física', 'Conforme', 'Sin novedad; sellos intactos.', 10, 6),
  ('2026-09-30', 'Física', 'No conforme', 'Falta permiso sanitario / fitosanitario del ministerio correspondiente.', 11, 7),
  ('2026-10-02', 'Física', 'No conforme', 'Valor declarado inferior al de referencia; se inició ajuste de valor.', 13, 8),
  ('2026-10-03', 'Documental', 'Conforme', 'Mercancía coincide con lo declarado.', 12, 6),
  ('2026-10-03', 'Física', 'Con observaciones', 'Diferencia menor de cantidad (2%) respecto a la factura; se ajustó la declaración.', 11, 2),
  ('2026-10-05', 'Física', 'Pendiente', 'Programada revisión física completa.', 14, 2),
  ('2026-10-07', 'Rayos X', 'Conforme', 'Sin novedad; sellos intactos.', 15, 5),
  ('2026-10-07', 'Física', 'No conforme', 'Valor declarado inferior al de referencia; se inició ajuste de valor.', 13, 6),
  ('2026-10-10', 'Física', 'Con observaciones', 'Etiquetado en idioma extranjero; se solicitó reetiquetar antes de su venta.', 16, 2),
  ('2026-10-10', 'Física', 'No conforme', 'Falta permiso sanitario / fitosanitario del ministerio correspondiente.', 17, 9),
  ('2026-10-13', 'Física', 'Pendiente', 'Programada revisión física completa.', 18, 6),
  ('2026-10-14', 'Rayos X', 'Con observaciones', 'Etiquetado en idioma extranjero; se solicitó reetiquetar antes de su venta.', 16, 6),
  ('2026-10-15', 'Rayos X', 'Con observaciones', 'Diferencia menor de cantidad (2%) respecto a la factura; se ajustó la declaración.', 17, 9),
  ('2026-10-16', 'Física', 'Con observaciones', 'Falta certificado de origen original; se presentó copia y se otorgó plazo.', 19, 5),
  ('2026-10-18', 'Física', 'No conforme', 'Valor declarado inferior al de referencia; se inició ajuste de valor.', 21, 5),
  ('2026-10-20', 'Rayos X', 'Pendiente', 'Programada revisión física completa.', 22, 6),
  ('2026-10-23', 'Física', 'No conforme', 'Falta permiso sanitario / fitosanitario del ministerio correspondiente.', 21, 7);

-- Arancel = valor x % de la partida (solo importación); IVA = 12% sobre (CIF + arancel).
-- Depósito, tránsito y exportación no pagan impuestos: la mercancía en depósito (DUA-2026-0010)
-- salió reexportada, por eso su liquidación es 0.
INSERT INTO liquidacion (id_declaracion, valor_cif, monto_arancel, monto_iva, estado_pago, fecha_pago) VALUES
  (1, 261994.39, 13167.57, 33019.44, 'Pagada', '2026-08-06'),
  (2, 253173.47, 41902.53, 35409.12, 'Pagada', '2026-08-11'),
  (3, 34782.13, 695.82, 4257.35, 'Pagada', '2026-08-15'),
  (4, 62763.13, 0.0, 0.0, 'Pagada', '2026-08-21'),
  (5, 132143.65, 16413.76, 17826.89, 'Pagada', '2026-08-27'),
  (6, 30028.51, 4504.28, 4143.93, 'Pagada', '2026-09-05'),
  (7, 73741.61, 7374.16, 9733.89, 'Pagada', '2026-09-09'),
  (8, 202607.03, 0.0, 0.0, 'Pagada', '2026-09-15'),
  (9, 104300.36, 3252.14, 12906.3, 'Pagada', '2026-09-17'),
  (10, 23697.68, 0.0, 0.0, 'Pagada', '2026-09-23'),
  (11, 50811.79, 3893.76, 6564.67, 'Pendiente', NULL),
  (12, 21604.18, 0.0, 0.0, 'Pagada', '2026-10-03'),
  (13, 38924.07, 4921.16, 5261.43, 'Pendiente', NULL),
  (14, 44226.98, 5649.59, 5985.19, 'Pendiente', NULL),
  (15, 14841.23, 742.06, 1869.99, 'Pagada', '2026-10-06'),
  (16, 319611.06, 0.0, 38353.33, 'Pendiente', NULL),
  (17, 82149.55, 0.0, 0.0, 'Pendiente', NULL),
  (18, 74079.99, 11112.0, 10223.04, 'Pendiente', NULL),
  (19, 19801.82, 0.0, 2376.22, 'Pagada', '2026-10-16'),
  (20, 77688.42, 0.0, 0.0, 'Pendiente', NULL),
  (21, 117901.44, 11790.14, 15562.99, 'Pendiente', NULL),
  (22, 38703.97, 3308.52, 5041.5, 'Pendiente', NULL),
  (23, 118352.25, 0.0, 0.0, 'Pendiente', NULL),
  (24, 79475.73, 0.0, 9537.09, 'Pendiente', NULL),
  (25, 25799.84, 2579.98, 3405.58, 'Anulada', NULL);


-- =====================================================================
-- 3. SEGURIDAD: USUARIO DE SOLO LECTURA PARA EL AGENTE DE n8n
-- =====================================================================
-- El agente de IA se conecta con este usuario. Solo tiene permiso SELECT
-- sobre la base "aduana", así que aunque el modelo intentara un DELETE,
-- UPDATE o DROP, MySQL lo rechaza. ¡Cambien la clave y NO la suban!
CREATE USER IF NOT EXISTS 'agente_lectura'@'localhost' IDENTIFIED BY 'CAMBIAR_ESTA_CLAVE'
    WITH MAX_USER_CONNECTIONS 5;
GRANT SELECT ON aduana.* TO 'agente_lectura'@'localhost';
FLUSH PRIVILEGES;

-- =====================================================================
-- 4. CONSULTAS DEL NEGOCIO (JOIN, WHERE, GROUP BY, ORDER BY)
-- =====================================================================

-- Q1. ¿Cuántas declaraciones de importación se registraron en octubre de 2026?
SELECT COUNT(*) AS declaraciones_importacion_octubre
FROM declaracion
WHERE regimen = 'Importacion'
  AND fecha BETWEEN '2026-10-01' AND '2026-10-31';

-- Q2. ¿Qué mercancías siguen retenidas y en qué bodega están?
SELECT d.numero AS declaracion, p.descripcion AS producto, i.cantidad, p.unidad_medida,
       b.nombre AS bodega, b.ubicacion, pa.nombre AS pais_origen, i.fecha_ingreso
FROM inventario i
JOIN producto    p  ON p.id_producto    = i.id_producto
JOIN bodega      b  ON b.id_bodega      = i.id_bodega
JOIN declaracion d  ON d.id_declaracion = i.id_declaracion
JOIN pais        pa ON pa.id_pais       = d.id_pais_origen
WHERE i.estado = 'Retenido'
ORDER BY b.id_bodega, i.fecha_ingreso;

-- Q3. ¿Cuál es el país de origen con más contenedores recibidos?
SELECT pa.nombre AS pais_origen, COUNT(c.id_contenedor) AS contenedores,
       SUM(c.peso_kg) AS peso_total_kg
FROM contenedor c
JOIN declaracion d ON d.id_declaracion = c.id_declaracion
JOIN pais pa       ON pa.id_pais       = d.id_pais_origen
WHERE d.regimen <> 'Exportacion'
GROUP BY pa.nombre
ORDER BY contenedores DESC, peso_total_kg DESC;

-- Q4. ¿Qué importador ha declarado el mayor valor total en mercancías?
SELECT im.razon_social, COUNT(DISTINCT d.id_declaracion) AS declaraciones,
       SUM(dd.valor_declarado) AS valor_total_usd
FROM importador im
JOIN declaracion d          ON d.id_importador   = im.id_importador
JOIN detalle_declaracion dd ON dd.id_declaracion = d.id_declaracion
WHERE d.estado <> 'Anulada'
GROUP BY im.razon_social
ORDER BY valor_total_usd DESC
LIMIT 5;

-- Q5. ¿Qué inspecciones tuvieron resultado "Con observaciones" y quién las realizó?
SELECT ins.fecha, d.numero AS declaracion, ins.canal, f.nombre AS inspector,
       f.cargo, ins.observaciones
FROM inspeccion ins
JOIN funcionario f ON f.id_funcionario = ins.id_funcionario
JOIN declaracion d ON d.id_declaracion = ins.id_declaracion
WHERE ins.resultado = 'Con observaciones'
ORDER BY ins.fecha;

-- Q6. ¿Cuánto stock queda de cada producto en todas las bodegas?
SELECT p.descripcion AS producto, p.unidad_medida,
       SUM(i.cantidad) AS stock_total,
       SUM(CASE WHEN i.estado = 'Retenido' THEN i.cantidad ELSE 0 END) AS retenido,
       COUNT(DISTINCT i.id_bodega) AS bodegas
FROM inventario i
JOIN producto p ON p.id_producto = i.id_producto
WHERE i.cantidad > 0
GROUP BY p.descripcion, p.unidad_medida
ORDER BY stock_total DESC;

-- Q7. ¿Qué mercancías de China siguen retenidas en la bodega 2?
SELECT d.numero, p.descripcion AS producto, i.cantidad, im.razon_social AS importador
FROM inventario i
JOIN declaracion d  ON d.id_declaracion = i.id_declaracion
JOIN pais pa        ON pa.id_pais       = d.id_pais_origen
JOIN producto p     ON p.id_producto    = i.id_producto
JOIN bodega b       ON b.id_bodega      = i.id_bodega
JOIN importador im  ON im.id_importador = d.id_importador
WHERE pa.nombre = 'China' AND b.nombre = 'Bodega 2' AND i.estado = 'Retenido'
ORDER BY d.numero;

-- Q8. Impuestos (arancel + IVA) recaudados por mes y régimen
SELECT DATE_FORMAT(l.fecha_pago, '%Y-%m') AS mes, d.regimen, COUNT(*) AS liquidaciones_pagadas,
       SUM(l.monto_arancel) AS arancel, SUM(l.monto_iva) AS iva, SUM(l.total_pagar) AS total
FROM liquidacion l
JOIN declaracion d ON d.id_declaracion = l.id_declaracion
WHERE l.estado_pago = 'Pagada'
GROUP BY DATE_FORMAT(l.fecha_pago, '%Y-%m'), d.regimen
ORDER BY mes, d.regimen;

-- Q9. Declaraciones con impuestos pendientes de pago, su agente aduanal y días transcurridos
SELECT d.numero, d.fecha, d.estado, im.razon_social, ag.nombre AS agente_aduanal,
       l.total_pagar, DATEDIFF(CURRENT_DATE, d.fecha) AS dias_transcurridos
FROM liquidacion l
JOIN declaracion d     ON d.id_declaracion = l.id_declaracion
JOIN importador im     ON im.id_importador = d.id_importador
JOIN agente_aduanal ag ON ag.id_agente     = d.id_agente
WHERE l.estado_pago = 'Pendiente' AND l.total_pagar > 0
ORDER BY l.total_pagar DESC;

-- Q10. Personal de inspección, su supervisor (relación recursiva) y cuántas inspecciones hizo
SELECT f.nombre AS funcionario, f.cargo, s.nombre AS supervisor,
       COUNT(ins.id_inspeccion) AS inspecciones
FROM funcionario f
LEFT JOIN funcionario s  ON s.id_funcionario   = f.id_supervisor
LEFT JOIN inspeccion ins ON ins.id_funcionario = f.id_funcionario
WHERE f.cargo IN ('Inspector', 'Jefe de Inspección')
GROUP BY f.id_funcionario, f.nombre, f.cargo, s.nombre
ORDER BY inspecciones DESC, f.nombre;

-- Q11. Movimientos de inventario por bodega y tipo en el tercer trimestre de 2026 en adelante
SELECT b.nombre AS bodega, m.tipo, COUNT(*) AS movimientos, SUM(m.cantidad) AS unidades
FROM movimiento_inventario m
JOIN bodega b ON b.id_bodega = m.id_bodega
WHERE m.fecha >= '2026-07-01'
GROUP BY b.id_bodega, b.nombre, m.tipo
ORDER BY b.id_bodega, m.tipo;

-- Q12. ¿Cuántas inspecciones con observaciones o no conformes hizo cada inspector?
SELECT f.nombre AS inspector, ins.resultado, COUNT(*) AS inspecciones
FROM inspeccion ins
JOIN funcionario f ON f.id_funcionario = ins.id_funcionario
WHERE ins.resultado IN ('Con observaciones', 'No conforme')
GROUP BY f.nombre, ins.resultado
ORDER BY inspecciones DESC, f.nombre;

-- Q13. Mercancía retenida por bodega: lotes y valor aproximado (cantidad x valor unitario)
SELECT b.nombre AS bodega, b.tipo, COUNT(*) AS lotes_retenidos,
       SUM(i.cantidad * p.valor_unitario) AS valor_aprox_usd
FROM inventario i
JOIN bodega b   ON b.id_bodega   = i.id_bodega
JOIN producto p ON p.id_producto = i.id_producto
WHERE i.estado = 'Retenido'
GROUP BY b.id_bodega, b.nombre, b.tipo
ORDER BY valor_aprox_usd DESC;
