import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Leaf, Mail, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { useAuth, type AuthUser } from "@/hooks/useAuth";
import { ApiError, apiPost } from "@/lib/apiClient";

function redirectAfterLogin(user: AuthUser, navigate: ReturnType<typeof useNavigate>) {
  const currentHost = window.location.host;
  const targetHost = user.home_host?.trim();
  const defaultPath = user.is_admin ? "/ops" : user.platform_enabled ? "/dashboard" : "/account";
  const targetPath = user.home_path?.trim() || defaultPath;

  if (targetHost && targetHost !== currentHost) {
    window.location.href = `https://${targetHost}${targetPath}`;
    return;
  }

  navigate(targetPath, { replace: true });
}

export default function Login() {
  const [searchParams] = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const navigate = useNavigate();
  const { toast } = useToast();
  const { user, loading, login, loginWithToken } = useAuth();

  const currentHost = window.location.host;
  const isCentralHost = currentHost === "www.greenbrain.it" || currentHost === "greenbrain.it";
  const isSsoBridge = Boolean(searchParams.get("sso")) && !isCentralHost;

  useEffect(() => {
    if (!loading && user) {
      redirectAfterLogin(user, navigate);
    }
  }, [user, loading, navigate]);

  useEffect(() => {
    const sso = searchParams.get("sso");

    if (!sso || isCentralHost) return;

    let cancelled = false;

    async function run() {
      try {
        setIsLoading(true);
        const data = await apiPost("/api/v1/auth/sso/exchange", { ticket: sso });
        const me = await loginWithToken(data.access_token);
        try {
          localStorage.setItem("gb_sso_last_ok", new Date().toISOString());
        } catch {}
        redirectAfterLogin(me, navigate);
      } catch (err) {
        if (!cancelled) {
          setErrorMessage(err instanceof Error ? err.message : "Errore SSO");
        }
      }
    }

    run();
    return () => {
      cancelled = true;
    };
  }, [searchParams, isCentralHost, loginWithToken, navigate]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setErrorMessage(null);

    try {
      if (isCentralHost) {
        try {
          const res = await apiPost("/api/v1/auth/sso/start", { email, password });
          const targetHost = res?.target_host?.trim();
          if (res?.redirect_url && targetHost && targetHost !== window.location.host) {
            window.location.href = res.redirect_url;
            return;
          }
          // Same-host users do not need SSO. Continue with standard login below.
          if (targetHost && targetHost === window.location.host) {
            // no-op
          }
        } catch {
          // Non cliente/SSO non applicabile: continua con login standard dev/admin.
        }
      } else {
        window.location.href = "https://www.greenbrain.it/login";
        return;
      }

      const me = await login(email, password);

      toast({
        title: "Benvenuto!",
        description: "Accesso effettuato con successo.",
      });

      redirectAfterLogin(me, navigate);
    } catch (err) {
      const msg =
        err instanceof ApiError && err.status === 401
          ? "Credenziali non valide. Riprova."
          : err instanceof Error
            ? err.message
            : "Errore di accesso.";

      setErrorMessage(msg);

      toast({
        title: "Errore di accesso",
        description: msg,
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  if (loading || isSsoBridge) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <Card className="w-full max-w-md p-8 text-center animate-fade-in">
          <div className="mx-auto mb-6 w-12 h-12 bg-primary rounded-xl flex items-center justify-center">
            <Leaf className="w-7 h-7 text-primary-foreground" />
          </div>
          <h1 className="text-xl font-semibold mb-2">Accesso in corso...</h1>
          <p className="text-sm text-muted-foreground">
            Ti stiamo portando alla tua piattaforma GreenBrain.
          </p>
          {errorMessage && (
            <p className="text-sm text-destructive mt-4">{errorMessage}</p>
          )}
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex flex-col items-center justify-center gap-4 p-4">
      <div className="w-full max-w-md">
        <Link to="/" className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1">
          ← Torna alla home
        </Link>
      </div>
      <Card className="w-full max-w-md p-8 animate-fade-in">
        <Link to="/" className="flex items-center justify-center gap-3 mb-8 hover:opacity-80 transition-opacity">
          <div className="w-12 h-12 bg-primary rounded-xl flex items-center justify-center">
            <Leaf className="w-7 h-7 text-primary-foreground" />
          </div>
          <span className="text-2xl font-bold">GreenBrain</span>
        </Link>

        <h1 className="text-xl font-semibold text-center mb-2">Bentornato!</h1>
        <p className="text-sm text-muted-foreground text-center mb-8">Accedi al tuo Garden Center</p>

        <form onSubmit={handleLogin} className="space-y-4" autoComplete="off">
          <div className="space-y-2">
            <label className="text-sm font-medium">Email</label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                type="email"
                name="gb_email"
                autoComplete="off"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="nome@gardencenter.it"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">Password</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                type="password"
                name="gb_password"
                autoComplete="new-password"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          {errorMessage && <p className="text-sm text-destructive text-center">{errorMessage}</p>}

          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? "Accesso in corso..." : "Accedi"}
          </Button>
        </form>

        <p className="text-xs text-muted-foreground text-center mt-6">
          Hai dimenticato la password? Contatta l&apos;amministratore.
        </p>
      </Card>
    </div>
  );
}
