import { retainPlacesInClaimedSuburb } from "./canonicalise_claimed_suburb.ts";

function assertEquals<T>(actual: T, expected: T) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test(
  "an accepted Google locality alias is persisted under the canonical area label",
  async () => {
    const providerRows = [
      { placeId: "place-1", name: "Alias venue", suburb: "Crowsnest" },
      { placeId: "place-2", name: "Neighbouring venue", suburb: "Cammeray" },
    ];

    const retained = await retainPlacesInClaimedSuburb(
      providerRows,
      "suburb-crows-nest",
      async (suburb) => {
        if (suburb === "Crowsnest") {
          return {
            suburb_id: "suburb-crows-nest",
            canonical_name: "Crows Nest",
            is_active: true,
          };
        }
        return {
          suburb_id: "suburb-cammeray",
          canonical_name: "Cammeray",
          is_active: true,
        };
      },
    );

    assertEquals(retained, [
      { placeId: "place-1", name: "Alias venue", suburb: "Crows Nest" },
    ]);
    assertEquals(
      retained.filter((row) => row.suburb === "Crows Nest").length,
      1,
    );
  },
);
