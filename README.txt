PROYECTO DATASALUD PERÚ - PASOS 4, 5 Y 6
=========================================

Archivos:

1) 04_preparar_mongodb.py
   Convierte Atenciones_atendidos_2023-dires.csv a JSON Lines para MongoDB.
   Ejemplo:
   python 04_preparar_mongodb.py --input Atenciones_atendidos_2023-dires.csv --output atenciones_salud.jsonl

2) 04_mongodb_crud.js
   Crea la colección, índices y operaciones CRUD documentadas.
   Ejecutar con mongosh después de importar el JSONL.

3) 05_dw_ddl.sql
   Crea el Data Warehouse Kimball en SQL Server: 1 tabla de hechos + 4 dimensiones + ETL_Log.

4) 05_etl_dw.py
   ETL con pandas. Limpia el dataset y puede exportar tablas dimensionales o cargarlas a SQL Server.

5) 06_powerbi_medidas.dax
   Medidas DAX para construir los KPIs del dashboard.

6) 06_diseno_dashboard.md
   Diseño del dashboard, OLAP, preguntas de negocio y gobernanza de KPIs.

7) Informe_Pasos_4_5_6.docx
   Texto listo para insertar en las secciones [1.4], [1.5] y [1.6] del informe grupal.

NOTA SOBRE EL DATASET
---------------------
El archivo Atenciones_atendidos_2023-dires.csv contiene principalmente datos de provincias de San Martín,
no de La Libertad. Por ello, en el informe se presenta como prototipo técnico basado en datos reales del
sector salud y se evita afirmar que sus indicadores representan a DIRESA La Libertad.
El archivo de reembolsos sí contiene registros de LA LIBERTAD, pero su volumen es mucho menor.
