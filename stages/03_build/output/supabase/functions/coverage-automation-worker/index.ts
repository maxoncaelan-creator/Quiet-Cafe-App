// Private Step 1 worker for NSW locality coverage. pg_cron/pg_net invoke this
// with a Vault-backed secret; it never accepts a browser request. All Google
// requests still flow through places-search, which owns the global monthly
// budget reservation.

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  retainPlacesInClaimedSuburb,
  type ResolvedNswSuburb,
} from "../canonicalise_claimed_suburb.ts";
import { syncNswGazetteer } from "../sync-nsw-gazetteer/service.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PIPELINE_SHARED_SECRET = Deno.env.get("PIPELINE_SHARED_SECRET");
const AUTOMATION_SECRET = Deno.env.get("COVERAGE_AUTOMATION_SECRET");
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const BASE_MAX_PAGES = 2;
const FOLLOWUP_CATEGORIES = ["cafes", "pubs", "bars"];
const POSITIVE_PHRASES = [
  "quiet",
  "peaceful",
  "great for conversation",
  "easy to talk",
  "could hear each other",
  "calm atmosphere",
  "not loud",
  "low key",
];
const NEGATIVE_PHRASES = [
  "loud",
  "noisy",
  "couldn't hear",
  "could not hear",
  "hard to hear",
  "had to shout",
  "ear-splitting",
  "deafening",
  "too much noise",
];
const CONFIDENCE_LEVELS = [
  "Very Low",
  "Low",
  "Moderate",
  "High",
  "Very High",
  "Certain",
];

type SweepClaim = {
  suburb_id: string;
  canonical_name: string;
  attempt_count: number;
  lease_token: string;
};

type RawPlace = {
  id: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  addressComponents?: { longText?: string; types?: string[] }[];
  location?: { latitude?: number; longitude?: number };
  priceLevel?: string;
  primaryType?: string;
  rating?: number;
  reviews?: { text?: { text?: string } }[];
};

type NormalisedPlace = {
  placeId: string;
  name: string;
  address: string | null;
  suburb: string | null;
  lat: number | null;
  lng: number | null;
  priceLevel: number | null;
  cuisine: string | null;
  googleRating: number | null;
  reviewTexts: string[];
};

class MonthlyPlacesBudgetReached extends Error {
  constructor() {
    super("monthly_places_budget_reached");
  }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function fetchWithRetry(
  url: string,
  options: RequestInit,
  retries = 2,
  delayMs = 3000,
): Promise<Response> {
  for (let attempt = 0;; attempt++) {
    const response = await fetch(url, options);
    if (response.ok || response.status < 500 || attempt >= retries) {
      return response;
    }
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
}

const SUBURB_COMPONENT_TYPES = [
  "locality",
  "sublocality",
  "sublocality_level_1",
];
const PRICE_LEVEL_MAP: Record<string, number> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

function extractSuburb(
  components: RawPlace["addressComponents"],
): string | null {
  for (const type of SUBURB_COMPONENT_TYPES) {
    const component = components?.find((candidate) =>
      candidate.types?.includes(type)
    );
    if (component?.longText?.trim()) return component.longText.trim();
  }
  return null;
}

function normalisePlace(place: RawPlace): NormalisedPlace {
  return {
    placeId: place.id,
    name: place.displayName?.text?.trim() || "",
    address: place.formattedAddress?.trim() || null,
    suburb: extractSuburb(place.addressComponents),
    lat: place.location?.latitude ?? null,
    lng: place.location?.longitude ?? null,
    priceLevel: place.priceLevel
      ? PRICE_LEVEL_MAP[place.priceLevel] ?? null
      : null,
    cuisine: place.primaryType ?? null,
    googleRating: place.rating ?? null,
    reviewTexts: (place.reviews ?? []).map((review) => review.text?.text)
      .filter((text): text is string => Boolean(text)),
  };
}

async function resolveReturnedNswSuburb(
  suburb: string,
): Promise<ResolvedNswSuburb | null> {
  const { data, error } = await supabaseAdmin
    .rpc("resolve_nsw_suburb", { p_query: suburb })
    .maybeSingle();
  if (error) {
    throw new Error(
      `Could not resolve a returned Google locality: ${error.message}`,
    );
  }
  return data as ResolvedNswSuburb | null;
}

async function searchPlaces(query: string, maxPages: number) {
  if (!PIPELINE_SHARED_SECRET) {
    throw new Error("PIPELINE_SHARED_SECRET is not configured");
  }
  const places: RawPlace[] = [];
  let pageToken: string | undefined;
  let pagesAttempted = 0;
  let pagesExhausted = false;

  for (let page = 0; page < maxPages; page++) {
    const response = await fetchWithRetry(
      `${SUPABASE_URL}/functions/v1/places-search`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
          apikey: SUPABASE_ANON_KEY,
          "x-pipeline-secret": PIPELINE_SHARED_SECRET,
        },
        body: JSON.stringify({ query, ...(pageToken ? { pageToken } : {}) }),
      },
    );
    if (!response.ok) {
      const detail = await response.text();
      if (
        response.status === 429 &&
        detail.includes("monthly_places_budget_reached")
      ) {
        throw new MonthlyPlacesBudgetReached();
      }
      throw new Error(`places-search failed: ${response.status} ${detail}`);
    }
    const data = await response.json();
    pagesAttempted += 1;
    places.push(...(data.places ?? []));
    if (!data.nextPageToken) {
      pagesExhausted = true;
      break;
    }
    pageToken = data.nextPageToken;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return {
    places: places.map(normalisePlace),
    pagesAttempted,
    pagesExhausted,
    possiblyTruncated: places.length >= maxPages * 20,
  };
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.max(minimum, Math.min(maximum, value));
}

function countPhraseOccurrences(text: string, phrases: string[]) {
  const lower = text.toLowerCase();
  return phrases.reduce((count, phrase) => {
    let index = 0;
    let found = 0;
    while ((index = lower.indexOf(phrase, index)) !== -1) {
      found += 1;
      index += phrase.length;
    }
    return count + found;
  }, 0);
}

function scoreFromReviews(reviewTexts: string[]) {
  const positiveCount = reviewTexts.reduce(
    (count, text) => count + countPhraseOccurrences(text, POSITIVE_PHRASES),
    0,
  );
  const negativeCount = reviewTexts.reduce(
    (count, text) => count + countPhraseOccurrences(text, NEGATIVE_PHRASES),
    0,
  );
  const total = positiveCount + negativeCount;
  if (total < 1) {
    return { positiveCount, negativeCount, subscore: null, confidence: null };
  }
  const subscore = clamp((positiveCount / total) * 100, 0, 100);
  const points = 1 + Number(total >= 3) + Number(total >= 6);
  return {
    positiveCount,
    negativeCount,
    subscore,
    confidence: CONFIDENCE_LEVELS[clamp(points, 1, 6) - 1],
  };
}

async function completeSweep(
  suburbId: string,
  leaseToken: string,
  outcome: "completed" | "failed" | "blocked_budget",
  pagesAttempted: number,
  pagesExhausted: boolean,
  placesFound: number,
  error?: string,
) {
  const { error: rpcError } = await supabaseAdmin.rpc(
    "complete_nsw_suburb_sweep",
    {
      p_suburb_id: suburbId,
      p_lease_token: leaseToken,
      p_outcome: outcome,
      p_pages_attempted: pagesAttempted,
      p_pages_exhausted: pagesExhausted,
      p_places_found: placesFound,
      p_error: error ?? null,
    },
  );
  if (rpcError) {
    throw new Error(`Could not complete suburb sweep: ${rpcError.message}`);
  }
}

async function processOneSweep() {
  // pgmq wake-ups are private database state; a periodic worker tick can still
  // recover an expired lease even if the previous process died after popping.
  await supabaseAdmin.rpc("consume_nsw_suburb_sweep_wakeup");
  const { data: claimData, error: claimError } = await supabaseAdmin
    .rpc("claim_next_nsw_suburb_sweep")
    .maybeSingle();
  if (claimError) {
    throw new Error(`Could not claim suburb sweep: ${claimError.message}`);
  }
  const claim = claimData as SweepClaim | null;
  if (!claim) return { outcome: "idle" };
  if (!claim.lease_token) {
    throw new Error("Claimed suburb sweep is missing its lease token");
  }

  let pagesAttempted = 0;
  let pagesExhausted = false;
  let placesFound = 0;
  try {
    const base = await searchPlaces(
      `restaurants, cafes, pubs and bars in ${claim.canonical_name} NSW`,
      BASE_MAX_PAGES,
    );
    pagesAttempted += base.pagesAttempted;
    pagesExhausted = base.pagesExhausted;
    const byPlaceId = new Map(
      base.places.map((place) => [place.placeId, place]),
    );
    const materialiseRows = async () => {
      const fetchedPlaces = [...byPlaceId.values()];
      const places = await retainPlacesInClaimedSuburb(
        fetchedPlaces,
        claim.suburb_id,
        resolveReturnedNswSuburb,
      );
      if (fetchedPlaces.length > 0 && places.length === 0) {
        throw new Error(
          "Places search returned no venues in the claimed NSW suburb",
        );
      }
      const now = new Date().toISOString();
      return places
        .filter((place) => place.placeId && place.name)
        .map((place) => {
          const review = scoreFromReviews(place.reviewTexts);
          return {
            place_id: place.placeId,
            name: place.name,
            cuisine: place.cuisine,
            price_level: place.priceLevel,
            google_rating: place.googleRating,
            address: place.address,
            suburb: place.suburb,
            lat: place.lat,
            lng: place.lng,
            review_positive_count: review.positiveCount,
            review_negative_count: review.negativeCount,
            review_subscore: review.subscore,
            review_signal_updated_at: now,
            mic_reading_count_ios: 0,
            mic_reading_count_android: 0,
            vote_count: 0,
            quietness_score: review.subscore,
            confidence: review.confidence,
            score_updated_at: now,
            discovered_via: "suburb sweep",
          };
        });
    };
    const persistRows = async (
      rows: Awaited<ReturnType<typeof materialiseRows>>,
    ) => {
      if (rows.length === 0) return;
      const { data: insertedRows, error: insertError } = await supabaseAdmin
        .from("restaurants")
        .upsert(rows, { onConflict: "place_id", ignoreDuplicates: true })
        .select("place_id");
      if (insertError) {
        throw new Error(`Restaurant upsert failed: ${insertError.message}`);
      }
      placesFound += insertedRows?.length ?? 0;
    };
    await persistRows(await materialiseRows());
    if (base.possiblyTruncated) {
      for (const category of FOLLOWUP_CATEGORIES) {
        const followup = await searchPlaces(
          `${category} in ${claim.canonical_name} NSW`,
          1,
        );
        pagesAttempted += followup.pagesAttempted;
        pagesExhausted = pagesExhausted && followup.pagesExhausted;
        for (const place of followup.places) {
          byPlaceId.set(place.placeId, place);
        }
        // Preserve earlier pages even if a later category hits the monthly
        // ceiling. Re-running this additive upsert safely inserts only newly
        // discovered place ids.
        await persistRows(await materialiseRows());
      }
    }
    await completeSweep(
      claim.suburb_id,
      claim.lease_token,
      "completed",
      pagesAttempted,
      pagesExhausted,
      placesFound,
    );
    return {
      outcome: "completed",
      suburb: claim.canonical_name,
      pagesAttempted,
      placesFound,
    };
  } catch (error) {
    if (error instanceof MonthlyPlacesBudgetReached) {
      await completeSweep(
        claim.suburb_id,
        claim.lease_token,
        "blocked_budget",
        pagesAttempted,
        pagesExhausted,
        placesFound,
        error.message,
      );
      return { outcome: "blocked_budget", suburb: claim.canonical_name };
    }
    const message = error instanceof Error
      ? error.message
      : "unknown sweep failure";
    await completeSweep(
      claim.suburb_id,
      claim.lease_token,
      "failed",
      pagesAttempted,
      pagesExhausted,
      placesFound,
      message,
    );
    throw error;
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!AUTOMATION_SECRET) {
    return jsonResponse({ error: "automation_secret_not_configured" }, 503);
  }
  if (
    request.headers.get("x-coverage-automation-secret") !== AUTOMATION_SECRET
  ) {
    return jsonResponse({ error: "unauthorised" }, 401);
  }

  let body: { action?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }
  if (body.action === "sync_gazetteer") {
    try {
      return jsonResponse(await syncNswGazetteer(supabaseAdmin));
    } catch (error) {
      console.error("NSW gazetteer sync failed:", error);
      return jsonResponse({ error: "gazetteer_sync_failed" }, 502);
    }
  }
  if (body.action !== "sweep") {
    return jsonResponse({ error: "unknown_action" }, 400);
  }

  try {
    return jsonResponse(await processOneSweep());
  } catch (error) {
    console.error("NSW suburb sweep failed:", error);
    return jsonResponse({ error: "sweep_failed" }, 502);
  }
});
