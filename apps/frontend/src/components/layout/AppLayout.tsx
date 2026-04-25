import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { TopBar } from "./TopBar";
import { cn } from "@/lib/utils";

export function AppLayout() {
  const [collapsed, setCollapsed] = useState(false);
  const location = useLocation();

  const hideSidebar =
    location.pathname === "/customers" ||
    /^\/customers\/[^/]+$/.test(location.pathname);

  return (
    <div className="min-h-screen bg-background">
      {!hideSidebar && (
        <Sidebar collapsed={collapsed} onToggle={() => setCollapsed((v) => !v)} />
      )}

      <div className={cn(
        "transition-all duration-300 ease-in-out",
        hideSidebar ? "ml-0" : collapsed ? "ml-16" : "ml-64",
      )}>
        <TopBar />
        <main className="p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
