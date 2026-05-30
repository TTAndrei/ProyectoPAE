import os
import sys

# Añadir el directorio raíz al path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import obtener_conexion, inicializar_bd, cerrar_conexion
from app.config import NEO4J_DATABASE

def debug():
    inicializar_bd()
    with obtener_conexion() as session:
        # Create an order
        session.run("CREATE (o:Order {id: 'test-order-debug', status: 'pending'})")
        
        # Try to run the query
        actualizado_record = session.run(
            "MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o",
            {"id": "test-order-debug"}
        ).single()
        print("Record:", actualizado_record)
        if actualizado_record:
            print("o:", actualizado_record["o"])
            
        # Clean up
        session.run("MATCH (o:Order {id: 'test-order-debug'}) DETACH DELETE o")

if __name__ == "__main__":
    debug()
    cerrar_conexion()
