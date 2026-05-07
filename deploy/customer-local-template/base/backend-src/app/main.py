from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.api.v1.analytics import router as analytics_router
from app.api.v1.auth import router as auth_router
from app.api.v1.catalog import router as catalog_router
from app.api.v1.cloud_sync import router as cloud_sync_router
from app.api.v1.customer_ops import router as customer_ops_router
from app.api.v1.dashboard import router as dashboard_router
from app.api.v1.forecast import router as forecast_router
from app.api.v1.ops import router as ops_router
from app.api.v1.planner import router as planner_router
from app.api.v1.sales import router as sales_router
from app.api.v1.settings import router as settings_router
from app.api.v1.system import router as system_router
from app.api.v1.customer_provisioning import router as customer_provisioning_router
from app.api.v1.customer_runtime import router as customer_runtime_router
from app.api.v1.customer_delivery import router as customer_delivery_router
from app.api.v1.customer_onboarding import router as customer_onboarding_router
from app.api.v1.customer_portal import router as customer_portal_router
from app.api.v1.customer_billing import router as customer_billing_router
from app.core.config import settings

app = FastAPI(title=settings.app_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8081",
        "http://127.0.0.1:8081",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:8083",
        "http://127.0.0.1:8083",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:80",
        "http://127.0.0.1:80",
        "https://app.greenbrain.it",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(auth_router)
app.include_router(cloud_sync_router)
app.include_router(customer_ops_router)
app.include_router(customer_provisioning_router)
app.include_router(customer_runtime_router)
app.include_router(customer_delivery_router)
app.include_router(customer_onboarding_router)
app.include_router(customer_portal_router)
app.include_router(customer_billing_router)
app.include_router(settings_router)
app.include_router(system_router)
app.include_router(catalog_router)
app.include_router(forecast_router)
app.include_router(sales_router)
app.include_router(analytics_router)
app.include_router(planner_router)
app.include_router(ops_router)
app.include_router(dashboard_router)


@app.get("/")
def root():
    return {
        "app": settings.app_name,
        "env": settings.app_env,
        "status": "running",
    }
