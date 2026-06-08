from typing import Optional
from urllib.parse import quote_plus

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "GreenBrain Backend"
    app_env: str = "development"
    app_host: str = "0.0.0.0"
    app_port: int = 8000

    database_url: Optional[str] = None

    postgres_host: str = "postgres"
    postgres_port: int = 5432
    postgres_db: str = "greenbrain"
    postgres_user: str = "greenbrain"
    postgres_password: str = "greenbrain"
    postgres_sslmode: str = "disable"

    jwt_secret: str = "CHANGE_ME_dev_only_not_for_production"
    jwt_expire_minutes: int = 60

    # Supabase — required only for customer-ops endpoint (central hub)
    supabase_url: Optional[str] = None
    supabase_service_role_key: Optional[str] = None
    supabase_bucket: str = "ml-snapshots"

    # Source DB credential encryption.
    # Must be a Fernet key generated with:
    # python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    # Never reuse JWT_SECRET for credential encryption.
    source_db_secret_key: Optional[str] = None

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @model_validator(mode="after")
    def _resolve_database_url(self) -> "Settings":
        if self.database_url:
            if not self.database_url.startswith("postgresql+psycopg"):
                self.database_url = self.database_url.replace(
                    "postgresql://", "postgresql+psycopg://", 1
                )
        else:
            user = quote_plus(self.postgres_user)
            password = quote_plus(self.postgres_password)
            sslmode = (self.postgres_sslmode or "").strip()
            url = f"postgresql+psycopg://{user}:{password}@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
            if sslmode:
                url += f"?sslmode={sslmode}"
            self.database_url = url
        return self


settings = Settings()
