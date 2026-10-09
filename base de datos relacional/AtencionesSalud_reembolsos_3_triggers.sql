/* =============================================================================
   AtencionesSalud - Dominio REEMBOLSOS
   1.3.  TRIGGERS
   Requiere haber ejecutado antes AtencionesSalud_reembolsos_1_tablas.sql
   (usa reembolsos.LogAuditoriaReembolso).
   ============================================================================= */

USE AtencionesSalud;
GO

/* -----------------------------------------------------------------------------
   reembolsos.trg_Reembolso_Auditoria  (trigger DML de auditoria)
   Proposito:
     Igual que dbo.trg_Atencion_Auditoria, pero sobre reembolsos.Reembolso, y
     con mas motivo: aqui la medida es dinero (MontoPagado), no un conteo de
     personas, asi que dejar rastro de quien modifico un monto y cual era el
     valor anterior es mas critico. Registra cada INSERT/UPDATE/DELETE en
     reembolsos.LogAuditoriaReembolso, distinguiendo la operacion por la
     presencia de la fila en "inserted"/"deleted".
   Parametros:
     No aplica (usa las tablas logicas "inserted" y "deleted" de SQL Server).
   Comportamiento ante excepciones:
     Sin TRY/CATCH propio, a proposito: si el INSERT hacia el log fallara, el
     error debe abortar tambien la operacion original sobre Reembolso, para
     que nunca quede un cambio de monto sin auditar. Esa propagacion es el
     comportamiento por defecto de un trigger AFTER en SQL Server.
   ----------------------------------------------------------------------------- */
CREATE TRIGGER reembolsos.trg_Reembolso_Auditoria
ON reembolsos.Reembolso
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO reembolsos.LogAuditoriaReembolso
           (Operacion, ReembolsoId, Periodo, MontoPagado_Anterior, MontoPagado_Nuevo, UsuarioBD)
    SELECT 'I', i.ReembolsoId, i.Periodo, NULL, i.MontoPagado, SUSER_SNAME()
    FROM inserted i
    LEFT JOIN deleted d ON d.ReembolsoId = i.ReembolsoId
    WHERE d.ReembolsoId IS NULL

    UNION ALL

    SELECT 'U', i.ReembolsoId, i.Periodo, d.MontoPagado, i.MontoPagado, SUSER_SNAME()
    FROM inserted i
    JOIN deleted d ON d.ReembolsoId = i.ReembolsoId

    UNION ALL

    SELECT 'D', d.ReembolsoId, d.Periodo, d.MontoPagado, NULL, SUSER_SNAME()
    FROM deleted d
    LEFT JOIN inserted i ON i.ReembolsoId = d.ReembolsoId
    WHERE i.ReembolsoId IS NULL;
END
GO
