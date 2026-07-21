# Процедурная генерация — как расширять

Новый контент = новый `.tres` в папке. Код трогать не нужно.

| Папка | Ресурс | Эффект |
|-------|--------|--------|
| `data/rooms/` | RoomDef | Новая комната в квартире |
| `data/objects/` | ObjectDef | Мебель / job-предметы |
| `data/missions/` | MissionDef | Тип заказа |
| `data/difficulties/` | DifficultyDef | Сложность в меню |
| `data/events/` | EventDef | Случайные события смены |

## Классы

- `LevelGenerator` — собирает уровень
- `RoomLibrary` / `ObjectLibrary` — читают папки
- `MissionGenerator` — план заказа
- `RandomEventRunner` — события во время смены
- `RoomFabricator` — комната-бокс, если у RoomDef нет своей сцены

## Своя сцена комнаты

В RoomDef укажи `scene` (PackedScene). В сцене желательны маркеры:
- `PlayerSpawn`
- `DeliveryAnchor`
- `FurnitureSpawn_*` (группа `furniture_spawn`)
