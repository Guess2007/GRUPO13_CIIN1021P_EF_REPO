/* =============================================================================
   AtencionesSalud - Dominio REEMBOLSOS
   1.4.  FUNCION ESCALAR
   Independiente de las secciones anteriores; se puede crear en cualquier
   momento (no depende de que existan filas cargadas, solo de que exista la
   base de datos).
   ============================================================================= */

USE AtencionesSalud;
GO

/* -----------------------------------------------------------------------------
   reembolsos.fn_ClasificarMonto  (funcion escalar)
   Proposito:
     Traducir un monto pagado a un rango legible para reportes (analogo a
     dbo.fn_GrupoEtario, pero para el dominio de reembolsos), sin repetir esta
     logica de clasificacion en cada consulta o aplicacion.
   Parametros:
     @Monto DECIMAL(12,2) - el monto pagado de una fila de reembolsos.Reembolso.
   Valor de retorno:
     VARCHAR(20) con el rango ('Hasta S/200', 'S/200 a S/1,000',
     'S/1,000 a S/5,000', 'Mas de S/5,000').
   Comportamiento ante excepciones:
     Es una funcion determinista de solo calculo (sin acceso a tablas). Un
     @Monto NULL o negativo no produce un error: cae en la rama ELSE final
     ('Sin clasificar'), en vez de interrumpir la consulta que la invoca.
   ----------------------------------------------------------------------------- */
CREATE FUNCTION reembolsos.fn_ClasificarMonto
(
    @Monto DECIMAL(12,2)
)
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @Rango VARCHAR(20);

    IF @Monto IS NULL OR @Monto < 0
        SET @Rango = 'Sin clasificar';
    ELSE IF @Monto <= 200
        SET @Rango = 'Hasta S/200';
    ELSE IF @Monto <= 1000
        SET @Rango = 'S/200 a S/1,000';
    ELSE IF @Monto <= 5000
        SET @Rango = 'S/1,000 a S/5,000';
    ELSE
        SET @Rango = 'Mas de S/5,000';

    RETURN @Rango;
END
GO
