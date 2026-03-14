"""Pydantic models (request/response schemas)."""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, field_validator


# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: str
    username: str
    role: str
    name: str


class TokenResponse(BaseModel):
    token: str
    user: UserOut


# ── Orders ────────────────────────────────────────────────────────────────────

class OrderCreate(BaseModel):
    type: str
    address: str
    lat: float
    lng: float

    @field_validator("type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        if v not in ("delivery", "pickup"):
            raise ValueError("type must be 'delivery' or 'pickup'")
        return v


class OrderAssign(BaseModel):
    driver_id: str


class OrderRespond(BaseModel):
    accepted: bool


class OrderStatusUpdate(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def validate_status(cls, v: str) -> str:
        if v not in ("in_progress", "completed"):
            raise ValueError("status must be 'in_progress' or 'completed'")
        return v


class OrderOut(BaseModel):
    id: str
    type: str
    address: str
    lat: float
    lng: float
    status: str
    assigned_driver_id: Optional[str]
    estimated_extra_minutes: Optional[float]
    created_at: str
    updated_at: str


# ── Drivers ───────────────────────────────────────────────────────────────────

class LocationUpdate(BaseModel):
    lat: float
    lng: float
    heading: float = 0.0


class DriverOut(BaseModel):
    id: str
    username: str
    name: str
    lat: Optional[float]
    lng: Optional[float]
    heading: Optional[float]
    location_updated_at: Optional[str]


# ── Routes ────────────────────────────────────────────────────────────────────

class RouteOut(BaseModel):
    id: str
    driver_id: str
    order_ids: str
    status: str
    created_at: str
    updated_at: str
    orders: list[OrderOut] = []
