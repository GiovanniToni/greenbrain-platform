import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  apiGet,
  apiPost,
  clearStoredToken,
  getStoredToken,
  setStoredToken,
} from "@/lib/apiClient";

export interface AuthUser {
  id: string;
  email: string;
  full_name: string | null;
  is_admin: boolean;
  tenant_code?: string | null;
  home_host?: string | null;
  home_path?: string | null;
  user_role?: string | null;
  platform_enabled?: boolean;
  runtime_health?: string | null;
  runtime_public_backend_url?: string | null;
  runtime_installation_id?: string | null;
}

type AuthContextValue = {
  user: AuthUser | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<AuthUser>;
  loginWithToken: (token: string) => Promise<AuthUser>;
  logout: () => void;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = getStoredToken();

    if (!token) {
      setUser(null);
      setLoading(false);
      return;
    }

    apiGet("/api/v1/auth/me")
      .then((data: AuthUser) => {
        setUser(data);
      })
      .catch(() => {
        clearStoredToken();
        setUser(null);
      })
      .finally(() => {
        setLoading(false);
      });
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const data = await apiPost("/api/v1/auth/login", { email, password });
    setStoredToken(data.access_token);

    const me: AuthUser = await apiGet("/api/v1/auth/me");
    setUser(me);
    return me;
  }, []);

  const loginWithToken = useCallback(async (token: string) => {
    setStoredToken(token);
    const me: AuthUser = await apiGet("/api/v1/auth/me");
    setUser(me);
    return me;
  }, []);

  const logout = useCallback(() => {
    clearStoredToken();
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({
      user,
      loading,
      login,
      loginWithToken,
      logout,
    }),
    [user, loading, login, loginWithToken, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within <AuthProvider>");
  }
  return ctx;
}
