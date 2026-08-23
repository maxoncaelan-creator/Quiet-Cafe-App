export type PlacesBudgetClaim = {
  reservation_id: string | null;
  outcome: string;
  remaining: number | null;
};

export type BudgetedProviderResult<T> =
  | { kind: "denied"; remaining: number | null }
  | { kind: "completed"; value: T };

/// Runs one real provider attempt behind a one-request reservation.
///
/// The function is deliberately dependency-injected so its no-provider-on-deny
/// invariant has a deterministic Deno test. A thrown provider request still
/// settles at one: after invoking fetch we cannot safely assume Google did not
/// receive the request. The dispatch-marker preflight runs before the
/// reservation so a deployment that reaches this code before its migration
/// fails closed without consuming capacity.
export async function runBudgetedProviderRequest<T>(
  verifyDispatchBoundary: () => Promise<void>,
  claim: () => Promise<PlacesBudgetClaim>,
  markDispatched: (reservationId: string) => Promise<boolean>,
  settle: (reservationId: string, actualCount: number) => Promise<void>,
  providerRequest: () => Promise<T>,
): Promise<BudgetedProviderResult<T>> {
  await verifyDispatchBoundary();
  const budget = await claim();
  if (budget.outcome !== "granted" || !budget.reservation_id) {
    return { kind: "denied", remaining: budget.remaining };
  }

  const markedDispatched = await markDispatched(budget.reservation_id);
  if (!markedDispatched) {
    // Do not release here: a false result can mean another invocation already
    // marked the same reservation. Leaving it charged is the safe outcome.
    throw new Error("Could not mark Places request as dispatched");
  }

  try {
    return { kind: "completed", value: await providerRequest() };
  } finally {
    // The dispatch marker comes before providerRequest(). A thrown fetch may
    // still have reached Google, so it remains a one-request settlement.
    await settle(budget.reservation_id, 1);
  }
}
