"""Authentication router."""
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import get_connection
from app.schemas import LoginRequest, TokenResponse, UserOut
from app.auth import pwd_ctx, create_access_token, get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest):
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM users WHERE username = ?", (body.username,)
    ).fetchone()

    if not row or not pwd_ctx.verify(body.password, row["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    user_data = {
        "id": row["id"],
        "username": row["username"],
        "role": row["role"],
        "name": row["name"],
    }
    token = create_access_token(user_data)
    return TokenResponse(token=token, user=UserOut(**user_data))


@router.get("/me", response_model=UserOut)
def me(current_user: dict = Depends(get_current_user)):
    return UserOut(
        id=current_user["id"],
        username=current_user["username"],
        role=current_user["role"],
        name=current_user["name"],
    )
