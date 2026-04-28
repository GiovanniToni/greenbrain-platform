import os
from sqlalchemy import create_engine, text
from app.core.security import hash_password


def required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required env var: {name}")
    return value


def main() -> None:
    database_url = required("DATABASE_URL")
    if database_url.startswith("postgresql://"):
        database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    email = required("LOCAL_CUSTOMER_EMAIL").strip().lower()
    full_name = os.getenv("LOCAL_CUSTOMER_FULL_NAME", "Cliente GreenBrain").strip()
    temp_password = required("LOCAL_CUSTOMER_TEMP_PASSWORD")
    tenant_code = required("LOCAL_CUSTOMER_TENANT_CODE").strip()
    home_host = required("LOCAL_CUSTOMER_HOME_HOST").strip()
    home_path = os.getenv("LOCAL_CUSTOMER_HOME_PATH", "/dashboard").strip()

    hashed = hash_password(temp_password)
    engine = create_engine(database_url)

    with engine.begin() as conn:
        conn.execute(
            text("""
                INSERT INTO public.greenbrain_users (
                    email, hashed_password, full_name, is_active, is_admin,
                    tenant_code, home_host, home_path, user_role, can_access_app
                )
                VALUES (
                    :email, :hashed_password, :full_name, true, true,
                    :tenant_code, :home_host, :home_path, 'customer_admin', true
                )
                ON CONFLICT (email) DO UPDATE SET
                    full_name = EXCLUDED.full_name,
                    tenant_code = EXCLUDED.tenant_code,
                    home_host = EXCLUDED.home_host,
                    home_path = EXCLUDED.home_path,
                    user_role = EXCLUDED.user_role,
                    can_access_app = true,
                    is_active = true;
            """),
            {
                "email": email,
                "hashed_password": hashed,
                "full_name": full_name,
                "tenant_code": tenant_code,
                "home_host": home_host,
                "home_path": home_path,
            },
        )


    print(f"Provisioned local customer user: {email}")


if __name__ == "__main__":
    main()
