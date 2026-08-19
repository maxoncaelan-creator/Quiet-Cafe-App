// Google Places Text Search areas the pipeline queries, one request (plus
// pagination, see places.js) per entry. Text Search has no radius/bounding-
// box mode worth using here — it's driven by the text query — so broad
// coverage means a curated list of place names rather than one shape.
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
  'restaurants in Sydney CBD NSW',
  'restaurants in Surry Hills NSW',
  'restaurants in Darlinghurst NSW',
  'restaurants in Newtown NSW',
  'restaurants in Glebe NSW',
  'restaurants in Pyrmont NSW',
  'restaurants in Redfern NSW',
  'restaurants in Chippendale NSW',

  // Eastern suburbs
  'restaurants in Bondi NSW',
  'restaurants in Bondi Junction NSW',
  'restaurants in Coogee NSW',
  'restaurants in Double Bay NSW',
  'restaurants in Randwick NSW',
  'restaurants in Maroubra NSW',

  // Inner west
  'restaurants in Leichhardt NSW',
  'restaurants in Balmain NSW',
  'restaurants in Marrickville NSW',
  'restaurants in Ashfield NSW',
  'restaurants in Burwood NSW',
  'restaurants in Strathfield NSW',

  // North Shore & Northern Beaches
  'restaurants in North Sydney NSW',
  'restaurants in Chatswood NSW',
  'restaurants in Mosman NSW',
  'restaurants in Manly NSW',
  'restaurants in Dee Why NSW',
  'restaurants in Hornsby NSW',
  'restaurants in Ryde NSW',

  // Hills District
  'restaurants in Castle Hill NSW',
  'restaurants in Baulkham Hills NSW',
  'restaurants in Rouse Hill NSW',

  // Western Sydney
  'restaurants in Parramatta NSW',
  'restaurants in Blacktown NSW',
  'restaurants in Penrith NSW',
  'restaurants in Auburn NSW',
  'restaurants in Bankstown NSW',
  'restaurants in Fairfield NSW',
  'restaurants in Liverpool NSW',
  'restaurants in Cabramatta NSW',

  // South-west Sydney & Macarthur
  'restaurants in Campbelltown NSW',
  'restaurants in Camden NSW',
  'restaurants in Narellan NSW',

  // Sutherland Shire & St George
  'restaurants in Sutherland NSW',
  'restaurants in Cronulla NSW',
  'restaurants in Hurstville NSW',
  'restaurants in Kogarah NSW',

  // Blue Mountains (within Greater Sydney)
  'restaurants in Katoomba NSW',

  // North — Central Coast & Newcastle/Hunter
  'restaurants in Gosford NSW',
  'restaurants in The Entrance NSW',
  'restaurants in Newcastle NSW',
  'restaurants in Merewether NSW',
  'restaurants in Maitland NSW',

  // West — out to Dubbo
  'restaurants in Lithgow NSW',
  'restaurants in Bathurst NSW',
  'restaurants in Orange NSW',
  'restaurants in Dubbo NSW',

  // South — Southern Highlands to Moss Vale
  'restaurants in Campbelltown NSW',
  'restaurants in Picton NSW',
  'restaurants in Mittagong NSW',
  'restaurants in Bowral NSW',
  'restaurants in Moss Vale NSW',

  // Illawarra — down to Kiama
  'restaurants in Wollongong NSW',
  'restaurants in Shellharbour NSW',
  'restaurants in Kiama NSW',
];
