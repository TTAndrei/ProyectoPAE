import os
import sys

# Añadir el directorio raíz al path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import obtener_driver, inicializar_bd, cerrar_conexion
from app.config import NEO4J_DATABASE

def resetear_y_sembrar():
    driver = obtener_driver()
    print(f"Conectando a la base de datos '{NEO4J_DATABASE}' en Neo4j y limpiando datos existentes...")
    try:
        with driver.session(database=NEO4J_DATABASE) as session:
            # Borrar todos los nodos y relaciones
            session.run("MATCH (n) DETACH DELETE n")
            print("¡Limpieza completada con éxito!")
        
        print("Inicializando base de datos, creando restricciones y sembrando nuevos datos de prueba...")
        inicializar_bd()
        print("¡Base de datos inicializada y sembrada con éxito!")
    except Exception as e:
        print(f"Error al resetear la base de datos: {e}")
    finally:
        cerrar_conexion()

if __name__ == "__main__":
    resetear_y_sembrar()
