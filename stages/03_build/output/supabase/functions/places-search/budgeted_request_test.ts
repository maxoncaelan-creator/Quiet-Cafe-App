import { runBudgetedProviderRequest } from "./budgeted_request.ts";

function assertEquals<T>(actual: T, expected: T) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("a denied monthly budget cannot invoke the provider transport", async () => {
  let providerCalls = 0;
  let settles = 0;

  const result = await runBudgetedProviderRequest(
    async () => {},
    async () => ({
      reservation_id: null,
      outcome: "monthly_ceiling_reached",
      remaining: 0,
    }),
    async () => {
      throw new Error("must not mark a denied reservation");
    },
    async () => {
      settles += 1;
    },
    async () => {
      providerCalls += 1;
      return new Response("should never run");
    },
  );

  assertEquals(result, { kind: "denied", remaining: 0 });
  assertEquals(providerCalls, 0);
  assertEquals(settles, 0);
});

Deno.test("a provider attempt settles one budget request even when it fails", async () => {
  let settled: number | null = null;
  await Promise.allSettled([
    runBudgetedProviderRequest(
      async () => {},
      async () => ({
        reservation_id: "reservation-1",
        outcome: "granted",
        remaining: 7,
      }),
      async () => true,
      async (_id, actual) => {
        settled = actual;
      },
      async () => {
        throw new Error("network reset");
      },
    ),
  ]);
  assertEquals(settled, 1);
});

Deno.test("a reservation that cannot be marked dispatched never invokes the provider", async () => {
  let providerCalls = 0;
  let settles = 0;

  await Promise.allSettled([
    runBudgetedProviderRequest(
      async () => {},
      async () => ({
        reservation_id: "reservation-2",
        outcome: "granted",
        remaining: 7,
      }),
      async () => false,
      async () => {
        settles += 1;
      },
      async () => {
        providerCalls += 1;
        return new Response("unexpected");
      },
    ),
  ]);

  assertEquals(providerCalls, 0);
  assertEquals(settles, 0);
});

Deno.test("a missing dispatch marker cannot reserve budget or invoke the provider", async () => {
  let claims = 0;
  let providerCalls = 0;

  await Promise.allSettled([
    runBudgetedProviderRequest(
      async () => {
        throw new Error("marker RPC is not deployed yet");
      },
      async () => {
        claims += 1;
        return {
          reservation_id: "reservation-3",
          outcome: "granted",
          remaining: 7,
        };
      },
      async () => true,
      async () => {},
      async () => {
        providerCalls += 1;
        return new Response("unexpected");
      },
    ),
  ]);

  assertEquals(claims, 0);
  assertEquals(providerCalls, 0);
});
