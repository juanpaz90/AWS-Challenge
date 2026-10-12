"""HTTP routes: service info, probes, metrics and CRUD for notes."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from notes_api.db import get_session
from notes_api.models import Note
from notes_api.schemas import NoteCreate, NoteRead, NoteUpdate, ServiceInfo

logger = logging.getLogger(__name__)

SessionDep = Annotated[Session, Depends(get_session)]

system = APIRouter(tags=["system"])
notes = APIRouter(prefix="/notes", tags=["notes"])


@system.get("/", response_model=ServiceInfo)
def service_info(request: Request) -> ServiceInfo:
    settings = request.app.state.settings
    return ServiceInfo(
        service="notes-api",
        message=settings.app_message,
        version=settings.app_version,
        pod=settings.pod_name,
    )


@system.get("/healthz")
def liveness() -> dict[str, str]:
    """Liveness: the process is up and serving. Deliberately does not touch the database."""
    return {"status": "ok"}


@system.get("/readyz")
def readiness(session: SessionDep, response: Response) -> dict[str, str]:
    """Readiness: only accept traffic while the database is reachable."""
    try:
        session.execute(text("SELECT 1"))
    except Exception:
        logger.warning("readiness check failed: database unreachable", exc_info=True)
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "unavailable", "database": "unreachable"}
    return {"status": "ok", "database": "ok"}


@system.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def _get_or_404(session: Session, note_id: int) -> Note:
    note = session.get(Note, note_id)
    if note is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=f"note {note_id} not found")
    return note


@notes.get("", response_model=list[NoteRead])
def list_notes(
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Note]:
    return list(session.scalars(select(Note).order_by(Note.id).limit(limit).offset(offset)))


@notes.post("", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def create_note(payload: NoteCreate, session: SessionDep) -> Note:
    note = Note(title=payload.title, content=payload.content)
    session.add(note)
    session.commit()
    session.refresh(note)
    logger.info("note created", extra={"note_id": note.id})
    return note


@notes.get("/{note_id}", response_model=NoteRead)
def get_note(note_id: int, session: SessionDep) -> Note:
    return _get_or_404(session, note_id)


@notes.patch("/{note_id}", response_model=NoteRead)
def update_note(note_id: int, payload: NoteUpdate, session: SessionDep) -> Note:
    note = _get_or_404(session, note_id)
    for field, value in payload.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(note, field, value)
    session.commit()
    session.refresh(note)
    return note


@notes.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, session: SessionDep) -> Response:
    session.delete(_get_or_404(session, note_id))
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
