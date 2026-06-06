import { useEffect, useState } from "react";
import { Bell, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { getCustomerOpsNotifications, type CustomerSecurityAlert } from "@/lib/customerOpsApi";

import { AnalyticsEntitySearch } from "@/components/analytics/AnalyticsEntitySearch";
import type { CatalogItem } from "@/hooks/useAnalyticsCatalog";

function isInternalAdminUser(user: any): boolean {
  const role = (user?.user_role || "").trim();
  return role === "super_admin" || role === "greenbrain_admin" || Boolean(user?.is_admin && !user?.tenant_code);
}

function fmtNotificationDate(value?: string | null): string {
  if (!value) return "";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString("it-IT", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function TopBar() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();

  const isAnalytics = location.pathname.startsWith("/analytics");
  const isInternalAdmin = isInternalAdminUser(user);

  // ✅ pagine dove vuoi la search "smart"
  const showSmartSearch =
    location.pathname === "/dashboard" ||
    location.pathname.startsWith("/dashboard/reorders") ||
    location.pathname.startsWith("/assortment-planner");

  const [now, setNow] = useState<Date>(() => new Date());

  // serve per la prop `selectedItem` (anche se non la usi davvero)
  const [lastSelected, setLastSelected] = useState<CatalogItem | null>(null);

  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [notifications, setNotifications] = useState<CustomerSecurityAlert[]>([]);
  const [notificationsLoading, setNotificationsLoading] = useState(false);
  const [notificationsError, setNotificationsError] = useState<string | null>(null);

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let cancelled = false;

    if (!isInternalAdmin) {
      setNotifications([]);
      setNotificationsError(null);
      setNotificationsLoading(false);
      return;
    }

    const loadNotifications = async () => {
      try {
        setNotificationsLoading(true);
        const data = await getCustomerOpsNotifications(20);
        if (!cancelled) {
          setNotifications(data.items || []);
          setNotificationsError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setNotifications([]);
          setNotificationsError(err instanceof Error ? err.message : "Errore notifiche");
        }
      } finally {
        if (!cancelled) {
          setNotificationsLoading(false);
        }
      }
    };

    loadNotifications();
    const id = setInterval(loadNotifications, 60000);

    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [isInternalAdmin]);

  useEffect(() => {
    setNotificationsOpen(false);
  }, [location.pathname]);

  const handleLogout = () => {
    const host = window.location.host;
    const isCentralHost = host === "www.greenbrain.it" || host === "greenbrain.it";

    logout();

    if (!isCentralHost) {
      window.location.href = "https://www.greenbrain.it/login";
      return;
    }

    navigate("/login", { replace: true });
  };

  const handleTopSearchSelect = (item: CatalogItem) => {
    setLastSelected(item);
    navigate("/analytics", { state: { preselect: item } });
  };

  const handleNotificationClick = (notification: CustomerSecurityAlert) => {
    setNotificationsOpen(false);
    if (notification.customer_id) {
      navigate(`/customers/${notification.customer_id}`);
      return;
    }
    navigate("/customers");
  };

  const notificationCount = isInternalAdmin ? notifications.length : 0;

  return (
    <header className="h-16 bg-card border-b border-border flex items-center justify-between px-6">
      {/* Left: Search */}
      <div className="relative w-[520px] max-w-full">
        {/* ✅ in Analytics la search è già nella pagina */}
        {!isAnalytics && showSmartSearch && (
          <AnalyticsEntitySearch onSelect={handleTopSearchSelect} selectedItem={lastSelected} />
        )}

        {/* opzionale: placeholder sulle altre pagine */}
        {!isAnalytics && !showSmartSearch && <div className="h-9" />}
      </div>

      {/* Right */}
      <div className="flex items-center gap-4">
        <div className="text-right text-xs text-muted-foreground leading-tight">
          <div className="font-medium text-foreground">
            {now.toLocaleDateString("it-IT", {
              weekday: "long",
              day: "2-digit",
              month: "long",
              year: "numeric",
            })}
          </div>
          <div className="tabular-nums">{now.toLocaleTimeString("it-IT", { hour12: false })}</div>
        </div>

        <div className="relative">
          <Button
            variant="ghost"
            size="icon"
            className="relative"
            onClick={() => setNotificationsOpen((v) => !v)}
            title={isInternalAdmin ? "Notifiche admin" : "Notifiche"}
          >
            <Bell className="w-5 h-5" />
            {notificationCount > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-destructive text-[10px] font-bold text-destructive-foreground flex items-center justify-center">
                {notificationCount > 9 ? "9+" : notificationCount}
              </span>
            )}
          </Button>

          {notificationsOpen && (
            <div className="absolute right-0 mt-2 w-96 max-w-[calc(100vw-2rem)] rounded-lg border border-border bg-card shadow-lg z-50 overflow-hidden">
              <div className="px-4 py-3 border-b border-border">
                <div className="text-sm font-semibold text-foreground">
                  {isInternalAdmin ? "Notifiche admin" : "Notifiche"}
                </div>
                <div className="text-xs text-muted-foreground">
                  {isInternalAdmin
                    ? `${notificationCount} avvisi attivi`
                    : "Notifiche cliente/local non ancora collegate"}
                </div>
              </div>

              {!isInternalAdmin ? (
                <div className="px-4 py-4 text-sm text-muted-foreground">
                  Le notifiche cliente/local saranno collegate in una fase separata.
                </div>
              ) : notificationsLoading ? (
                <div className="px-4 py-4 text-sm text-muted-foreground">Caricamento notifiche...</div>
              ) : notificationsError ? (
                <div className="px-4 py-4 text-sm text-destructive">{notificationsError}</div>
              ) : notifications.length === 0 ? (
                <div className="px-4 py-4 text-sm text-muted-foreground">Nessuna notifica admin attiva.</div>
              ) : (
                <div className="max-h-96 overflow-y-auto">
                  {notifications.map((notification) => (
                    <button
                      key={notification.id}
                      onClick={() => handleNotificationClick(notification)}
                      className="w-full text-left px-4 py-3 border-b border-border last:border-b-0 hover:bg-muted/60 transition-colors"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <div className="text-sm font-semibold text-foreground truncate">
                            {notification.title || "Avviso operativo"}
                          </div>
                          <div className="text-xs text-muted-foreground mt-1">
                            {notification.message}
                          </div>
                          <div className="text-[11px] text-muted-foreground mt-2">
                            {notification.tenant_code || "—"} · {notification.email}
                            {notification.last_seen_at ? ` · ${fmtNotificationDate(notification.last_seen_at)}` : ""}
                          </div>
                        </div>
                        <span
                          className={
                            notification.severity === "error"
                              ? "text-[10px] font-bold uppercase text-destructive"
                              : notification.severity === "warning"
                                ? "text-[10px] font-bold uppercase text-amber-700"
                                : "text-[10px] font-bold uppercase text-muted-foreground"
                          }
                        >
                          {notification.severity}
                        </span>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <div className="flex items-center gap-3 pl-4 border-l border-border">
          <div className="text-right">
            <p className="text-sm font-medium">{user?.full_name || "Garden Center"}</p>
            <p className="text-xs text-muted-foreground">{user?.email || "utente"}</p>
          </div>
          <Button variant="ghost" size="icon" onClick={handleLogout}>
            <LogOut className="w-4 h-4" />
          </Button>
        </div>
      </div>
    </header>
  );
}
