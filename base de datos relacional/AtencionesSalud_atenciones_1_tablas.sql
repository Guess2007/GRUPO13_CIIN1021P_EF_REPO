/* =============================================================================
   AtencionesSalud - Dominio ATENCIONES DE SALUD
   1.1.  TABLAS
   Incluye: el modelo dimensional (Red, Microred, Provincia, Distrito,
   CategoriaEstablecimiento, Establecimiento, TipoEdad, Etnia, TipoSeguro,
   Ups), la tabla de hechos Atencion, la tabla de staging para la carga desde
   el CSV, y las tablas de soporte para auditoria, control de errores de carga
   y cierre de periodos (las usan los procedimientos y triggers de las
   secciones 1.2 y 1.3 de este mismo dominio).
   Ejecutar PRIMERO que AtencionesSalud_reembolsos_1_tablas.sql, porque ese
   script extiende dbo.Provincia con dbo.Region, y dbo.Provincia se crea aqui.
   ============================================================================= */

USE AtencionesSalud;
GO

/* #############################################################################
   1.1.  TABLAS
   Tablas del modelo (dimensiones + tabla de hechos), la tabla de staging usada
   para la carga desde el CSV, y las tablas de soporte para auditoria, control
   de errores de carga y cierre de periodos.
   ############################################################################# */
GO

-- ---------- Dimensiones geograficas / organizativas ----------

CREATE TABLE dbo.Red (
    RedId   SMALLINT     IDENTITY(1,1) NOT NULL,
    Nombre  NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Red        PRIMARY KEY (RedId),
    CONSTRAINT UQ_Red_Nombre UNIQUE (Nombre)
);

-- "NO PERTENECE A NINGUNA MICRORED" aparece en varias redes, por eso la microred depende de la red.
CREATE TABLE dbo.Microred (
    MicroredId INT           IDENTITY(1,1) NOT NULL,
    RedId      SMALLINT      NOT NULL,
    Nombre     NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Microred        PRIMARY KEY (MicroredId),
    CONSTRAINT UQ_Microred        UNIQUE (RedId, Nombre),
    CONSTRAINT FK_Microred_Red    FOREIGN KEY (RedId) REFERENCES dbo.Red (RedId)
);

CREATE TABLE dbo.Provincia (
    ProvinciaId SMALLINT     IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Provincia        PRIMARY KEY (ProvinciaId),
    CONSTRAINT UQ_Provincia_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.Distrito (
    DistritoId  INT          IDENTITY(1,1) NOT NULL,
    ProvinciaId SMALLINT     NOT NULL,
    Nombre      NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Distrito           PRIMARY KEY (DistritoId),
    CONSTRAINT UQ_Distrito           UNIQUE (ProvinciaId, Nombre),
    CONSTRAINT FK_Distrito_Provincia FOREIGN KEY (ProvinciaId) REFERENCES dbo.Provincia (ProvinciaId)
);

-- Categorias: I-1, I-2, I-3, I-4, II-1, II-2, II-E y '0' (sin categoria asignada)
CREATE TABLE dbo.CategoriaEstablecimiento (
    CategoriaId TINYINT     IDENTITY(1,1) NOT NULL,
    Codigo      VARCHAR(5)  NOT NULL,
    CONSTRAINT PK_CategoriaEstablecimiento        PRIMARY KEY (CategoriaId),
    CONSTRAINT UQ_CategoriaEstablecimiento_Codigo UNIQUE (Codigo)
);

-- CODIGO_UNICO es la clave natural; los nombres de establecimiento se repiten (18 casos), el codigo no.
CREATE TABLE dbo.Establecimiento (
    CodigoUnico   INT           NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    CategoriaId   TINYINT       NOT NULL,
    MicroredId    INT           NOT NULL,
    DistritoId    INT           NOT NULL,
    CONSTRAINT PK_Establecimiento           PRIMARY KEY (CodigoUnico),
    CONSTRAINT FK_Establecimiento_Categoria FOREIGN KEY (CategoriaId) REFERENCES dbo.CategoriaEstablecimiento (CategoriaId),
    CONSTRAINT FK_Establecimiento_Microred  FOREIGN KEY (MicroredId)  REFERENCES dbo.Microred (MicroredId),
    CONSTRAINT FK_Establecimiento_Distrito  FOREIGN KEY (DistritoId)  REFERENCES dbo.Distrito (DistritoId)
);

-- ---------- Catalogos ----------

CREATE TABLE dbo.TipoEdad (
    TipoEdad    CHAR(1)     NOT NULL,   -- A, M, D
    Descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_TipoEdad PRIMARY KEY (TipoEdad)
);

INSERT dbo.TipoEdad (TipoEdad, Descripcion) VALUES ('A', 'Años'), ('M', 'Meses'), ('D', 'Días');

CREATE TABLE dbo.Etnia (
    EtniaId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre  NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Etnia        PRIMARY KEY (EtniaId),
    CONSTRAINT UQ_Etnia_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.TipoSeguro (
    TipoSeguroId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre       NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_TipoSeguro        PRIMARY KEY (TipoSeguroId),
    CONSTRAINT UQ_TipoSeguro_Nombre UNIQUE (Nombre)
);

-- UPS = Unidad Productora de Servicios (93 valores distintos en el archivo)
CREATE TABLE dbo.Ups (
    UpsId  SMALLINT      IDENTITY(1,1) NOT NULL,
    Nombre NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Ups        PRIMARY KEY (UpsId),
    CONSTRAINT UQ_Ups_Nombre UNIQUE (Nombre)
);

-- ---------- Tabla de hechos ----------
-- Grano: una fila del CSV = combinacion de dia + establecimiento + UPS + sexo + edad + etnia + seguro.

CREATE TABLE dbo.Atencion (
    AtencionId   BIGINT   IDENTITY(1,1) NOT NULL,
    Fecha        DATE     NOT NULL,                 -- ANIO + MES + DIA
    CodigoUnico  INT      NOT NULL,
    UpsId        SMALLINT NOT NULL,
    EtniaId      TINYINT  NOT NULL,
    TipoSeguroId TINYINT  NOT NULL,
    Sexo         CHAR(1)  NOT NULL,
    EdadReg      SMALLINT NOT NULL,                 -- -1 = edad no registrada
    TipoEdad     CHAR(1)  NOT NULL,                 -- A = años, M = meses, D = días
    Atendidos    SMALLINT NOT NULL,                 -- personas atendidas
    Atenciones   SMALLINT NOT NULL,                 -- numero de atenciones
    FechaCorte   DATE     NOT NULL,                 -- fecha de corte de la extraccion
    Anio AS YEAR(Fecha)  PERSISTED,
    Mes  AS MONTH(Fecha) PERSISTED,
    CONSTRAINT PK_Atencion               PRIMARY KEY CLUSTERED (AtencionId),
    CONSTRAINT FK_Atencion_Establecim    FOREIGN KEY (CodigoUnico)  REFERENCES dbo.Establecimiento (CodigoUnico),
    CONSTRAINT FK_Atencion_Ups           FOREIGN KEY (UpsId)        REFERENCES dbo.Ups (UpsId),
    CONSTRAINT FK_Atencion_Etnia         FOREIGN KEY (EtniaId)      REFERENCES dbo.Etnia (EtniaId),
    CONSTRAINT FK_Atencion_TipoSeguro    FOREIGN KEY (TipoSeguroId) REFERENCES dbo.TipoSeguro (TipoSeguroId),
    CONSTRAINT FK_Atencion_TipoEdad      FOREIGN KEY (TipoEdad)     REFERENCES dbo.TipoEdad (TipoEdad),
    CONSTRAINT CK_Atencion_Sexo          CHECK (Sexo IN ('F', 'M')),
    CONSTRAINT CK_Atencion_EdadReg       CHECK (EdadReg >= -1),
    CONSTRAINT CK_Atencion_Atendidos     CHECK (Atendidos >= 0),
    CONSTRAINT CK_Atencion_Atenciones    CHECK (Atenciones >= 0)
);

CREATE NONCLUSTERED INDEX IX_Atencion_Fecha
    ON dbo.Atencion (Fecha) INCLUDE (Atendidos, Atenciones);
CREATE NONCLUSTERED INDEX IX_Atencion_Establecimiento
    ON dbo.Atencion (CodigoUnico, Fecha);
CREATE NONCLUSTERED INDEX IX_Atencion_Ups
    ON dbo.Atencion (UpsId);
GO
GO

-- Tabla de staging (mismas columnas y orden que el CSV de origen)
CREATE TABLE dbo.stg_Atenciones (
    ANIO                   SMALLINT,
    MES                    TINYINT,
    DIA                    TINYINT,
    CATEGORIA              VARCHAR(10),
    RED                    NVARCHAR(100),
    MICRORED               NVARCHAR(150),
    CODIGO_UNICO           INT,
    NOMBRE_ESTACLECIMIENTO NVARCHAR(150),
    PROVINCIA              NVARCHAR(50),
    DISTRITO               NVARCHAR(50),
    EDAD_REG               SMALLINT,
    TIPO_EDAD              VARCHAR(10),
    SEXO                   VARCHAR(10),
    ETNIA                  NVARCHAR(50),
    TIPO_SEGURO            VARCHAR(20),
    UPS                    NVARCHAR(150),
    ATENDIDOS              SMALLINT,
    ATENCIONES             SMALLINT,
    FECHA_CORTE            CHAR(8)
);
GO
GO

-- Tablas de soporte para los procedimientos y triggers de las secciones 1.2 y 1.3
-- Identificador propio en staging, para poder trazar cada fila rechazada hasta su origen.
ALTER TABLE dbo.stg_Atenciones
    ADD StgId INT IDENTITY(1,1) NOT NULL;
GO

-- Log de ejecucion de los procesos de carga (uno por corrida de cada procedimiento).
CREATE TABLE dbo.LogCargaETL (
    LogId            BIGINT        IDENTITY(1,1) NOT NULL,
    Proceso          VARCHAR(100)  NOT NULL,
    FechaInicio      DATETIME2(0)  NOT NULL,
    FechaFin         DATETIME2(0)  NULL,
    FilasLeidas      INT           NULL,
    FilasInsertadas  INT           NULL,
    FilasRechazadas  INT           NULL,
    Estado           VARCHAR(20)   NOT NULL,   -- 'OK','ERROR','ERROR_PARCIAL'
    MensajeError     NVARCHAR(4000) NULL,
    UsuarioEjecucion SYSNAME       NOT NULL CONSTRAINT DF_LogCargaETL_Usuario DEFAULT (SUSER_SNAME()),
    CONSTRAINT PK_LogCargaETL PRIMARY KEY (LogId)
);

-- Detalle de filas de staging que no pasaron la validacion de negocio.
CREATE TABLE dbo.LogErroresValidacion (
    ErrorId       BIGINT        IDENTITY(1,1) NOT NULL,
    Proceso       VARCHAR(100)  NOT NULL,
    StgId         INT           NOT NULL,
    Campo         VARCHAR(50)   NOT NULL,
    ValorOriginal NVARCHAR(200) NULL,
    Motivo        NVARCHAR(200) NOT NULL,
    FechaRegistro DATETIME2(0)  NOT NULL CONSTRAINT DF_LogErroresValidacion_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LogErroresValidacion PRIMARY KEY (ErrorId)
);

-- Periodos (Anio/Mes) cerrados para edicion; el trigger de integridad la consulta.
CREATE TABLE dbo.PeriodoCerrado (
    Anio        SMALLINT NOT NULL,
    Mes         TINYINT  NOT NULL,
    FechaCierre DATE     NOT NULL CONSTRAINT DF_PeriodoCerrado_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_PeriodoCerrado PRIMARY KEY (Anio, Mes)
);

-- Auditoria de cambios sobre la tabla de hechos.
CREATE TABLE dbo.LogAuditoriaAtencion (
    AuditId             BIGINT       IDENTITY(1,1) NOT NULL,
    Operacion           CHAR(1)      NOT NULL,     -- I = insert, U = update, D = delete
    AtencionId          BIGINT       NOT NULL,
    CodigoUnico         INT          NOT NULL,
    Fecha               DATE         NOT NULL,
    Atendidos_Anterior  SMALLINT     NULL,
    Atendidos_Nuevo     SMALLINT     NULL,
    Atenciones_Anterior SMALLINT     NULL,
    Atenciones_Nuevo    SMALLINT     NULL,
    UsuarioBD           SYSNAME      NOT NULL,
    FechaHora           DATETIME2(0) NOT NULL CONSTRAINT DF_LogAuditoriaAtencion_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LogAuditoriaAtencion PRIMARY KEY (AuditId)
);
GO
