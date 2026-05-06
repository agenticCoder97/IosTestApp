"""Canonical app endpoint catalog for monitor request tables."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class EndpointSpec:
    method: str
    path: str


MAIN_APP_ENDPOINTS: tuple[EndpointSpec, ...] = (
    EndpointSpec("GET", "/api/v1/health"),
    EndpointSpec("GET", "/api/v1/comics"),
    EndpointSpec("GET", "/api/v1/comics/{id}"),
    EndpointSpec("PATCH", "/api/v1/comics/{id}"),
    EndpointSpec("DELETE", "/api/v1/comics/{id}"),
    EndpointSpec("POST", "/api/v1/comics/{id}/archive"),
    EndpointSpec("POST", "/api/v1/comics/{id}/unarchive"),
    EndpointSpec("DELETE", "/api/v1/comics/{id}/permanent"),
    EndpointSpec("GET", "/api/v1/comics/{id}/chapters/{id}/pages"),
    EndpointSpec("GET", "/api/v1/fanfic"),
    EndpointSpec("GET", "/api/v1/fanfic/{id}"),
    EndpointSpec("DELETE", "/api/v1/fanfic/{id}"),
    EndpointSpec("DELETE", "/api/v1/fanfic/{id}/permanent"),
    EndpointSpec("GET", "/api/v1/fanfic/{id}/chapters/{id}"),
    EndpointSpec("GET", "/api/v1/fanfic-thumbnails/random"),
    EndpointSpec("POST", "/api/v1/scrape/comic"),
    EndpointSpec("POST", "/api/v1/scrape/fanfic"),
    EndpointSpec("GET", "/api/v1/scrape"),
    EndpointSpec("GET", "/api/v1/scrape/{id}"),
    EndpointSpec("POST", "/api/v1/scrape/{id}/retry"),
    EndpointSpec("POST", "/api/v1/scrape/{id}/update"),
    EndpointSpec("GET", "/api/v1/scrape/{id}/logs"),
    EndpointSpec("GET", "/api/v1/progress"),
    EndpointSpec("PUT", "/api/v1/progress/comic/{id}"),
    EndpointSpec("PUT", "/api/v1/progress/fanfic/{id}"),
    EndpointSpec("GET", "/api/v1/progress/{type}/{id}"),
    EndpointSpec("GET", "/api/v1/authors/{id}"),
    EndpointSpec("GET", "/api/v1/stats"),
)

MAIN_APP_ENDPOINT_KEYS = frozenset((endpoint.method, endpoint.path) for endpoint in MAIN_APP_ENDPOINTS)


def is_main_app_endpoint(method: str, path: str) -> bool:
    return (method.upper(), path) in MAIN_APP_ENDPOINT_KEYS
