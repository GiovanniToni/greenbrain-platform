from .storage_interface import StorageInterface
from .factory import get_storage
from .backend import get_storage_backend  # backward-compat

__all__ = ["StorageInterface", "get_storage", "get_storage_backend"]
