import { Link, useLocation } from "react-router-dom";
import {
  LayoutDashboard,
  ShoppingCart,
  BarChart3,
  Truck,
  User,
  Leaf,
  CalendarRange,
  ChevronLeft,
  ChevronRight,
  Terminal,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";

const navItems = [
  { path: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { path: "/dashboard/reorders", label: "Riordino", icon: ShoppingCart },
  { path: "/analytics", label: "Analytics", icon: BarChart3 },
  { path: "/assortment-planner", label: "Assortment Planner", icon: CalendarRange },
  { path: "/suppliers", label: "Fornitori", icon: Truck },
  { path: "/account", label: "Account", icon: User },
];

type SidebarProps = {
  collapsed: boolean;
  onToggle: () => void;
};

export function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const location = useLocation();
  const { user } = useAuth();

  return (
    <aside
      className={cn(
        "fixed left-0 top-0 h-screen bg-sidebar text-sidebar-foreground flex flex-col border-r border-sidebar-border",
        "transition-all duration-300 ease-in-out",
        collapsed ? "w-16" : "w-64",
      )}
    >
      {/* Logo */}
      <div className="p-4 border-b border-sidebar-border">
        <div className="flex items-center justify-between">
          <Link to="/dashboard" className="flex items-center gap-3">
            <div className="w-10 h-10 bg-sidebar-primary rounded-lg flex items-center justify-center">
              <Leaf className="w-6 h-6 text-sidebar-primary-foreground" />
            </div>
            {!collapsed && <span className="text-xl font-bold text-sidebar-foreground">GreenBrain</span>}
          </Link>

          {/* Toggle button */}
          <button
            onClick={onToggle}
            className={cn(
              "ml-auto inline-flex items-center justify-center rounded-md",
              "h-9 w-9 hover:bg-sidebar-accent/50 transition-colors",
            )}
            aria-label={collapsed ? "Espandi sidebar" : "Comprimi sidebar"}
            title={collapsed ? "Espandi" : "Comprimi"}
          >
            {collapsed ? <ChevronRight className="w-5 h-5" /> : <ChevronLeft className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-2">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const isActive =
              location.pathname === item.path ||
              (item.path !== "/dashboard" && location.pathname.startsWith(item.path));

            return (
              <li key={item.path}>
                <Link
                  to={item.path}
                  className={cn(
                    "flex items-center gap-3 rounded-lg transition-colors",
                    collapsed ? "px-3 py-3 justify-center" : "px-4 py-3",
                    isActive
                      ? "bg-sidebar-accent text-sidebar-accent-foreground"
                      : "text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                  )}
                  title={collapsed ? item.label : undefined}
                >
                  <item.icon className="w-5 h-5 shrink-0" />
                  {!collapsed && <span className="font-medium">{item.label}</span>}
                </Link>
              </li>
            );
          })}

          {user?.is_admin && (
            <li key="/ops">
              <Link
                to="/ops"
                className={cn(
                  "flex items-center gap-3 rounded-lg transition-colors",
                  collapsed ? "px-3 py-3 justify-center" : "px-4 py-3",
                  location.pathname.startsWith("/ops") || location.pathname === "/customers"
                    ? "bg-sidebar-accent text-sidebar-accent-foreground"
                    : "text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                )}
                title={collapsed ? "Console Ops" : undefined}
              >
                <Terminal className="w-5 h-5 shrink-0" />
                {!collapsed && <span className="font-medium">Console Ops</span>}
              </Link>
            </li>
          )}
        </ul>
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-sidebar-border">
        {!collapsed ? (
          <p className="text-xs text-sidebar-foreground/50">© 2024 GreenBrain v1.0</p>
        ) : (
          <p className="text-xs text-sidebar-foreground/50 text-center">v1.0</p>
        )}
      </div>
    </aside>
  );
}
