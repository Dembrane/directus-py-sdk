from typing import Optional, Dict, Any


class DirectusAuthError(Exception):
    """Exception raised for authentication errors from Directus API."""

    def __init__(
        self,
        message: str,
        code: Optional[str] = None,
        extensions: Optional[Dict[str, Any]] = None,
    ):
        self.message = message
        self.code = code
        self.extensions = extensions or {}
        super().__init__(self.message)
