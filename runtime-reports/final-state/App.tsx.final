import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import { AuthProvider } from "@/hooks/useAuth";
import { AppLayout } from "@/components/layout/AppLayout";
import { ProtectedRoute } from "@/components/auth/ProtectedRoute";

import Login from "@/pages/Login";
import Landing from "@/pages/Landing";
import Dashboard from "@/pages/Dashboard";
import Reorders from "@/pages/Reorders";
import Analytics from "@/pages/Analytics";
import Suppliers from "@/pages/Suppliers";
import Account from "@/pages/Account";
import AssortmentPlanner from "@/pages/AssortmentPlanner";
import NotFound from "@/pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/login" element={<Login />} />

            <Route element={<ProtectedRoute />}>
              <Route element={<AppLayout />}>
                <Route path="/dashboard" element={<Dashboard />} />
                <Route path="/dashboard/reorders" element={<Reorders />} />
                <Route path="/analytics" element={<Analytics />} />
                <Route path="/assortment-planner" element={<AssortmentPlanner />} />
                <Route path="/suppliers" element={<Suppliers />} />
                <Route path="/account" element={<Account />} />
              </Route>
            </Route>

            <Route path="*" element={<NotFound />} />
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
