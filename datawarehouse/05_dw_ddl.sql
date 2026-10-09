-- PASO 5 - Data Warehouse Kimball para atenciones de salud
-- Motor: Microsoft SQL Server

IF DB_ID('DW_DataSaludPeru') IS NULL
    CREATE DATABASE DW_DataSaludPeru;
GO
USE DW_DataSaludPeru;
GO

-- El orden de DROP permite volver a ejecutar el script en laboratorio.
IF OBJECT_ID('dbo.FactAtenciones', 'U') IS NOT NULL DROP TABLE dbo.FactAtenciones;
IF OBJECT_ID('dbo.DimServicio', 'U') IS NOT NULL DROP TABLE dbo.DimServicio;
IF OBJECT_ID('dbo.DimPaciente', 'U') IS NOT NULL DROP TABLE dbo.DimPaciente;
IF OBJECT_ID('dbo.DimEstablecimiento', 'U') IS NOT NULL DROP TABLE dbo.DimEstablecimiento;
IF OBJECT_ID('dbo.DimTiempo', 'U') IS NOT NULL DROP TABLE dbo.DimTiempo;
IF OBJECT_ID('dbo.ETL_Log', 'U') IS NOT NULL DROP TABLE dbo.ETL_Log;
GO

CREATE TABLE dbo.DimTiempo (
    IdTiempo INT IDENTITY(1,1) PRIMARY KEY,
    Fecha DATE NOT NULL UNIQUE,
    Anio SMALLINT NOT NULL,
    Mes TINYINT NOT NULL,
    Dia TINYINT NOT NULL,
    Trimestre TINYINT NOT NULL,
    NombreMes VARCHAR(15) NOT NULL
);
GO

CREATE TABLE dbo.DimEstablecimiento (
    IdEstablecimiento INT IDENTITY(1,1) PRIMARY KEY,
    CodigoUnico INT NOT NULL UNIQUE,
    NombreEstablecimiento NVARCHAR(200) NOT NULL,
    Categoria VARCHAR(30) NULL,
    Red NVARCHAR(120) NULL,
    Microred NVARCHAR(120) NULL,
    Provincia NVARCHAR(120) NULL,
    Distrito NVARCHAR(120) NULL
);
GO

CREATE TABLE dbo.DimPaciente (
    IdPaciente INT IDENTITY(1,1) PRIMARY KEY,
    Edad INT NULL,
    TipoEdad VARCHAR(20) NULL,
    Sexo VARCHAR(20) NULL,
    Etnia NVARCHAR(100) NULL,
    TipoSeguro NVARCHAR(100) NULL,
    CONSTRAINT UQ_DimPaciente UNIQUE (Edad, TipoEdad, Sexo, Etnia, TipoSeguro)
);
GO

CREATE TABLE dbo.DimServicio (
    IdServicio INT IDENTITY(1,1) PRIMARY KEY,
    UPS NVARCHAR(200) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.FactAtenciones (
    IdHecho BIGINT IDENTITY(1,1) PRIMARY KEY,
    IdTiempo INT NOT NULL,
    IdEstablecimiento INT NOT NULL,
    IdPaciente INT NOT NULL,
    IdServicio INT NOT NULL,
    Atendidos INT NOT NULL,
    Atenciones INT NOT NULL,
    FechaCorte CHAR(8) NULL,
    CONSTRAINT FK_Fact_Tiempo FOREIGN KEY (IdTiempo) REFERENCES dbo.DimTiempo(IdTiempo),
    CONSTRAINT FK_Fact_Establecimiento FOREIGN KEY (IdEstablecimiento) REFERENCES dbo.DimEstablecimiento(IdEstablecimiento),
    CONSTRAINT FK_Fact_Paciente FOREIGN KEY (IdPaciente) REFERENCES dbo.DimPaciente(IdPaciente),
    CONSTRAINT FK_Fact_Servicio FOREIGN KEY (IdServicio) REFERENCES dbo.DimServicio(IdServicio),
    CONSTRAINT CK_Fact_Atendidos CHECK (Atendidos >= 0),
    CONSTRAINT CK_Fact_Atenciones CHECK (Atenciones >= 0)
);
GO

CREATE INDEX IX_FactAtenciones_Tiempo ON dbo.FactAtenciones(IdTiempo);
CREATE INDEX IX_FactAtenciones_Establecimiento ON dbo.FactAtenciones(IdEstablecimiento);
CREATE INDEX IX_FactAtenciones_Servicio ON dbo.FactAtenciones(IdServicio);
CREATE INDEX IX_DimEstablecimiento_ProvinciaDistrito
    ON dbo.DimEstablecimiento(Provincia, Distrito);
GO

CREATE TABLE dbo.ETL_Log (
    IdLog BIGINT IDENTITY(1,1) PRIMARY KEY,
    FechaHora DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    Etapa VARCHAR(40) NOT NULL,
    FilasEntrada BIGINT NULL,
    FilasSalida BIGINT NULL,
    Detalle NVARCHAR(1000) NULL
);
GO
