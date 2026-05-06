/**
 * fic-urls.js
 *
 * Stable, well-known multi-chapter fanfic URLs used as load test targets.
 * Each VU in scrape-pipeline-test.js owns one URL and fires a scrape job
 * against the Astral backend, then polls for completion.
 *
 * All works are 50+ chapters and long-running on their respective platforms.
 */

// 15 AO3 works — kudos-heavy, multi-chapter, stable IDs
export const AO3_URLS = [
  // Harry Potter
  "https://archiveofourown.org/works/1335295",  // All the Young Dudes (HP, 70+ chapters)
  "https://archiveofourown.org/works/6637061",  // The Shoebox Project (HP/Marauders)
  "https://archiveofourown.org/works/5936666",  // Hermione Granger's Hogwarts Crammer (HP)
  // Supernatural
  "https://archiveofourown.org/works/2002705",  // Twist and Shout (SPN, 2 long parts)
  "https://archiveofourown.org/works/1009033",  // The Best Years of Our Lives (SPN, 80+ chapters)
  // MCU / Avengers
  "https://archiveofourown.org/works/7565728",  // Infinite Coffee and Protection Detail (MCU)
  "https://archiveofourown.org/works/1499253",  // Fourth Wall (MCU, 100+ chapters)
  "https://archiveofourown.org/works/11592927", // Bucky Barnes Has His Shit Together (MCU)
  // Teen Wolf
  "https://archiveofourown.org/works/857439",   // Navigating This Space Between Us (TW)
  "https://archiveofourown.org/works/896519",   // Pack Up; Don't Stray (TW, 50+ chapters)
  // Sherlock
  "https://archiveofourown.org/works/404611",   // Performance in a Leading Role (Sherlock)
  "https://archiveofourown.org/works/1064698",  // The Progress of Sherlock Holmes (Sherlock)
  // Haikyuu
  "https://archiveofourown.org/works/4523974",  // say it with me (don't assume) (Haikyuu)
  // One Direction (RPF — among AO3's most-kudosed)
  "https://archiveofourown.org/works/1141624",  // Relief Next to Me (1D RPF, 70 chapters)
  // Naruto
  "https://archiveofourown.org/works/2494350",  // Team Tensai (Naruto, time-travel fix-it)
];

// 15 FFNet stories — sorted-by-favorites, 50–800+ chapters, extremely well-known
export const FFNET_URLS = [
  // Harry Potter
  "https://www.fanfiction.net/s/5782108/1/Harry-Potter-and-the-Methods-of-Rationality",  // HPMoR (~122 ch)
  "https://www.fanfiction.net/s/3401052/1/Naruto-Namikaze-Rikudou-Sennin-Reborn",        // popular Naruto AU (~70 ch)
  "https://www.fanfiction.net/s/4536005/1/A-Black-Comedy",                                // HP Black Comedy (~30 ch)
  "https://www.fanfiction.net/s/2680093/1/Make-A-Wish",                                   // HP Make A Wish (50 ch)
  "https://www.fanfiction.net/s/6351458/1/Oh-God-Not-Again",                              // HP Oh God Not Again (50 ch)
  // Naruto
  "https://www.fanfiction.net/s/4437151/1/Team-8",                                        // Team 8 Naruto (30+ ch)
  "https://www.fanfiction.net/s/6538890/1/Naruto-Shippuden-Ultimate-Ninja-Hero",          // Naruto AU
  "https://www.fanfiction.net/s/5193644/1/The-Sealed-Kunai",                              // Naruto Sealed Kunai (40 ch)
  // Bleach
  "https://www.fanfiction.net/s/6192111/1/Hogyoku-ex-Machina",                            // Bleach HxM (19+ ch)
  // Dragon Ball Z
  "https://www.fanfiction.net/s/6209735/1/Dragon-Ball-Z-Return-of-the-Legendary",        // DBZ long AU
  // Pokémon
  "https://www.fanfiction.net/s/2512316/1/Ashes-of-the-Past",                             // Ash of the Past (~300 ch)
  // Star Wars
  "https://www.fanfiction.net/s/3964771/1/Darth-Vader-Hero-of-Naboo",                    // Vader AU (~50 ch)
  // Avatar: The Last Airbender
  "https://www.fanfiction.net/s/5765515/1/The-Tea-Shoppe",                                // ATLA (~30 ch)
  // One Piece
  "https://www.fanfiction.net/s/7578441/1/This-Bites",                                   // One Piece This Bites (~100 ch)
  // Fairy Tail
  "https://www.fanfiction.net/s/8109670/1/Fairy-Without-Wings",                           // Fairy Tail long AU (~170 ch)
];
