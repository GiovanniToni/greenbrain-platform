import { apiGet } from "@/lib/apiClient";

export async function getCustomerPortalMe() {
  return apiGet("/api/v1/customer-portal/me");
}

export function getCustomerPortalBundleDownloadUrl() {
  return "/api/v1/customer-portal/download-bundle";
}
