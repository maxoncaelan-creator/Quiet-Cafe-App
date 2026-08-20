// Google Places Text Search areas the pipeline queries, one request (plus
// pagination, see places.js) per entry. Text Search has no radius/bounding-
// box mode worth using here — it's driven by the text query — so broad
// coverage means a curated list of place names rather than one shape.
//
// Query text covers restaurants, cafes, pubs and bars in one request per
// area (Caelan, 2026-08-20) — previously said "restaurants in <area>" only,
// which is why cafes turned up inconsistently (Text Search ranks by
// relevance to the query text, so a place typed "cafe" competed poorly
// against literal "restaurant" matches) and pubs/bars didn't turn up at
// all. Broadening the query text costs nothing extra in requests — still
// one search per area — versus a separate query per category, which would
// have multiplied the request budget (and Google Places API bill) by
// roughly the number of categories added.
//
// Scope confirmed with Caelan 2026-08-19: Greater Sydney, plus out to Dubbo,
// north to Newcastle, south to Moss Vale, and into the Illawarra as far as
// Kiama. This list is regional/suburb-level, not exhaustive — Greater Sydney
// alone has 600+ gazetted suburbs, and hand-curating all of them isn't
// practical. It's a representative spread across each region so the app has
// real coverage everywhere in scope; extend this list (or swap in a proper
// suburb dataset, e.g. the ABS SA2/locality list) if a specific suburb
// user testing turns up is missing results.

export const SEARCH_AREAS = [
  // Sydney CBD & inner city
  'restaurants, cafes, pubs and bars in Sydney CBD NSW',
  'restaurants, cafes, pubs and bars in Surry Hills NSW',
  'restaurants, cafes, pubs and bars in Darlinghurst NSW',
  'restaurants, cafes, pubs and bars in Newtown NSW',
  'restaurants, cafes, pubs and bars in Glebe NSW',
  'restaurants, cafes, pubs and bars in Pyrmont NSW',
  'restaurants, cafes, pubs and bars in Redfern NSW',
  'restaurants, cafes, pubs and bars in Chippendale NSW',

  // Eastern suburbs
  'restaurants, cafes, pubs and bars in Bondi NSW',
  'restaurants, cafes, pubs and bars in Bondi Junction NSW',
  'restaurants, cafes, pubs and bars in Coogee NSW',
  'restaurants, cafes, pubs and bars in Double Bay NSW',
  'restaurants, cafes, pubs and bars in Randwick NSW',
  'restaurants, cafes, pubs and bars in Maroubra NSW',

  // Inner west
  'restaurants, cafes, pubs and bars in Leichhardt NSW',
  'restaurants, cafes, pubs and bars in Balmain NSW',
  'restaurants, cafes, pubs and bars in Marrickville NSW',
  'restaurants, cafes, pubs and bars in Ashfield NSW',
  'restaurants, cafes, pubs and bars in Burwood NSW',
  'restaurants, cafes, pubs and bars in Strathfield NSW',

  // North Shore & Northern Beaches
  'restaurants, cafes, pubs and bars in North Sydney NSW',
  'restaurants, cafes, pubs and bars in Chatswood NSW',
  'restaurants, cafes, pubs and bars in Mosman NSW',
  'restaurants, cafes, pubs and bars in Manly NSW',
  'restaurants, cafes, pubs and bars in Dee Why NSW',
  'restaurants, cafes, pubs and bars in Hornsby NSW',
  'restaurants, cafes, pubs and bars in Ryde NSW',

  // Hills District
  'restaurants, cafes, pubs and bars in Castle Hill NSW',
  'restaurants, cafes, pubs and bars in Baulkham Hills NSW',
  'restaurants, cafes, pubs and bars in Rouse Hill NSW',

  // Western Sydney
  'restaurants, cafes, pubs and bars in Parramatta NSW',
  'restaurants, cafes, pubs and bars in Blacktown NSW',
  'restaurants, cafes, pubs and bars in Penrith NSW',
  'restaurants, cafes, pubs and bars in Auburn NSW',
  'restaurants, cafes, pubs and bars in Bankstown NSW',
  'restaurants, cafes, pubs and bars in Fairfield NSW',
  'restaurants, cafes, pubs and bars in Liverpool NSW',
  'restaurants, cafes, pubs and bars in Cabramatta NSW',

  // South-west Sydney & Macarthur
  'restaurants, cafes, pubs and bars in Campbelltown NSW',
  'restaurants, cafes, pubs and bars in Camden NSW',
  'restaurants, cafes, pubs and bars in Narellan NSW',

  // Sutherland Shire & St George
  'restaurants, cafes, pubs and bars in Sutherland NSW',
  'restaurants, cafes, pubs and bars in Cronulla NSW',
  'restaurants, cafes, pubs and bars in Hurstville NSW',
  'restaurants, cafes, pubs and bars in Kogarah NSW',

  // Blue Mountains (within Greater Sydney)
  'restaurants, cafes, pubs and bars in Katoomba NSW',

  // North — Central Coast & Newcastle/Hunter
  'restaurants, cafes, pubs and bars in Gosford NSW',
  'restaurants, cafes, pubs and bars in The Entrance NSW',
  'restaurants, cafes, pubs and bars in Newcastle NSW',
  'restaurants, cafes, pubs and bars in Merewether NSW',
  'restaurants, cafes, pubs and bars in Maitland NSW',

  // West — out to Dubbo
  'restaurants, cafes, pubs and bars in Lithgow NSW',
  'restaurants, cafes, pubs and bars in Bathurst NSW',
  'restaurants, cafes, pubs and bars in Orange NSW',
  'restaurants, cafes, pubs and bars in Dubbo NSW',

  // South — Southern Highlands to Moss Vale
  'restaurants, cafes, pubs and bars in Campbelltown NSW',
  // Not just "Picton NSW" — that also matched Picton, New Zealand and
  // Picton, Ontario in the 2026-08-19 live run (real namesake towns, not a
  // parsing bug). extractSuburbFromAddress correctly excluded them, but a
  // more specific query avoids paying for the wrong-country results at all.
  'restaurants, cafes, pubs and bars in Picton, New South Wales, Australia',
  'restaurants, cafes, pubs and bars in Mittagong NSW',
  'restaurants, cafes, pubs and bars in Bowral NSW',
  'restaurants, cafes, pubs and bars in Moss Vale NSW',

  // Illawarra — down to Kiama
  'restaurants, cafes, pubs and bars in Wollongong NSW',
  'restaurants, cafes, pubs and bars in Shellharbour NSW',
  'restaurants, cafes, pubs and bars in Kiama NSW',
];
