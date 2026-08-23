import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type GazetteerConfig = {
  gazetteer_source_url: string;
};

type GazetteerClaim = {
  sync_id: string | null;
  outcome: "granted" | "recently_synced" | "sync_in_progress";
};

type GazetteerFeature = {
  attributes?: Record<string, unknown>;
};

type GazetteerPage = {
  features?: GazetteerFeature[];
  exceededTransferLimit?: boolean;
};

type GazetteerRecord = Record<string, string | null>;

function value(
  attributes: Record<string, unknown>,
  name: string,
): string | null {
  const direct = attributes[name];
  const found = direct ??
    attributes[
      Object.keys(attributes).find((key) => key.toLowerCase() === name)!
    ];
  if (found === null || found === undefined || found === "") return null;
  return String(found);
}

function normaliseFeature(feature: GazetteerFeature): GazetteerRecord | null {
  const attributes = feature.attributes;
  if (!attributes) return null;
  const cadid = value(attributes, "cadid");
  const suburbname = value(attributes, "suburbname");
  if (!cadid || !suburbname) return null;
  return {
    cadid,
    suburbname,
    postcode: value(attributes, "postcode"),
    createdate: value(attributes, "createdate"),
    modifieddate: value(attributes, "modifieddate"),
    startdate: value(attributes, "startdate"),
    enddate: value(attributes, "enddate"),
    lastupdate: value(attributes, "lastupdate"),
    shapeuuid: value(attributes, "shapeuuid"),
  };
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function fetchSnapshot(sourceUrl: string): Promise<GazetteerRecord[]> {
  const records: GazetteerRecord[] = [];
  const pageSize = 2000;

  for (let offset = 0;; offset += pageSize) {
    const url = new URL(sourceUrl);
    url.searchParams.set("where", "1=1");
    url.searchParams.set(
      "outFields",
      "cadid,suburbname,postcode,createdate,modifieddate,startdate,enddate,lastupdate,shapeuuid",
    );
    url.searchParams.set("returnGeometry", "false");
    url.searchParams.set("orderByFields", "cadid");
    url.searchParams.set("resultOffset", String(offset));
    url.searchParams.set("resultRecordCount", String(pageSize));
    url.searchParams.set("f", "json");

    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Official NSW gazetteer returned ${response.status}`);
    }
    const page = await response.json() as GazetteerPage;
    const features = page.features ?? [];
    records.push(...features.flatMap((feature) => {
      const record = normaliseFeature(feature);
      return record ? [record] : [];
    }));
    if (!page.exceededTransferLimit || features.length === 0) break;
  }

  if (records.length === 0) {
    throw new Error(
      "Official NSW gazetteer returned no usable locality records",
    );
  }
  return records.sort((left, right) => left.cadid!.localeCompare(right.cadid!));
}

export type GazetteerSyncResult = {
  outcome: GazetteerClaim["outcome"] | "succeeded";
  records?: number;
  inserted?: number;
  updated?: number;
  retired?: number;
};

export async function syncNswGazetteer(
  supabaseAdmin: SupabaseClient,
): Promise<GazetteerSyncResult> {
  const { data: config, error: configError } = await supabaseAdmin
    .from("coverage_automation_config")
    .select("gazetteer_source_url")
    .eq("id", true)
    .single();
  if (configError || !config) {
    throw new Error(
      `Could not load gazetteer config: ${
        configError?.message ?? "No config returned"
      }`,
    );
  }

  const { data: claimData, error: claimError } = await supabaseAdmin
    .rpc("claim_nsw_suburb_gazetteer_sync")
    .single();
  if (claimError || !claimData) {
    throw new Error(
      `Could not claim gazetteer sync: ${
        claimError?.message ?? "No claim returned"
      }`,
    );
  }
  const claim = claimData as GazetteerClaim;
  if (claim.outcome !== "granted" || !claim.sync_id) {
    return { outcome: claim.outcome };
  }

  try {
    const sourceUrl = (config as GazetteerConfig).gazetteer_source_url;
    const records = await fetchSnapshot(sourceUrl);
    const checksum = await sha256(JSON.stringify(records));
    const { data, error } = await supabaseAdmin
      .rpc("apply_nsw_suburb_gazetteer_snapshot", {
        p_sync_id: claim.sync_id,
        p_records: records,
        p_checksum: checksum,
      })
      .single();
    if (error || !data) {
      throw new Error(
        `Could not apply gazetteer snapshot: ${
          error?.message ?? "No result returned"
        }`,
      );
    }
    const result = data as {
      inserted_count: number;
      updated_count: number;
      retired_count: number;
    };
    return {
      outcome: "succeeded",
      records: records.length,
      inserted: result.inserted_count,
      updated: result.updated_count,
      retired: result.retired_count,
    };
  } catch (error) {
    // The SQL apply function marks an apply failure itself. A source/network
    // error occurs before it runs, so close the claimed slot explicitly.
    const message = error instanceof Error
      ? error.message
      : "unknown gazetteer sync failure";
    await supabaseAdmin
      .from("nsw_suburb_gazetteer_syncs")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
        error_message: message.slice(0, 500),
      })
      .eq("id", claim.sync_id)
      .eq("status", "running");
    throw error;
  }
}
