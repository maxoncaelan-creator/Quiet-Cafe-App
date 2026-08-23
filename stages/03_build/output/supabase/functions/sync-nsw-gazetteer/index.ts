import { createClient } from "npm:@supabase/supabase-js@2";

import { syncNswGazetteer } from "./service.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const AUTOMATION_SECRET = Deno.env.get("COVERAGE_AUTOMATION_SECRET");
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response({ error: "method_not_allowed" }, 405);
  }
  if (!AUTOMATION_SECRET) {
    return response({ error: "automation_secret_not_configured" }, 503);
  }
  if (
    request.headers.get("x-coverage-automation-secret") !== AUTOMATION_SECRET
  ) {
    return response({ error: "unauthorised" }, 401);
  }

  try {
    return response(await syncNswGazetteer(supabaseAdmin));
  } catch (error) {
    console.error("NSW gazetteer sync failed:", error);
    return response({ error: "gazetteer_sync_failed" }, 502);
  }
});
