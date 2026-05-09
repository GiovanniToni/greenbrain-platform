import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";

function LoadingScreen() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="animate-pulse text-muted-foreground">Caricamento...</div>
    </div>
  );
}

const INTERNAL_ADMIN_ROLES = new Set(["super_admin", "greenbrain_admin"]);
const PLATFORM_ACCESS_ROLES = new Set([
  "super_admin",
  "greenbrain_admin",
  "customer_admin",
  "customer_user",
  "tenant_admin",
]);

function roleOf(user: { user_role?: string | null } | null | undefined): string {
  return (user?.user_role ?? "").trim();
}

function isInternalAdmin(user: any): boolean {
  const role = roleOf(user);
  return INTERNAL_ADMIN_ROLES.has(role) || Boolean(user?.is_admin && !user?.tenant_code);
}

function hasPlatformAccess(user: any): boolean {
  if (isInternalAdmin(user)) return true;
  return Boolean(user?.platform_enabled);
}

export function ProtectedRoute() {
  const { user, loading } = useAuth();

  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;

  return <Outlet />;
}

export function CustomerRoute() {
  const { user, loading } = useAuth();

  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  if (!hasPlatformAccess(user)) return <Navigate to="/account" replace />;

  return <Outlet />;
}

export function InternalAdminRoute() {
  const { user, loading } = useAuth();

  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  if (!isInternalAdmin(user)) return <Navigate to="/account" replace />;

  return <Outlet />;
}

export const AdminRoute = InternalAdminRoute;
