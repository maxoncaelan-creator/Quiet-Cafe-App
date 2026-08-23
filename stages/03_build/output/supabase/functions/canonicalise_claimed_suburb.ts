// Google may return a current or historic locality alias. Area sweeps use the
// official canonical label for every subsequent read, so normalise accepted
// provider rows before they reach the restaurants table.

export type ResolvedNswSuburb = {
  suburb_id: string;
  canonical_name: string;
  is_active: boolean;
};

type PlaceWithSuburb = {
  suburb: string | null;
};

export async function retainPlacesInClaimedSuburb<T extends PlaceWithSuburb>(
  places: T[],
  suburbId: string,
  resolveNswSuburb: (suburb: string) => Promise<ResolvedNswSuburb | null>,
): Promise<T[]> {
  const suburbNames = [
    ...new Set(
      places.map((place) => place.suburb).filter((suburb): suburb is string =>
        Boolean(suburb)
      ),
    ),
  ];
  const resolvedNames = await Promise.all(suburbNames.map(async (suburb) => {
    const resolved = await resolveNswSuburb(suburb);
    const canonicalName = resolved?.is_active &&
        resolved.suburb_id === suburbId
      ? resolved.canonical_name
      : null;
    return [suburb, canonicalName] as const;
  }));
  const canonicalNameByReturnedName = new Map(resolvedNames);

  return places.flatMap((place) => {
    if (!place.suburb) return [];
    const canonicalName = canonicalNameByReturnedName.get(place.suburb);
    return canonicalName ? [{ ...place, suburb: canonicalName } as T] : [];
  });
}
