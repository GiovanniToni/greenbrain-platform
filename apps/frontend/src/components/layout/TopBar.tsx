import { useEffect, useState } from "react";
import { Bell, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";

import { AnalyticsEntitySearch } from "@/components/analytics/AnalyticsEntitySearch";
import type { CatalogItem } from "@/hooks/useAnalyticsCatalog";

export function TopBar() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();

  const isAnalytics = location.pathname.startsWith("/analytics");

  // ✅ pagine dove vuoi la search "smart"
  const showSmartSearch =
    location.pathname === "/dashboard" ||
    location.pathname.startsWith("/dashboard/reorders") ||
    location.pathname.startsWith("/assortment-planner");

  const [now, setNow] = useState<Date>(() => new Date());

  // serve per la prop `selectedItem` (anche se non la usi davvero)
  const [lastSelected, setLastSelected] = useState<CatalogItem | null>(null);

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

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

        <Button variant="ghost" size="icon" className="relative">
          <Bell className="w-5 h-5" />
          <span className="absolute top-1 right-1 w-2 h-2 bg-destructive rounded-full" />
        </Button>

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
