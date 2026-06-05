from fastapi import APIRouter, Depends, HTTPException, status

from app.auth import obtener_usuario_actual, requerir_central
from app.database import obtener_conexion
from app.schemas import (
    ActualizarEstadoPedido,
    AsignarPedido,
    CrearPedido,
    PedidoRespuesta,
    ResponderPedido,
    RutaRespuesta,
)
from app.services.order_workflow import (
    actualizar_estado_pedido as ejecutar_actualizar_estado_pedido,
    asignar_pedido as ejecutar_asignar_pedido,
    crear_pedido as ejecutar_crear_pedido,
    obtener_ruta_repartidor as ejecutar_obtener_ruta_repartidor,
    responder_pedido as ejecutar_responder_pedido,
)

enrutador = APIRouter(prefix="/orders", tags=["pedidos"])


@enrutador.get("/", response_model=list[PedidoRespuesta])
def listar_pedidos(usuario_actual: dict = Depends(obtener_usuario_actual)):
    with obtener_conexion() as session:
        if usuario_actual["role"] == "central":
            result = session.run(
                """
                MATCH (o:Order)
                OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
                WITH o, collect(u.id) AS assigned_ids
                RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o,
                       head(assigned_ids) AS assigned_driver_id
                ORDER BY o.created_at DESC
                """
            )
        else:
            result = session.run(
                """
                MATCH (o:Order)
                OPTIONAL MATCH (asignado_a_mi:User {id: $uid})-[:ASSIGNED_TO]->(o)
                WHERE asignado_a_mi IS NOT NULL OR o.status = 'pending'
                WITH DISTINCT o
                OPTIONAL MATCH (asignado:User)-[:ASSIGNED_TO]->(o)
                WITH o, collect(asignado.id) AS assigned_ids
                RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o,
                       head(assigned_ids) AS assigned_driver_id
                ORDER BY o.created_at DESC
                """,
                {"uid": usuario_actual["id"]},
            )

        pedidos = []
        for record in result:
            pedido = dict(record["o"])
            pedido["assigned_driver_id"] = record["assigned_driver_id"]
            pedidos.append(pedido)
        return pedidos


@enrutador.post("/", response_model=PedidoRespuesta, status_code=status.HTTP_201_CREATED)
async def crear_pedido(cuerpo: CrearPedido, _: dict = Depends(requerir_central)):
    return await ejecutar_crear_pedido(cuerpo)


@enrutador.post("/{id_pedido}/assign")
async def asignar_pedido(
    id_pedido: str,
    cuerpo: AsignarPedido,
    _: dict = Depends(requerir_central),
):
    return await ejecutar_asignar_pedido(id_pedido, cuerpo.driver_id)


@enrutador.post("/{id_pedido}/respond")
async def responder_pedido(
    id_pedido: str,
    cuerpo: ResponderPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    if usuario_actual["role"] != "repartidor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo los repartidores pueden responder a pedidos",
        )

    return await ejecutar_responder_pedido(
        id_pedido,
        usuario_actual["id"],
        cuerpo.accepted,
    )


@enrutador.patch("/{id_pedido}/status")
def actualizar_estado_pedido(
    id_pedido: str,
    cuerpo: ActualizarEstadoPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    return ejecutar_actualizar_estado_pedido(
        id_pedido,
        cuerpo.status,
        usuario_actual,
    )


@enrutador.get("/route/{id_repartidor}", response_model=RutaRespuesta)
def obtener_ruta_repartidor(
    id_repartidor: str,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    if usuario_actual["role"] != "central" and (
        usuario_actual["role"] != "repartidor" or usuario_actual["id"] != id_repartidor
    ):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    return ejecutar_obtener_ruta_repartidor(id_repartidor)
