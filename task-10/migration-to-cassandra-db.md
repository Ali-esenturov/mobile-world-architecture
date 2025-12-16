# Migration to leaderless type DB (Cassandra)

## 10.1 Данные и требования к ним

| Данные                  | Критичность целостности | Критичность latency |
| ----------------------- | ----------------------- | ------------------- |
| Активные корзины        | высокая                 | очень высокая       |
| Создание заказов        | высокая                 | высокая             |
| Остатки товаров         | высокая                 | высокая             |
| Каталог товаров         | средняя                 | высокая             |
| История заказов         | средняя                 | средняя             |
| Пользовательские сессии | низкая                  | высокая             |

Наиболее подходит для Cassandra:
- Carts
- Orders
- Products (каталог)
- Products stock (остатки)

## 10.2 Концептуальная модель данных для критичных сущностей

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


### Orders
```js
orders (
  user_id TEXT,
  order_date TIMESTAMP,
  order_id UUID,
  status TEXT,
  total_sum DECIMAL,
  PRIMARY KEY ((user_id), order_date, order_id)
)
```

Обоснование:
- доступ по пользователю
- временная сортировка
- контролируемый рост партиций


### Products (каталог, без остатков)
```js
products_catalog (
  product_id UUID,
  name TEXT,
  category TEXT,
  price DECIMAL,
  attributes MAP<TEXT, TEXT>,
  PRIMARY KEY ((product_id))
)
```

Обоснование:
- равномерный partition key
- read-heavy
- без бизнес-инвариантов


### Products Stock (остатки)
```js
product_stock_by_geo (
  product_id UUID,
  geo TEXT,
  available INT,
  reserved INT,
  PRIMARY KEY ((product_id), geo)
)
```

Обоснование:
- операции по конкретному товару
- ограниченное число geo

## 10.3 Стратегии обеспечения целостности

Hinted Handoff используем для:
- Carts

Почему:
- минимальный latency

Read Repair используем для:
- Products catalog

Почему:
- read-heavy
- можно чинить данные при чтении

Anti-Entropy Repair используем для:
- Orders
- Products stock (остатки)

Почему
- критичная целостность
- допустим фоновый repair
- используется по расписанию
