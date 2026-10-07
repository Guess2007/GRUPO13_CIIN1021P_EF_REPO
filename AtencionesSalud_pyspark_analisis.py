"""
AtencionesSalud - Analisis con PySpark (RDD + DataFrame + SparkSQL)
Dataset: Atenciones_atendidos_2023-dires.csv (DIRES San Martin, 1,048,575 filas)

Mismo objetivo que la seccion de plan de ejecucion en SQL Server: total de
ATENDIDOS/ATENCIONES filtrando por TIPO_SEGURO = 'S.I.S' y un rango de fechas
de enero 2023, para poder comparar motores sobre la MISMA consulta.
"""
import time
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

CSV_PATH = "/mnt/user-data/uploads/Atenciones_atendidos_2023-dires.csv"

# ---------------------------------------------------------------------------
# 0) Arranque de la sesion de Spark (JVM) - se mide aparte porque en un
#    pipeline real este costo se paga una sola vez por sesion, no por consulta.
# ---------------------------------------------------------------------------
t0 = time.perf_counter()
spark = (
    SparkSession.builder
    .appName("AtencionesSalud-Analisis")
    .master("local[*]")          # un solo nodo: todos los cores disponibles en ESTE entorno
    .config("spark.driver.memory", "2g")
    .config("spark.sql.shuffle.partitions", "8")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("ERROR")
t_startup = time.perf_counter() - t0
print(f"[0] Arranque de SparkSession: {t_startup:.2f} s  (cores asignados: {spark.sparkContext.defaultParallelism})")

# ---------------------------------------------------------------------------
# 1) DATAFRAME: leer el CSV con esquema explicito (evita inferSchema, que
#    obliga a Spark a leer el archivo dos veces).
# ---------------------------------------------------------------------------
from pyspark.sql.types import StructType, StructField, IntegerType, StringType

schema = StructType([
    StructField("ANIO", IntegerType()), StructField("MES", IntegerType()), StructField("DIA", IntegerType()),
    StructField("CATEGORIA", StringType()), StructField("RED", StringType()), StructField("MICRORED", StringType()),
    StructField("CODIGO_UNICO", IntegerType()), StructField("NOMBRE_ESTACLECIMIENTO", StringType()),
    StructField("PROVINCIA", StringType()), StructField("DISTRITO", StringType()),
    StructField("EDAD_REG", IntegerType()), StructField("TIPO_EDAD", StringType()), StructField("SEXO", StringType()),
    StructField("ETNIA", StringType()), StructField("TIPO_SEGURO", StringType()), StructField("UPS", StringType()),
    StructField("ATENDIDOS", IntegerType()), StructField("ATENCIONES", IntegerType()),
    StructField("FECHA_CORTE", StringType()),
])

t0 = time.perf_counter()
df = spark.read.csv(CSV_PATH, sep=";", header=True, schema=schema, encoding="UTF-8")
df = df.withColumn("Fecha", F.to_date(F.concat_ws("-", "ANIO", F.lpad("MES", 2, "0"), F.lpad("DIA", 2, "0"))))
df = df.withColumn("TIPO_SEGURO", F.trim("TIPO_SEGURO"))
df.cache()
n_rows = df.count()   # fuerza la materializacion (lectura real del archivo) para medir el costo real
t_read = time.perf_counter() - t0
print(f"[1] Lectura + cache del CSV (DataFrame): {t_read:.2f} s  ({n_rows:,} filas)")

# ---------------------------------------------------------------------------
# 2) DATAFRAME API - consulta critica (frio: primera ejecucion tras cache)
# ---------------------------------------------------------------------------
def consulta_dataframe():
    return (
        df.filter((F.col("TIPO_SEGURO") == "S.I.S") &
                   (F.col("Fecha").between("2023-01-01", "2023-01-31")))
          .groupBy("TIPO_SEGURO")
          .agg(F.count("*").alias("Registros"),
               F.sum("ATENDIDOS").alias("TotalAtendidos"),
               F.sum("ATENCIONES").alias("TotalAtenciones"))
          .collect()
    )

tiempos_df = []
for i in range(5):
    t0 = time.perf_counter()
    res_df = consulta_dataframe()
    tiempos_df.append(time.perf_counter() - t0)
print(f"[2] DataFrame API - resultado: {res_df}")
print(f"    tiempos (s): {[round(t,4) for t in tiempos_df]}  min={min(tiempos_df):.4f}  prom={sum(tiempos_df)/5:.4f}")

# ---------------------------------------------------------------------------
# 3) SPARK SQL - misma consulta, escrita en SQL puro sobre una vista temporal
# ---------------------------------------------------------------------------
df.createOrReplaceTempView("atenciones")

def consulta_sparksql():
    return spark.sql("""
        SELECT TIPO_SEGURO,
               COUNT(*) AS Registros,
               SUM(ATENDIDOS) AS TotalAtendidos,
               SUM(ATENCIONES) AS TotalAtenciones
        FROM atenciones
        WHERE TIPO_SEGURO = 'S.I.S' AND Fecha BETWEEN '2023-01-01' AND '2023-01-31'
        GROUP BY TIPO_SEGURO
    """).collect()

tiempos_sql = []
for i in range(5):
    t0 = time.perf_counter()
    res_sql = consulta_sparksql()
    tiempos_sql.append(time.perf_counter() - t0)
print(f"[3] SparkSQL - resultado: {res_sql}")
print(f"    tiempos (s): {[round(t,4) for t in tiempos_sql]}  min={min(tiempos_sql):.4f}  prom={sum(tiempos_sql)/5:.4f}")

# ---------------------------------------------------------------------------
# 4) RDD - estadistica descriptiva de EDAD_REG calculada "a mano" con
#    map/reduce (no con .describe(), para demostrar el API de bajo nivel).
# ---------------------------------------------------------------------------
t0 = time.perf_counter()
rdd = df.select("EDAD_REG").filter(F.col("EDAD_REG") >= 0).rdd.map(lambda r: r["EDAD_REG"])
rdd.cache()
n = rdd.count()

suma = rdd.reduce(lambda a, b: a + b)
media = suma / n

suma_sq_diff = rdd.map(lambda x: (x - media) ** 2).reduce(lambda a, b: a + b)
desviacion = (suma_sq_diff / n) ** 0.5

edad_min = rdd.reduce(lambda a, b: min(a, b))
edad_max = rdd.reduce(lambda a, b: max(a, b))
t_rdd = time.perf_counter() - t0

print(f"[4] RDD - estadistica descriptiva de EDAD_REG (excluyendo -1, n={n:,}):")
print(f"    media={media:.2f}  desviacion_estandar={desviacion:.2f}  min={edad_min}  max={edad_max}")
print(f"    tiempo total RDD (count+reduce x4): {t_rdd:.2f} s")

# ---------------------------------------------------------------------------
# 5) Resumen final para el informe
# ---------------------------------------------------------------------------
print("\n=== RESUMEN ===")
print(f"Arranque SparkSession : {t_startup:.2f} s")
print(f"Lectura CSV + cache   : {t_read:.2f} s  ({n_rows:,} filas, {spark.sparkContext.defaultParallelism} particiones logicas)")
print(f"Consulta critica (DF) : min {min(tiempos_df)*1000:.1f} ms | prom {sum(tiempos_df)/5*1000:.1f} ms")
print(f"Consulta critica (SQL): min {min(tiempos_sql)*1000:.1f} ms | prom {sum(tiempos_sql)/5*1000:.1f} ms")
print(f"Stats RDD EDAD_REG    : {t_rdd*1000:.1f} ms")

spark.stop()
