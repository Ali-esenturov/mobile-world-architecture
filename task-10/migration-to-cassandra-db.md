# Migration to leaderless type DB (Cassandra)

## 10.1 Данные и требования к ним

Наиболее подходит для Cassandra ввиду скорости и масштабируемости во время пиковых периодов:
- Carts
- User sessions

Не подходят поскольку требуют транзакционной обработки (создание заказа и уменьшение остатков):
- Orders
- Products

## 10.2 Концептуальная модель данных для подходящих сущностей и обоснование

### Carts
```js
carts (
  owner_id TEXT,
  status TEXT,
  updated_at TIMESTAMP,
  items MAP<TEXT, INT>,
  PRIMARY KEY ((owner_id), status)
)
```

Обоснование:
- быстрые read/write
- owner_id обеспечивает равномерное распределение
- нет hot partitions
- масштабирование без reshuffle

### User sessions
```js
user_sessions (
  session_id UUID,
  created_at TIMESTAMP,
  last_access TIMESTAMP,
  data MAP<TEXT, TEXT>,
  PRIMARY KEY (session_id)
)
```

Обоснование:
- равномерное распределение по session_id
- быстрые read/write-heavy
- нет бизнес-инвариантов, не нужна строгая ACID


## 10.3 Стратегии обеспечения целостности

### Carts

Выбранная стратегия:
- Consistency Level: LOCAL_QUORUM + Read Repair + Hinted Handoff
- Anti-Entropy Repair — опционально

Почему:
- Потеря актуальной корзины = потеря выручки → высокая вероятность актуальных данных важнее минимального latency
- LOCAL_QUORUM обеспечивает ~99% актуальности при чтении/записи
- Read Repair и Hinted Handoff помогают исправлять расхождения и не терять обновления при сбоях
- Anti-Entropy Repair для Carts не критичен, так как данные short-lived

Компромисс:
- Более высокая нагрузка на latency при записи и чтении, но критично для бизнеса.

### User sessions

Выбранная стратегия:
- Consistency Level: ONE + Hinted Handoff
- Read Repair и Anti-Entropy Repair — не используем

Почему:
- eventual consistency допустима
- основная цель — минимальный latency и быстрая обработка read/write-heavy операций
- Hinted Handoff защищает от потери сессий при временных сбоях узлов.

Компромисс:
- Возможна небольшая несогласованность между репликами, но это допустимо
- Максимальная скорость и минимальное время отклика
