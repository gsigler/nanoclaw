---
name: tendy
description: Use the tendy garden-tracking MCP server. Invoke when the user wants to manage gardens, seasons, plantings, tasks, harvests, or catalog entries in tendy.
---

# Tendy MCP — Garden Tracker

Tendy is a personal garden tracker. Data is organized hierarchically:

```
Garden → Season → Spaces (raised beds, trays, etc.)
                → Plantings (individual crops)
                    → Tasks, Events, Harvests
```

## Connecting

The MCP server is at the tendy API base URL, using SSE transport:
- **SSE endpoint:** `GET /mcp`
- **Message endpoint:** `POST /mcp/message?sessionId=<id>`
- **Auth:** `Authorization: Bearer <token>`

Tokens can be a **JWT** (from `POST /api/v1/auth/login`) or a **tendy API key** (prefix `tndy_`, created via `POST /api/v1/api-keys`). For long-running agents, use an API key so it doesn't expire.

Claude Desktop / MCP client config:
```json
{
  "mcpServers": {
    "tendy": {
      "url": "https://your-tendy-url.com/mcp",
      "headers": {
        "Authorization": "Bearer tndy_your_api_key_here"
      }
    }
  }
}
```

---

## Data Model

| Entity | Key fields |
|--------|-----------|
| **Garden** | id, name, location, hardinessZone, latitude, longitude |
| **Season** | id, gardenId, year, name, status (planning/active/complete), lastFrostDate, firstFrostDate |
| **Space** | id, seasonId, name, type (RaisedBed/Tray/Container/RowBed/Shelf/HardeningArea), width, length, unit, sunExposure |
| **Planting** | id, seasonId, spaceId, crop, variety, sourceType (seed/start), stage, health, quantity |
| **Task** | id, seasonId, title, type, priority, status, dueAt, plantingId, spaceId |
| **Event** | id, seasonId, type, summary, plantingId, spaceId, happenedAt |
| **Harvest** | id, seasonId, plantingId, spaceId, crop, variety, quantity, weightOz, quality |
| **Catalog Entry** | id, crop, variety, vendor, daysToMaturity, startIndoorsWeeks, minNightTemp, spacingInches |

**Planting stages (in order):** `planned` → `seeded_indoors` → `seedling` → `hardening_off` → `transplanted` / `direct_sown` → `producing` → `finished` | `failed`

---

## Tool Reference

### Gardens
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listGardens` | — | Lists all user gardens |
| `getGarden` | gardenId | |
| `createGarden` | name*, location, hardinessZone, latitude, longitude | |
| `updateGarden` | gardenId*, name, location, hardinessZone, lat/lng | Partial update |
| `deleteGarden` | gardenId* | **Cascade** — deletes everything inside |

### Seasons
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listSeasons` | gardenId* | Ordered year desc |
| `getSeason` | seasonId* | |
| `createSeason` | gardenId*, year*, name*, lastFrostDate, firstFrostDate | Upserts on garden+year+name |
| `updateSeason` | seasonId*, lastFrostDate, firstFrostDate, status | |
| `deleteSeason` | seasonId* | **Cascade** |
| `getSeasonSummary` | seasonId* | Spaces, planting counts by stage, task counts |

### Spaces
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listSpaces` | seasonId* | |
| `getSpace` | spaceId* | |
| `createSpace` | seasonId*, name*, type*, width, length, unit, sunExposure, posX, posY, notes | Upserts on season+name |
| `updateSpace` | spaceId*, name, type, width, length, posX, posY, sunExposure, notes | |
| `deleteSpace` | spaceId* | Plantings unlinked, grid placements removed |
| `getSpaceGrid` | spaceId* | Grid layout with cell occupancy |
| `placeOnGrid` | spaceId*, plantingId*, cells* (`[{row,col}]`) | Assigns planting to specific cells |
| `removeFromGrid` | spaceId*, plantingId* | |

### Plantings
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listPlantings` | seasonId*, stage (optional filter) | |
| `getPlanting` | plantingId* | |
| `createPlanting` | seasonId*, crop*, variety, sourceType, spaceId, quantity, notes | Auto-links catalog entry if match found |
| `updatePlanting` | plantingId*, variety, quantity, quantityUnit, notes | Not for stage/health changes |
| `advancePlantingStage` | plantingId*, newStage*, date (ISO, optional) | Auto-sets timestamps, logs event |
| `updatePlantingHealth` | plantingId*, health*, reason | health: healthy/fair/poor/critical/dead |
| `movePlanting` | plantingId*, newSpaceId* | Clears grid placements in old space |
| `deletePlanting` | plantingId* | |

### Tasks
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listTasks` | seasonId*, status (pending/completed/skipped) | Includes overdue flag |
| `getTask` | taskId* | |
| `createTask` | seasonId*, title*, type, priority, dueAt, plantingId, spaceId, notes | type: seed_start/transplant/check/harvest/maintenance/other |
| `updateTask` | taskId*, title, priority, dueAt, notes | |
| `completeTask` | taskId* | Sets completedAt |
| `skipTask` | taskId* | |
| `deleteTask` | taskId* | |

### Events
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listRecentEvents` | seasonId*, limit (default 20, max 100) | Most recent first |
| `recordEvent` | seasonId*, type*, summary*, plantingId, spaceId, data | type: observation/watering/fertilizing/pest/disease/weather/stage_change/planting/maintenance/other |
| `deleteEvent` | eventId* | |

### Harvests
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `listHarvests` | seasonId* | Most recent first |
| `getHarvest` | harvestId* | |
| `recordHarvest` | seasonId*, crop*, variety, plantingId, spaceId, quantity, quantityUnit, weightOz, harvestedAt, quality, notes | If plantingId given, crop/variety auto-filled |
| `updateHarvest` | harvestId*, quantity, quantityUnit, weightOz, harvestedAt, quality, notes | |
| `deleteHarvest` | harvestId* | |
| `getHarvestSummary` | seasonId* | Totals grouped by crop/variety |

### Catalog
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `searchCatalog` | query* | Case-insensitive crop name search |
| `getCatalogEntry` | catalogId* | |
| `createCatalogEntry` | crop*, variety, vendor, sourceType, daysToMaturity, startIndoorsWeeks, minNightTemp, spacingInches, plantsPerSquare, sun, growthHabit, notes | |
| `updateCatalogEntry` | catalogId*, vendor, daysToMaturity, startIndoorsWeeks, minNightTemp, spacingInches, plantsPerSquare, sun, rating (1-5), wouldGrowAgain (0/1), yieldNotes, notes | |
| `deleteCatalogEntry` | catalogId* | Plantings unlinked, not deleted |

### Planning
| Tool | Key inputs | Notes |
|------|-----------|-------|
| `getWeekPlan` | seasonId* | Overdue + next 7 days tasks, active plantings |
| `getPlantingSchedule` | seasonId* | Computed start/harden/transplant/harvest dates per planting. Requires lastFrostDate |
| `generateAutoTasks` | seasonId* | Creates seed_start + transplant tasks from catalog data. Requires lastFrostDate. Deduplicates |

*\* = required*

---

## Common Workflows

### New season setup
```
1. createGarden (if needed)
2. createSeason { gardenId, year, name, lastFrostDate, firstFrostDate }
3. createSpace (for each bed/tray)
4. createPlanting (for each crop)
5. generateAutoTasks → creates seed start + transplant reminders
```

### Log what happened today
```
- advancePlantingStage → moves a planting forward (seeded, transplanted, etc.)
- recordHarvest → logs a harvest with weight/quantity
- recordEvent { type: "observation", summary: "..." } → freeform notes
- updatePlantingHealth → flag a sick plant
- completeTask / skipTask → mark off today's tasks
```

### Weekly planning
```
1. getWeekPlan → overdue tasks + next 7 days
2. listTasks { status: "pending" } → full pending list
3. getSeasonSummary → high-level season health
```

### Season retrospective
```
1. getHarvestSummary → totals by crop
2. listRecentEvents → what happened throughout season
3. updateCatalogEntry → record rating, yieldNotes, wouldGrowAgain
4. updateSeason { status: "complete" }
```

---

## Tips

- `createSeason` and `createSpace` are **upserts** — safe to call again with same identifiers
- `advancePlantingStage` with `date` is useful for logging past actions accurately (e.g., "I seeded these last Tuesday")
- `generateAutoTasks` is idempotent — it skips tasks that already exist, and deduplicates across plantings of the same crop+variety
- `placeOnGrid` cells are zero-indexed `{row, col}` within the space dimensions
- `getPlantingSchedule` requires the season to have `lastFrostDate` set and plantings to have matching catalog entries with `startIndoorsWeeks` / `daysToMaturity`
- Always use `getSeasonSummary` first to orient yourself in a new season before taking actions
