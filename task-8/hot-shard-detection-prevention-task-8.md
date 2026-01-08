# MongoDB Hot Shard Detection and Prevention

## Проблема
Категория **«Электроника»** генерирует до 70% запросов к коллекции `products`.
Несмотря на равномерный shard key (`_id: hashed`), высокая концентрация read/write операций по популярной категории приводит к перегрузке одного из шардов.

Цель — **выявлять hot shards и автоматически устранять дисбаланс**, а также иметь метрики для раннего обнаружения проблемы.

---

## 1. Метрики мониторинга шардов

### 1.1 Метрики нагрузки

| Метрика | Описание | Источник |
|------|---------|---------|
| ops/sec per shard | Количество операций чтения/записи | `mongostat` |
| read/write latency | Среднее и p95 время операций | MongoDB Atlas / FTDC |
| active connections | Количество активных подключений | `serverStatus.connections` |
| queue length | Очереди операций | `serverStatus.globalLock` |

---

### 1.2 Метрики дисбаланса данных

| Метрика | Описание | Операции |
|------|---------|---------|
| chunks per shard | Количество чанков | `sh.status()` |
| data size per shard | Размер данных | `db.stats()` |
| jumbo chunks | Нечитаемые чанки | `config.chunks` |

---

### 1.3 Метрики hot-query patterns

| Метрика | Описание | Источник |
|------|---------|----------|
| top slow queries | Часто выполняемые запросы | profiler |
| category query ratio | % запросов по category | app metrics |

---

## 2. Выявление «горячих» шардов

Shard считается «горячим», если выполняется **хотя бы одно условие**:

- ops/sec > среднего по кластеру на 30%
- p95 latency выше SLA
- disproportionate number of chunks
- рост CPU при стабильной нагрузке кластера

---

## 3. Стратегии устранения дисбаланса

### 3.1 Перераспределение чанков (balancer)

Убедиться, что balancer включён:
```js
sh.getBalancerState()
sh.startBalancer()
```

Balancer:
- работает в фоне
- перераспределяет чанки между шардами

---

### 3.2 Изменение shard key

Если категория Electronics стабильно создает неравномерную нагрузку
при добавлении category в shard key

```js
{ category: 1, _id: "hashed" }
```

Можно использовать подход Zone Sharding

```js
sh.addShardToZone("shard1", "electronics_zone")
sh.addShardToZone("shard2", "electronics_zone")

sh.updateZoneKeyRange(
  "db.products",
  { category: "Electronics", _id: MinKey },
  { category: "Electronics", _id: MaxKey },
  "electronics_zone"
)
```

В таком случае новые Electronics документы будут жить на shard1 и shard2 
и сразу попадать в эту изолированную зону и равномерно распределяться между шардами

Это позволяет:
- изолировать hot-категории
- масштабировать только конкретные зоны

---

### 3.3 Read Replicas + Cache

- Redis / CDN для product pages
- MongoDB read preference: `secondaryPreferred`

```js
readPreference=secondaryPreferred
```

---

## 4. Автоматизация и алерты

### Примеры алертов

| Условие | Действие |
|------|---------|
| shard ops/sec > 1.5x avg | alert |
| latency p95 > SLA | alert |
| chunks imbalance > 20% | rebalance |


---

## Итог

Предложенная стратегия позволяет:
- рано выявлять «горячие» шарды
- автоматически перераспределять нагрузку
- масштабировать популярные категории без деградации всего кластера
