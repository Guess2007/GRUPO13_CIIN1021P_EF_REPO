// PASO 4 - MongoDB: colección semiestructurada y operaciones CRUD
// Ejecutar en mongosh después de importar atenciones_salud.jsonl

use DataSaludPeru;

// Crear colección con validación básica
try { db.atenciones_salud.drop(); } catch (e) {}

db.createCollection("atenciones_salud", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["fecha", "establecimiento", "paciente", "ups", "atendidos", "atenciones"],
      properties: {
        fecha: { bsonType: "date" },
        establecimiento: {
          bsonType: "object",
          required: ["codigo", "nombre"],
          properties: {
            codigo: { bsonType: ["int", "long"] },
            nombre: { bsonType: "string" },
            categoria: { bsonType: "string" },
            red: { bsonType: "string" },
            microred: { bsonType: "string" },
            provincia: { bsonType: "string" },
            distrito: { bsonType: "string" }
          }
        },
        paciente: {
          bsonType: "object",
          properties: {
            edad: { bsonType: ["int", "null"] },
            tipoEdad: { bsonType: "string" },
            sexo: { bsonType: "string" },
            etnia: { bsonType: "string" },
            seguro: { bsonType: "string" }
          }
        },
        ups: { bsonType: "string" },
        atendidos: { bsonType: ["int", "long"] },
        atenciones: { bsonType: ["int", "long"] },
        fechaCorte: { bsonType: "string" }
      }
    }
  },
  validationLevel: "moderate"
});

// Índices útiles para consultas analíticas
// (se crean tras la importación)
db.atenciones_salud.createIndex({ "establecimiento.provincia": 1 });
db.atenciones_salud.createIndex({ "establecimiento.codigo": 1 });
db.atenciones_salud.createIndex({ "paciente.seguro": 1 });
db.atenciones_salud.createIndex({ ups: 1, fecha: 1 });

// CREATE: documento de prueba
const insercion = db.atenciones_salud.insertOne({
  fecha: ISODate("2023-01-01T00:00:00Z"),
  establecimiento: {
    codigo: 6488,
    nombre: "SANTA MARTHA",
    categoria: "I-1",
    red: "EL DORADO",
    microred: "AGUA BLANCA",
    provincia: "EL DORADO",
    distrito: "SANTA ROSA"
  },
  paciente: {
    edad: 4,
    tipoEdad: "A",
    sexo: "F",
    etnia: "Kichwa",
    seguro: "S.I.S"
  },
  ups: "ENFERMERIA",
  atendidos: 0,
  atenciones: 3,
  fechaCorte: "20231220",
  origen: "registro_prueba_crud"
});
print("CREATE - _id: " + insercion.insertedId);

// READ: atenciones SIS en una provincia
db.atenciones_salud.find(
  {
    "paciente.seguro": "S.I.S",
    "establecimiento.provincia": "EL DORADO"
  },
  {
    _id: 0,
    fecha: 1,
    "establecimiento.nombre": 1,
    "paciente.sexo": 1,
    ups: 1,
    atenciones: 1
  }
).limit(10);

// READ agregado: total de atenciones por provincia
db.atenciones_salud.aggregate([
  {
    $group: {
      _id: "$establecimiento.provincia",
      totalAtenciones: { $sum: "$atenciones" },
      totalAtendidos: { $sum: "$atendidos" }
    }
  },
  { $sort: { totalAtenciones: -1 } }
]);

// UPDATE: modificar el documento creado como prueba
const actualizacion = db.atenciones_salud.updateOne(
  { _id: insercion.insertedId },
  { $set: { "establecimiento.categoria": "I-1 ACTUALIZADA", actualizadoPor: "equipo_proyecto" } }
);
print("UPDATE - modificados: " + actualizacion.modifiedCount);

// Verificación de UPDATE
db.atenciones_salud.findOne({ _id: insercion.insertedId });

// DELETE: retirar solamente el documento de prueba
const eliminacion = db.atenciones_salud.deleteOne({ _id: insercion.insertedId });
print("DELETE - eliminados: " + eliminacion.deletedCount);

// Consulta de control final
print("Documentos actuales: " + db.atenciones_salud.countDocuments({}));
